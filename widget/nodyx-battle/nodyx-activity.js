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

  var cb = {
    lobby: null, speaking: null, message: null, snapshot: null, matchStart: null,
    syncRequest: null
  }

  // --- persistance (records perso + classement d'instance) --------
  // La frame est SAME-ORIGIN avec l'instance : elle appelle /storage
  // directement (le port ne sert qu'au temps-reel). Jeton court passe dans
  // le boot, re-emis via l'evenement 'session'.
  // Cf SPECS/NODYX_ACTIVITIES_CDC.md §10.
  var stg = { url: '', surface: '', token: null }
  var stgCache = {}   // "scope/key" -> valeur JSON deja lue

  function stgKey(scope, key) { return String(scope) + '/' + String(key) }

  function stgFetch(op, scope, key, value, retried) {
    if (!stg.url || !stg.token) {
      // pas encore de jeton : on en redemande un a l'hote et on abandonne
      // cet appel (le jeu reessaiera au prochain evenement).
      portSend('session.refresh')
      return Promise.resolve(null)
    }
    var body = { op: op, scope: scope, key: key }
    if (op === 'set') body.value = value
    return fetch(stg.url, {
      method: 'POST',
      headers: {
        'authorization': 'Bearer ' + stg.token,
        'x-nodyx-surface': stg.surface,
        'content-type': 'application/json'
      },
      body: JSON.stringify(body)
    }).then(function (res) {
      if (res.status === 401 && !retried) {
        // jeton expire en pleine partie : on en redemande un, une seule fois.
        portSend('session.refresh')
        return new Promise(function (r) { setTimeout(r, 600) })
          .then(function () { return stgFetch(op, scope, key, value, true) })
      }
      if (!res.ok) return null
      return res.json().then(function (j) { return j ? j.result : null })
    }).catch(function () { return null })
  }

  var storage = {
    load: function (scope, key) {
      return stgFetch('get', scope, key, null, false).then(function (v) {
        stgCache[stgKey(scope, key)] = (v === undefined ? null : v)
        return v
      })
    },
    save: function (scope, key, valueJson) {
      var v
      try { v = JSON.parse(valueJson) } catch (_) { return Promise.resolve(null) }
      stgCache[stgKey(scope, key)] = v
      return stgFetch('set', scope, key, v, false)
    },
    read: function (scope, key) {
      var k = stgKey(scope, key)
      return JSON.stringify(k in stgCache ? stgCache[k] : null)
    }
  }

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
    if (window.NodyxBattle) window.NodyxBattle.__matchRunning = true
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
      case 'session':
        // L'hote a frappe un jeton frais (le notre a expire, ou il n'etait
        // pas pret au boot). On rejoue les lectures en cache.
        stg.token = d.token || null
        break
      case 'sync':
        // Un arrivant demande l'etat courant : seul le host repond.
        if (isHostNow()) {
          if (matchStarted) {
            room.send({ k: 'match_start', seed: currentSeed })
            // laisse MatchDirector renvoyer l'etat detaille (manche, phase, PV)
            if (cb.syncRequest) cb.syncRequest(String(d.from || ''))
          } else {
            fireLobby()
          }
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
    __matchRunning: false,

    me: function () {
      if (!BOOT || !BOOT.user) return { id: '', name: '', avatar: '', avatar_png: '' }
      var mine = roster.get(selfId())
      return {
        id: selfId(),
        name: String(BOOT.user.name || (mine ? mine.name : '')),
        avatar: String(BOOT.user.avatar || ''),
        avatar_png: mine ? (mine.avatar_png || '') : ''
      }
    },
    // JSON de me(), pour Godot qui lit `window.NodyxBattle.meJson()` via
    // JavaScriptBridge.eval (utile hors partie : solo, contre l'IA).
    meJson: function () { return JSON.stringify(window.NodyxBattle.me()) },
    isHost: function () { return isHostNow() },

    onLobby:      function (fn) { cb.lobby = fn; if (ready) fireLobby() },
    onSpeaking:   function (fn) {
      cb.speaking = fn
      for (var id in speakingIds) if (speakingIds.hasOwnProperty(id)) fn(id, true)
    },
    onMessage:    function (fn) { cb.message = fn },
    onSnapshot:   function (fn) { cb.snapshot = fn },
    // Rejoue immediatement si un match est deja en cours : un client qui
    // (re)demarre a froid lie ce callback APRES avoir recu match_start.
    onMatchStart: function (fn) {
      cb.matchStart = fn
      if (matchStarted && fn) fn(currentSeed, JSON.stringify(rosterArray()))
    },
    // L'hote recoit une demande de resync d'un pair (arg = son userId).
    onSyncRequest: function (fn) { cb.syncRequest = fn },

    // Persistance : records perso (scope 'user') / classement ('instance').
    storage: storage,
    loadStats:  function () { return storage.load('user', 'stats') },
    statsJson:  function () { return storage.read('user', 'stats') },
    saveStats:  function (json) { return storage.save('user', 'stats', json) },
    loadBoard:  function () { return storage.load('instance', 'leaderboard') },
    boardJson:  function () { return storage.read('instance', 'leaderboard') },
    saveBoard:  function (json) { return storage.save('instance', 'leaderboard', json) },

    // Demande explicite de resync (utilisee au (re)demarrage a froid).
    requestResume: function () { room.sync() },

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
    if (d.storage) {
      stg.url = String(d.storage.url || '')
      stg.surface = String(d.storage.surface || '')
      stg.token = d.storage.token || null
    }
    setRoster(d.members || [])
    ready = true
    window.NodyxBattle.__ready = true
    PORT.postMessage({ event: 'ready' })

    // Un client qui (re)demarre demande l'etat courant : si une partie tourne
    // deja dans ce salon, l'hote repond match_start (+ MatchDirector renvoie
    // manche / phase / PV des rois en cmd cible).
    setTimeout(function () { if (!matchStarted) room.sync() }, 400)
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
