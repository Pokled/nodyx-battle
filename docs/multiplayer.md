# NodyxBattle — Multijoueur (jalon 1)

**Course aux rois** FFA 2-8. Chacun sa forteresse (l'arène verticale), vague neutre
partagée chaque manche + monstres envoyés par les autres joueurs, dernier roi debout.
Le jeu vit dans un **salon vocal Nodyx** : les membres du salon = le roster ; la voix
reste native Nodyx ; on ne transporte que l'état de jeu.

## Modèle de synchro : snapshot autoritaire par joueur

Chaque client simule **son** plateau avec le code de jeu normal, et diffuse un
`BoardDigest` compact ~6 Hz. Les autres l'affichent en `GhostBoard` interpolé
(spectate). Pas de lockstep déterministe (l'audit l'a chiffré à un effort L — refonte
pas-fixe + RNG seedé). Contrepartie : client autoritaire sur son propre board (OK
entre joueurs d'un même salon vocal). `MatchDirector.cmd_log` garde le journal ordonné
des commandes → base d'un validateur re-sim headless futur.

## Couches

```
Net (autoload)            abstraction transport, aucun gameplay
├── NetLocal              1 humain + K bots en process (dev/solo)   [jouable]
├── NetWs  + lobby_server relais WebSocket headless                 [localhost OK]
└── NetNodyx + widget/    pont JavaScriptBridge ⇄ window.NodyxBattle [écrit, inerte]

MatchDirector (autoload)  barrière de manche, envois ciblés, élimination, victoire
BoardDigest               capture/sérialise un plateau
GhostBoard                rend un digest (spectate)
```

Sélection du backend : `--net=<local|ws|nodyx>` (CLI) / `?net=` (web) ; défaut =
`nodyx` si `window.NodyxBattle` existe, sinon `local`.

## Canaux

| Canal | Fiabilité | Contenu |
|---|---|---|
| `cmd` | fiable, ordonné | build/round/envois/king/élimination |
| `snap` | best-effort, latest-wins | `BoardDigest.to_bytes()` |

Le bus ne renvoie PAS à l'expéditeur : `MatchDirector._broadcast_cmd` = `Net.send` +
`_apply_cmd(local)` en local.

## Messages `cmd`

| `t` | émis par | charge | effet |
|---|---|---|---|
| `ready` | joueur/bot | `{id, on}` | marque prêt ; le host tente de lancer la manche |
| `targets` | host | `{ids:[...]}` | liste des joueurs vivants (pour les bots) |
| `round_begin` | host | `{n}` | nudge : les bots/pairs relancent leur phase build |
| `round_start` | host | `{n, seed}` | tout le monde entre en COMBAT, `WaveManager.start_wave(seed)` |
| `send` | joueur/bot | `{from, to, troops:{id:n}}` | `to` ajoute à son `incoming` (spawn au round suivant) |
| `king` | joueur/bot | `{id, hp, max}` | met à jour le roi d'un joueur ; hp≤0 ⇒ host émet `eliminated` |
| `wave_done` | joueur/bot | `{id, n}` | board nettoyé ; le host tente de clore la manche |
| `round_end` | host | `{n}` | retour BUILD, `round_no+1` |
| `eliminated` | host | `{id}` | joueur passe spectateur ; si 1 vivant ⇒ `match_over` |
| `match_over` | host | `{winner}` | fin de partie |

## Barrière de manche

```
BUILD ── tous "ready" (ou deadline 60s) ──▶ round_start ──▶ COMBAT
COMBAT ── tous "wave_done" (ou straggler 20s après le 1er) ──▶ round_end ──▶ BUILD
```

Le **host** (NetLocal : le client local ; NetWs : plus ancien pair ; Nodyx :
propriétaire du salon) arbitre. Deadlines partout ; pair qui drop = auto-éliminé.

## BoardDigest

`{k,km,o,f,w,ph, tw:[[cx,cy,type_idx,lvl]], un:[[id,x,y,hp255,type_idx,team,flags]]}`
`flags` bit0=champion bit1=from_send. `type_idx` = index dans `BoardDigest.TYPES`.
J1 : `var_to_bytes`. Optim (8 joueurs) : quantif int16/uint8 + cap d'unités + 5 Hz.

## Tester

**Solo + bot**
```
Godot ... --net=local     # ou: setup ▸ COURSE AUX ROIS
```

**2 instances (localhost)**
```
# terminal 1
Godot --headless --path . --script res://scripts/net/lobby_server.gd
# terminaux 2 et 3
Godot --path . -- --net=ws --host=127.0.0.1:9871
```

**QA visuelle** : `_shot.gd` `const MODE := "versus"`.
