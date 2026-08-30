// Banc d'essai du pont nodyx-activity.js : pur Node, sans navigateur.
//
//   node tools/test-activity-bridge.mjs
//
// Simule 2 iframes de jeu (chacune charge le shim dans un faux `window`) + un
// hote qui relaie entre elles exactement comme le fera socket/activity.ts :
// pas d'echo a l'emetteur, `to` cible un userId, payload opaque.
// Verifie : handshake, roster + couleurs par siege, detection du host (siege 0),
// propagation lobby_ready, match_start (meme seed partout), relais cmd + snapshot.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import assert from 'node:assert/strict'

const HERE = dirname(fileURLToPath(import.meta.url))
const SHIM = readFileSync(join(HERE, '../widget/nodyx-battle/nodyx-activity.js'), 'utf8')

const MEMBERS = [
  { id: 'u-alice', name: 'Alice', avatar_url: '', seatIndex: 0, speaking: false },
  { id: 'u-bob',   name: 'Bob',   avatar_url: '', seatIndex: 1, speaking: false },
]

let PASS = 0
const ok = (m) => { PASS++; console.log('  ok  ' + m) }

// --- Un faux `window` par iframe ---
function makeWindow(parentPost) {
  const listeners = new Set()
  const win = {
    NodyxBattle: undefined,
    addEventListener: (t, fn) => { if (t === 'message') listeners.add(fn) },
    removeEventListener: (t, fn) => { if (t === 'message') listeners.delete(fn) },
    parent: { postMessage: (data) => parentPost(data) },
  }
  win.parent = win.parent
  win._deliver = (data, ports) => { for (const fn of [...listeners]) fn({ data, ports: ports || [] }) }
  win.self = win
  return win
}

// --- Cote hote : un "pane" = une iframe + le port qui la relie ---
class Pane {
  constructor(user, relay) {
    this.user = user
    this.relay = relay
    this.ready = false
    this.win = makeWindow((msg) => this._fromGuestWindow(msg))
    // charge le shim dans ce faux window
    new Function('window', 'self', 'globalThis', SHIM)(this.win, this.win, globalThis)
  }
  _fromGuestWindow(msg) {
    if (msg && msg.type === 'nodyx:hello') this._boot()
  }
  _boot() {
    if (this.port) return
    const ch = new MessageChannel()
    this.port = ch.port1
    this.port.onmessage = (e) => this._fromGuest(e.data || {})
    this.win._deliver({
      p: 1, type: 'nodyx:activity-boot', activity: 'kings-race', version: 'test',
      user: this.user, members: MEMBERS, locale: 'fr', theme: {},
    }, [ch.port2])
  }
  _fromGuest(d) {
    if (d.event === 'ready') { this.ready = true; return }
    if (d.type === 'room.send')     return this.relay.send(this, d)
    if (d.type === 'room.snapshot') return this.relay.snapshot(this, d)
    if (d.type === 'room.sync')     return this.relay.sync(this)
  }
  toGuest(obj) { this.port.postMessage(obj) }
  api() { return this.win.NodyxBattle }
}

class Relay {
  constructor() { this.panes = []; this.msgCount = 0; this.snapCount = 0 }
  add(p) { this.panes.push(p) }
  send(from, d) {
    this.msgCount++
    const targets = d.to ? this.panes.filter(p => p.user.id === d.to) : this.panes.filter(p => p !== from)
    for (const t of targets) t.toGuest({ event: 'msg', from: from.user.id, payload: d.payload })
  }
  snapshot(from, d) {
    this.snapCount++
    for (const t of this.panes) if (t !== from) t.toGuest({ event: 'snap', from: from.user.id, blob: d.blob })
  }
  sync(from) { for (const t of this.panes) if (t !== from) t.toGuest({ event: 'sync', from: from.user.id }) }
}

const tick = () => new Promise(r => setTimeout(r, 5))

const relay = new Relay()
const alice = new Pane({ id: 'u-alice', name: 'Alice', avatar: '' }, relay)
const bob   = new Pane({ id: 'u-bob',   name: 'Bob',   avatar: '' }, relay)
relay.add(alice); relay.add(bob)

// capture les callbacks du jeu
const seen = { alice: {}, bob: {} }
for (const [k, p] of [['alice', alice], ['bob', bob]]) {
  p.api().onLobby((json) => { seen[k].lobby = JSON.parse(json) })
  p.api().onMatchStart((seed, json) => { seen[k].match = { seed, roster: JSON.parse(json) } })
  p.api().onMessage((from, ch, json) => { (seen[k].cmds ||= []).push({ from, ch, body: JSON.parse(json) }) })
  p.api().onSnapshot((from, b64) => { (seen[k].snaps ||= []).push({ from, b64 }) })
}

console.log('handshake + roster')
await tick()
assert.equal(alice.ready && bob.ready, true); ok('les deux shims ont fait la poignee de main')
assert.equal(alice.api().__ready && bob.api().__ready, true); ok('__ready = true des deux cotes')
assert.equal(seen.alice.lobby.length, 2); ok('roster a 2 joueurs')
assert.deepEqual(seen.alice.lobby.map(p => p.name), ['Alice', 'Bob']); ok('noms dans l\'ordre des sieges')
assert.notEqual(seen.alice.lobby[0].color, seen.alice.lobby[1].color); ok('couleurs distinctes par siege')
assert.equal(seen.alice.lobby[0].color, seen.bob.lobby[0].color); ok('memes couleurs sur les deux clients')

console.log('detection du host (siege 0)')
assert.equal(alice.api().isHost(), true);  ok('Alice (siege 0) est host')
assert.equal(bob.api().isHost(), false);   ok('Bob (siege 1) ne l\'est pas')
assert.equal(alice.api().me().id, 'u-alice'); ok('me() renvoie la bonne identite')

console.log('lobby_ready se propage')
bob.api().ready(true)
await tick()
assert.equal(seen.alice.lobby.find(p => p.id === 'u-bob').ready, true); ok('Alice voit Bob pret')
assert.equal(seen.bob.lobby.find(p => p.id === 'u-bob').ready, true);   ok('Bob se voit pret localement')

console.log('start -> match_started identique partout')
alice.api().ready(true)
await tick()
alice.api().start(123456)
await tick()
assert.equal(seen.alice.match.seed, 123456); ok('Alice entre en match, seed 123456')
assert.equal(seen.bob.match.seed, 123456);   ok('Bob entre en match, MEME seed')
assert.equal(seen.bob.match.roster.length, 2); ok('roster de match transmis')

console.log('relais du canal cmd (Net.send)')
// Alice envoie un "king" a tout le monde ; Bob doit le recevoir, pas Alice.
alice.api().send('cmd', JSON.stringify({ t: 'king', id: 'u-alice', hp: 60, max: 100 }), true, '')
await tick()
assert.equal((seen.bob.cmds || []).length, 1); ok('Bob recoit le cmd d\'Alice')
assert.deepEqual(seen.bob.cmds[0], { from: 'u-alice', ch: 'cmd', body: { t: 'king', id: 'u-alice', hp: 60, max: 100 } }); ok('payload cmd intact')
assert.equal((seen.alice.cmds || []).length, 0); ok('pas d\'echo a l\'emetteur')

console.log('envoi cible (to = userId)')
bob.api().send('cmd', JSON.stringify({ t: 'send', to: 'u-alice', troops: { grognard: 3 } }), true, 'u-alice')
await tick()
assert.equal((seen.alice.cmds || []).length, 1); ok('Alice recoit l\'envoi cible')

console.log('relais des snapshots')
bob.api().sendSnapshot(Buffer.from([1, 2, 3, 4, 5]).toString('base64'))
await tick()
assert.equal((seen.alice.snaps || []).length, 1); ok('Alice recoit le snapshot de Bob')
assert.equal(seen.alice.snaps[0].from, 'u-bob'); ok('from = l\'emetteur')

console.log(`\n${PASS} assertions vertes : le pont d'activite fait ce qu'il annonce.`)
process.exit(0)   // les MessagePort ouverts gardent la boucle Node vivante
