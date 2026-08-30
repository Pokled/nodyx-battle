// nodyx-activity.js : pont "Nodyx Activities" cote jeu.
//
// Charge dans le <head> de l'export web AVANT index.js (via html/head_include),
// pour que Net._detect_backend() (scripts/net/net.gd) voie window.NodyxBattle et
// choisisse le backend "nodyx".
//
// Role : poignee de main avec la page hote Nodyx (postMessage `nodyx:hello` ->
// un port MessageChannel prive), puis exposer window.NodyxBattle (les 11
// methodes attendues par scripts/net/net_nodyx.gd) par-dessus ce port.
//
// Le lobby (qui est pret, qui lance) est un mini-protocole porte par room.send.
// Une fois `onMatchStart` tire, MatchDirector reprend la main sur le canal "cmd".
//
// L'activite n'a AUCUN socket ni token : l'hote relaie pour elle, uniquement
// dans le salon vocal ou l'utilisateur se trouve deja. Le "host" (arbitre) est
// le membre au plus petit seatIndex du salon, deterministe sur tous les clients.

(function () {
  'use strict'

  // Couleur de joueur par siege. Identique sur tous les clients : le jeu
  // (net.gd:_normalize) transforme "#rrggbb" en Color.
  var SEAT_COLORS = [
    '#6bade5', '#d9665a', '#9973d9', '#e6b84d',
    '#73cc8c', '#d98c4d', '#8cbfd9', '#cc6699'
  ]

  var PORT = null
  var BOOT = null
  var ready = false
  var matchStarted = false
  var currentSeed = 0

  var cb = { lobby: null, speaking: null, message: null, snapshot: null, matchStart: null }

  // userId -> { id, name, avatar_url, avatar_png, color, ready, _seat }
  var roster = new Map()
  var speakingIds = {}   // id -> true : micro actif

  function setSpeaking(id, on) {
    id = String(id)
    if (on) speakingIds[id] = true
    else delete speakingIds[id]
    if (cb.speaking) cb.speaking(id, !!on)
  }

  function selfId() { return BOOT && BOOT.user ? String(BOOT.user.id) : '' }

  function hostId() {
    var best = null
    roster.forEach(function (p) { if (best === null || p._seat < best._seat) best = p })
    return best ? best.id : ''
  }

  function isHostNow() { return selfId() !== '' && selfId() === hostId() }

  function rosterArray() {
    return Array.from(roster.values()).map(function (p) {
      return {
        id: p.id, name: p.name, avatar_url: p.avatar_url, avatar_png: p.avatar_png || '',
        color: p.color, is_bot: false, ready: p.ready
      }
    })
  }

  function fireLobby() { if (cb.lobby) cb.lobby(JSON.stringify(rosterArray())) }

  function upsertMember(m) {
    var id = String(m.id)
    var prev = roster.get(id)
    var seat = (typeof m.seatIndex === 'number') ? m.seatIndex : (prev ? prev._seat : roster.size)
    var n = SEAT_COLORS.length
    // avatar_png : garde l'ancien si le nouveau message ne le porte pas (il arrive
    // souvent apres coup, en member_update, une fois resolu par l'hote).
    var png = (m.avatar_png != null && m.avatar_png !== '') ? String(m.avatar_png)
            : (prev ? prev.avatar_png : '')
    roster.set(id, {
      id: id,
      name: String(m.name || (prev ? prev.name : '?')),
      avatar_url: String(m.avatar_url != null ? m.avatar_url : (prev ? prev.avatar_url : '')),
      avatar_png: png,
      color: SEAT_COLORS[((seat % n) + n) % n],
      ready: prev ? prev.ready : false,
      _seat: seat
    })
  }

  function setRoster(list) {
    roster = new Map()
    ;(list || []).forEach(function (m) {
      upsertMember(m)
      if (m && m.speaking) setSpeaking(m.id, true)
    })
    fireLobby()
  }

  // --- port : envoi vers l'hote -----------------------------------
  function portSend(type, extra) {
    if (!PORT) return
    var msg = { p: 1, type: type }
    if (extra) for (var k in extra) if (Object.prototype.hasOwnProperty.call(extra, k)) msg[k] = extra[k]
    PORT.postMessage(msg)
  }

  var room = {
    send: function (payload, opts) {
      portSend('room.send', {
        payload: payload,
        to: (opts && opts.to) || '',
        reliable: !(opts && opts.reliable === false)
      })
    },
    snapshot: function (blob) { portSend('room.snapshot', { blob: blob }) },
    sync: function () { portSend('room.sync', {}) }
  }

  function applyMatchStart(seed) {
    if (matchStarted) return
    matchStarted = true
    currentSeed = seed | 0
    // Le roster est LOCAL (chaque client a le sien, avatars compris depuis son
    // boot) : on ne le fait pas transiter par le bus (trop gros, plafonne a 8 Ko).
    if (cb.matchStart) cb.matchStart(currentSeed, JSON.stringify(rosterArray()))
  }

  // --- port : reception depuis l'hote ----------------------------
  function onPortMessage(e) {
    var d = e.data || {}
    switch (d.event) {
      case 'members':       setRoster(d.members); break
      case 'member_join':   upsertMember(d.member); fireLobby(); break
      case 'member_update': upsertMember(d.member); fireLobby(); break
      case 'member_leave':  roster.delete(String(d.member && d.member.id)); fireLobby(); break
      case 'speaking':      setSpeaking(d.userId, d.speaking); break
      case 'snap':          if (cb.snapshot) cb.snapshot(String(d.from), String(d.blob)); break
      case 'msg':           onRoomMsg(String(d.from), d.payload || {}); break
      case 'sync':
        // Un arrivant demande l'etat courant : seul le host repond.
        if (isHostNow()) {
          if (matchStarted) room.send({ k: 'match_start', seed: currentSeed })
          else fireLobby()
        }
        break
    }
  }

  function onRoomMsg(from, p) {
    if (p.k === 'lobby_ready') {
      var r = roster.get(from)
      if (r) { r.ready = !!p.on; fireLobby() }
    } else if (p.k === 'match_start') {
      applyMatchStart(p.seed)
    } else if (p.k === 'game') {
      if (cb.message) cb.message(from, String(p.ch || 'cmd'), JSON.stringify(p.body || {}))
    }
  }

  // --- window.NodyxBattle : contrat attendu par net_nodyx.gd -----
  window.NodyxBattle = {
    __ready: false,

    me: function () {
      return BOOT && BOOT.user
        ? { id: selfId(), name: String(BOOT.user.name || ''), avatar: String(BOOT.user.avatar || '') }
        : { id: '', name: '', avatar: '' }
    },
    isHost: function () { return isHostNow() },

    onLobby:      function (fn) { cb.lobby = fn; if (ready) fireLobby() },
    onSpeaking:   function (fn) {
      cb.speaking = fn
      for (var id in speakingIds) if (speakingIds.hasOwnProperty(id)) fn(id, true)
    },
    onMessage:    function (fn) { cb.message = fn },
    onSnapshot:   function (fn) { cb.snapshot = fn },
    onMatchStart: function (fn) { cb.matchStart = fn },

    ready: function (on) {
      var r = roster.get(selfId())
      if (r) r.ready = !!on
      fireLobby()
      room.send({ k: 'lobby_ready', on: !!on })
    },

    start: function (seed) {
      if (!isHostNow()) return
      room.send({ k: 'match_start', seed: seed | 0 })
      applyMatchStart(seed | 0)   // le bus n'echo pas a l'emetteur
    },

    send: function (channel, payloadJson, reliable, toId) {
      var body
      try { body = JSON.parse(payloadJson) } catch (_) { body = {} }
      room.send({ k: 'game', ch: String(channel), body: body }, { to: toId || '', reliable: reliable !== false })
    },

    sendSnapshot: function (base64) { room.snapshot(String(base64)) }
  }

  // --- poignee de main ------------------------------------------
  function onWindowMessage(e) {
    var d = e.data || {}
    if (d.type !== 'nodyx:activity-boot' || !e.ports || !e.ports.length) return
    window.removeEventListener('message', onWindowMessage)

    PORT = e.ports[0]
    PORT.onmessage = onPortMessage
    if (PORT.start) PORT.start()

    BOOT = d
    setRoster(d.members || [])
    ready = true
    window.NodyxBattle.__ready = true
    PORT.postMessage({ event: 'ready' })
  }

  window.addEventListener('message', onWindowMessage)

  // On repond `nodyx:hello` jusqu'a recevoir le port : l'hote peut ne pas encore
  // ecouter au tout premier tir (ordre de montage iframe/parent non garanti).
  var hellos = 0
  function sayHello() {
    if (PORT || hellos > 40) return
    hellos++
    try {
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: 'nodyx:hello' }, '*')
      }
    } catch (_) { /* pas de parent joignable */ }
    setTimeout(sayHello, 100)
  }
  sayHello()
})()
