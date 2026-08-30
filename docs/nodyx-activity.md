# NodyxBattle comme activité Nodyx

Le jeu tourne dans un **canal vocal Nodyx**, en overlay plein écran, déclenché par
le bouton "Jeux" de la barre d'outils du canal. Les membres du salon forment le
lobby, la voix reste native Nodyx, on ne transporte que l'état de jeu.

## Ce qui vit où

| Morceau | Emplacement | Taille |
|---|---|---|
| l'extension `.nyx` | installée dans l'instance Nodyx | quelques Ko (manifeste, icône, i18n) |
| le bundle applicatif `kings-race-app-<ver>.zip` | une release GitHub | ~24 Mo (l'export web + le pont) |
| `nodyx-activity.js` | dans le bundle, chargé par `<head>` | le pont hôte / jeu |

Le manifeste (`widget/nodyx-battle/manifest.json`) déclare une surface
`type: "activity"` et un champ `app: { url, sha256, bytes }`. À l'installation,
Nodyx **télécharge le bundle une seule fois**, vérifie l'empreinte, le
décompresse, et **sert le jeu depuis l'instance elle-même** sous
`/api/v1/extensions/kings-race/<ver>/app/`. Aucune dépendance à un serveur tiers
au runtime : une fois installé, le jeu tourne même si le dépôt d'origine
disparaît.

L'iframe est same-origin (`sandbox="allow-scripts allow-same-origin"`, Godot a
besoin de `allow-same-origin` pour IndexedDB). Le contenu est épinglé par sha256
et validé par l'admin à l'installation.

## Le transport

L'activité n'a **ni socket ni jeton**. La page hôte relaie pour elle, via le
socket déjà authentifié de l'utilisateur, et **uniquement** dans la room
`voice:<channelId>` du canal rejoint. Les événements serveur (`activity:msg`,
`activity:snap`, `activity:sync_request`) sont calqués sur le relais du jukebox :
`from` estampillé serveur, payload opaque plafonné, rate-limité.

Le pont expose `window.NodyxBattle` (les 11 méthodes attendues par
`scripts/net/net_nodyx.gd`) par-dessus un port `MessageChannel` privé. Il porte
aussi un mini-protocole de lobby (`lobby_ready`, `match_start`) pour amener tout
le monde de "dans le canal vocal" à `match_started(seed, roster)`. Ensuite
`MatchDirector` reprend la main sur le canal `cmd` (voir
[multiplayer.md](multiplayer.md)).

L'**arbitre** (host : barrière de manche, seed, élimination) est le membre au plus
petit `seatIndex` du salon. Déterministe sur tous les clients, promotion
automatique si le host part.

## Publier une version

```bash
GODOT=godot bash tools/build_web.sh
#  -> dist/kings-race-app-<ver>.zip  + sha256/bytes injectés dans manifest.json
```

1. Release GitHub `v<ver>` sur `Pokled/nodyx-battle`, y téléverser
   `kings-race-app-<ver>.zip` (l'URL doit matcher `manifest.json` app.url).
2. `bash tools/pack_widget.sh` -> `dist/kings-race-<ver>.nyx`.
3. Nodyx, Admin, Extensions, Installer un fichier : le `.nyx`. Accorder la
   capacité `realtime`.

## Dev local (sans Nodyx)

```bash
GODOT=godot bash tools/build_web.sh
python3 tools/serve_web.py 8060
# http://localhost:8060/mock-parent.html : deux iframes du jeu contre un faux hôte
```

`tools/mock-parent.html` implémente le côté hôte du pont pour deux clients et
relaie entre eux exactement comme le fera le serveur. Le jeu tourne aussi en
standalone via le relais WebSocket `scripts/net/lobby_server.gd` et
`?net=ws&host=...&room=...`.
