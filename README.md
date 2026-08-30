# NodyxBattle

Un **tower-defense / auto-battler** en chacun-pour-soi, inspiré de *Legion TD 2*.
Tu farmes le minerai, tu bâtis ton labyrinthe de tours, tu recrutes des combattants,
et tu tiens la ligne contre des vagues qui montent. En multijoueur, chacun défend
sa forteresse et envoie des monstres sur les autres : dernier roi debout gagne.

Moteur : **Godot 4.7.2** (GDScript, rendu GL Compatibility). Le plateau et l'interface
sont dessinés **entièrement en code**, sans texture pour le décor. Le jeu s'exporte
en **WebAssembly** et se joue dans le navigateur.

NodyxBattle est aussi une **activité installable pour [Nodyx](https://github.com/Pokled/nodyx)** :
il tourne directement dans un canal vocal, les membres du salon forment le lobby,
la voix reste native Nodyx. Voir [docs/nodyx-activity.md](docs/nodyx-activity.md).

---

## Jouer

- **Solo (campagne)** : vagues neutres, victoire à la vague 20, puis mode sans fin.
- **Duel contre l'IA** : un adversaire abstrait, course au roi, sans limite de vague.
- **Course aux rois (2 à 8)** : FFA, chacun sa forteresse, envois de monstres ciblés.

Depuis l'écran-titre : `JOUER` puis choisis un mode dans `setup`. Tu y choisis aussi
**3 spécialités sur 5** (façon Slay the Spire) qui définissent tes tours et tes bonus.

Commandes : `1-7` construire, `Espace` lancer la vague, clic sur une tour pour
l'améliorer ou la vendre, `M` musique, `Tab` vitesse (x1 / x2 / x5), `Échap` annuler.

---

## Développer

Prérequis : **Godot 4.7.2 stable** (exact) et, pour l'export web, les
**modèles d'export 4.7.2** correspondants.

```bash
# Éditeur
godot --path .

# Contrôle headless après une modification (erreurs de script)
godot --headless --editor --path . --quit

# Export web  ->  widget/nodyx-battle/game/  + dist/kings-race-app-<ver>.zip
GODOT=godot bash tools/build_web.sh
python3 tools/serve_web.py 8060        # http://localhost:8060/

# Multijoueur en local : un relais + deux clients
godot --headless --path . --script res://scripts/net/lobby_server.gd
godot --path . -- --net=ws --host=127.0.0.1:9871
```

Détails et pièges Godot 4.7 : [docs/godot-notes.md](docs/godot-notes.md).

---

## Structure

```
scripts/
  main.gd            bootstrap : monde + ferme + vagues + HUD
  arena.gd           le plateau de bataille (géométrie, murs, effets)
  farm_view.gd       la vue FERME (mines, champs, garnison)
  hud.gd             tout le HUD, rail des joueurs
  wave_manager.gd    vagues neutres + monstres reçus des autres joueurs
  tower.gd enemy.gd fighter.gd peon.gd caserne.gd   unités
  net/               couche réseau (voir docs/multiplayer.md)
  match_director.gd  arbitre du mode course aux rois
scenes/              title, setup, lobby, main, arena, farm_view
shaders/ sound/ art/ (voir art/CREDITS.md)
widget/nodyx-battle/ l'extension Nodyx (activité)
docs/                design, architecture, protocole multi, intégration Nodyx
tools/               build web, serveur statique, empaquetage
```

## Docs

| | |
|---|---|
| [docs/design.md](docs/design.md) | ce qu'est le jeu, les piliers, le modèle de combat |
| [docs/architecture.md](docs/architecture.md) | carte du code : autoloads, plateau, combat, vagues, HUD |
| [docs/multiplayer.md](docs/multiplayer.md) | le protocole réseau : canaux, messages, snapshots |
| [docs/nodyx-activity.md](docs/nodyx-activity.md) | comment le jeu s'embarque dans un canal vocal Nodyx |
| [docs/godot-notes.md](docs/godot-notes.md) | pièges Godot 4.7 rencontrés |
| [Idea/idee-general.MD](Idea/idee-general.MD) | les notes de conception d'origine (motivations des joueurs) |

## Crédits

Sprites : [CraftPix.net](https://craftpix.net) (packs "Free"), détail dans
[art/CREDITS.md](art/CREDITS.md). Musique et conception : l'auteur du projet.

Licence : voir `LICENSE` (à définir).
