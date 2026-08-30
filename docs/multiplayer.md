# Multijoueur : le protocole

**Course aux rois**, FFA de 2 à 8. Chacun sa forteresse (l'arène verticale), une
vague neutre partagée chaque manche plus les monstres que les autres joueurs
t'envoient, dernier roi debout.

## Modèle de synchro : snapshot autoritaire par joueur

Chaque client simule **son** plateau avec le code de jeu normal et diffuse un
`BoardDigest` compact à environ 6 Hz. Les autres l'affichent en `GhostBoard`
interpolé (mode spectateur). Pas de lockstep déterministe : l'audit l'a chiffré à
un effort important (refonte pas-fixe, RNG seedé). Contrepartie assumée : chaque
client est autoritaire sur son propre plateau, ce qui va entre joueurs d'un même
salon vocal. `MatchDirector.cmd_log` garde le journal ordonné des commandes, base
d'un futur validateur re-sim headless.

## Couches

```
Net (autoload)              abstraction de transport, aucun gameplay
  NetLocal                  1 humain + K bots en process (dev / solo)
  NetWs + lobby_server.gd   vrais pairs via un relais WebSocket headless
  NetNodyx + nodyx-activity.js   pont vers l'hôte Nodyx (canal vocal)

MatchDirector (autoload)    barrière de manche, envois ciblés, élimination, victoire
BoardDigest                 capture et sérialise un plateau
GhostBoard                  rend un digest (mode spectateur)
```

Sélection du backend : `--net=<local|ws|nodyx>` en ligne de commande, `?net=` sur
le web. Par défaut : `nodyx` si `window.NodyxBattle` existe, sinon `local`.

## Deux canaux logiques

| Canal | Fiabilité | Contenu |
|---|---|---|
| `cmd` | fiable, ordonné | ready, transitions de manche, envois, PV du roi, élimination |
| `snap` | best-effort, dernier gagne | `BoardDigest.to_bytes()` |

Le bus ne renvoie pas à l'expéditeur : `MatchDirector._broadcast_cmd` fait
`Net.send` puis `_apply_cmd(local)` localement.

## Messages `cmd`

| `t` | émis par | charge | effet |
|---|---|---|---|
| `ready` | joueur / bot | `{id, on}` | marque prêt, le host tente de lancer la manche |
| `targets` | host | `{ids:[...]}` | liste des joueurs vivants, pour les bots |
| `round_begin` | host | `{n}` | signal : les bots et pairs relancent leur phase construction |
| `round_start` | host | `{n, seed}` | tout le monde entre en combat, `WaveManager.start_wave(seed)` |
| `send` | joueur / bot | `{from, to, troops:{id:n}}` | `to` ajoute à son `incoming`, spawn à la manche suivante |
| `king` | joueur / bot | `{id, hp, max}` | met à jour le roi d'un joueur, hp <= 0 fait émettre `eliminated` par le host |
| `wave_done` | joueur / bot | `{id, n}` | plateau nettoyé, le host tente de clore la manche |
| `round_end` | host | `{n}` | retour construction, `round_no + 1` |
| `eliminated` | host | `{id}` | le joueur passe spectateur, s'il ne reste qu'un vivant : `match_over` |
| `match_over` | host | `{winner}` | fin de partie |

## Barrière de manche

```
CONSTRUCTION  -- tous "ready" (ou deadline 60s) -->  round_start  -->  COMBAT
COMBAT        -- tous "wave_done" (ou 20s après le premier) -->  round_end  -->  CONSTRUCTION
```

Le **host** arbitre. Selon le backend : `NetLocal` le client local, `NetWs` le
plus ancien pair, `NetNodyx` le membre au plus petit `seatIndex` du salon vocal.
Deadlines partout, un pair qui se déconnecte est auto-éliminé.

## BoardDigest

`{k, km, o, f, w, ph, tw:[[cx,cy,type_idx,lvl]], un:[[id,x,y,hp255,type_idx,team,flags]]}`

`flags` bit 0 = champion, bit 1 = reçu d'un envoi. `type_idx` indexe
`BoardDigest.TYPES`. Sérialisation v1 : `var_to_bytes`. Optim prévue pour 8
joueurs : quantification int16 / uint8, plafond d'unités, 5 Hz.

## Tester

```bash
# solo + bots
godot --path . -- --net=local        # ou : setup > COURSE AUX ROIS

# deux clients via un relais local
godot --headless --path . --script res://scripts/net/lobby_server.gd
godot --path . -- --net=ws --host=127.0.0.1:9871

# activité Nodyx, sans instance : deux iframes contre un faux hôte
GODOT=godot bash tools/build_web.sh && python3 tools/serve_web.py 8060
# http://localhost:8060/mock-parent.html
```

QA visuelle : `_shot.gd`, `const MODE := "versus"`.
