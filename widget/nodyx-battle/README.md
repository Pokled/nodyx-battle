# Extension Nodyx — King's Race (lanceur)

Extension **SDK Nodyx v1** (`.nyx`, `api: 1`, `mount({root, nodyx})`, iframe isolée).
C'est le format que le validateur de l'instance impose — le legacy `.zip` Web Component
est refusé (`API_VERSION_MISSING`).

## Pourquoi un lanceur et pas un jeu embarqué

Le SDK v1 tourne dans une iframe au CSP verrouillé et **ne peut pas embarquer d'iframe
tierce** (`SPECS/NODYX_SDK_REFERENCE.md §10`). L'extension est donc une **carte** qui
ouvre le jeu dans un **nouvel onglet** via `nodyx.openExternal`, en passant :
- le **pseudo Nodyx** (`nodyx.user.username`, permission `identity`) → `?name=`
- un **code de salon** (créé ou saisi) → `?room=`
- le relais + l'URL du jeu (config du builder) → `?host=` / base

Le multijoueur passe par le **relais WebSocket** du jeu (`scripts/net/lobby_server.gd`),
pas par Nodyx (Nodyx n'a pas de bus temps-réel pour extension). Voir `docs/multiplayer.md`.

## Contenu (dans le `.nyx`)

```
manifest.json      api:1, id kings-race, surface widget "launcher", 2 champs de config
icon.svg
i18n/en.json  i18n/fr.json
ui/widget.js       export function mount({ root, nodyx })
```

`game/` (export HTML5 du jeu, ~54 Mo) est **hors du paquet** — servi ailleurs.

## Fabriquer

```
bash tools/pack_widget.sh          # -> dist/kings-race-<version>.nyx
```

## Servir le jeu

```
bash tools/build_web.sh            # -> widget/nodyx-battle/game/
python tools/serve_web.py          # :8060
Godot ... --headless --path . --script res://scripts/net/lobby_server.gd   # relais :9871
cloudflared tunnel --url http://localhost:8060   # -> URL "jeu"   (HTTPS, cert auto)
cloudflared tunnel --url http://localhost:9871   # -> URL "relais"
```

## Installer dans Nodyx

1. **Admin ▸ Extensions ▸ Installer un fichier** → glisser `dist/kings-race-*.nyx`
   (l'écran de permissions montre « peut voir votre pseudo »)
2. **Admin ▸ Homepage ▸ + widget ▸ King's Race**
3. Config :
   - **Game URL** = URL du tunnel "jeu" (`https://xxxx.trycloudflare.com`)
   - **Relay host** = domaine du tunnel "relais" (`yyyy.trycloudflare.com`, sans `https://`)
4. La carte apparaît sur l'accueil. « Créer un salon » ouvre le jeu dans un onglet,
   partage le code ; l'autre fait « Rejoindre » avec le même code.

## Limites

- URLs `trycloudflare` **éphémères**. Pour du permanent : héberger jeu + relais sur un
  serveur stable, ou un tunnel nommé.
- Carte d'accueil, **pas** dans un salon vocal — ça demande de construire une surface
  widget de salon + un bus `nodyx.room` côté Nodyx (path A, non fait).
- Publier au registre : `https://extensions.nodyx.org` (licence OSI ✓, `source` URL à
  ajouter, `nodyx-ext check` vert, capture).
