# Architecture du code

Godot 4.7.2, GDScript, rendu GL Compatibility. Viewport fixe **1280 x 1000**,
`stretch/mode = canvas_items` + `aspect = keep` (la fenêtre entière scale et
letterbox comme un bloc). Unités instanciées en code (`.new()`), pas de scènes de
prefab.

Flux d'écrans : `title.tscn` puis `setup.tscn` (mode + choix de 3 spécialités sur
5) puis `main.tscn`. En activité Nodyx, `title.gd` détecte `window.NodyxBattle` et
saute directement au lobby.

## Autoloads

| | rôle |
|---|---|
| `game_state.gd` `GameState` | deux monnaies (`minerai`, `nourriture`), `wave`, `king_hp`, `phase`, signaux de changement, `game_over`, mode (SOLO / DUEL) fixé par setup |
| `meta.gd` `Meta` | bonus de run : multiplicateurs de dégâts / portée / cadence par type, bonus de peons, reliques, spécialités |
| `specs.gd` `Specs` | les 5 spécialités (label, couleur, description) et leur application |
| `versus.gd` `Versus` | l'adversaire abstrait du mode DUEL : roi ennemi, défense, files d'envois, résolution des assauts |
| `net/net.gd` `Net` | abstraction de transport, aucun gameplay (voir docs/multiplayer.md) |
| `match_director.gd` `MatchDirector` | arbitre du mode course aux rois : barrière de manche, envois ciblés, élimination, victoire |
| `audio.gd` `Audio` | SFX procéduraux (pool de voix, throttle), musique OFF par défaut |
| `fx.gd` `Fx` | particules, anneaux, textes flottants, secousse de caméra |

Sources de couleur : `palette.gd` `Palette`. Catalogue des tours / unités :
`catalog.gd` `Catalog` (id, coût, label, description, catégorie, plafond de tours).

## Le plateau de bataille : `arena.gd` `Arena`

Grille 13 x 15 (dont 9 x 11 jouable), cellule 64 px. Murs haut et bas pleins sauf
la colonne de porte, murs latéraux pleins. Spawn en haut, roi en bas.
`AStarGrid2D` sur la région de l'arène, avec anti-blocage-total (`can_build`
garde toujours un chemin).

Rendu **scindé statique / animé** pour la perf web :

- `_draw()` = le décor statique, redessiné seulement sur `_static_dirty` (pose,
  vente, changement de tracé).
- un calque enfant `_ArenaFx` (z 7) = l'animé : lumière clé, faille, brume,
  points de pose, survol, bannières.
- `_LightLayer` additif : lueurs chaudes, throttle ~20 fps sur web.
- post-process plein cadre (grain papier + encre + vignette) désactivé sur web.

Piège d'espace de coordonnées : `arena` et `Effects` sont frères sous `world`
(scale ~0.97, position ~x232). `unit.global_position` est en espace écran,
`unit.position` en espace arène. Un projectile fait `add_child` **puis**
`global_position = <point global>`. Les effets `Fx.*` sont toujours en local.

## La vue FERME : `farm_view.gd` `FarmView`

Node2D avec sa propre grille 12 x 13, trois zones murées empilées : MINE, CHAMP,
GARNISON. Mêmes API que `Arena` (`occupied`, `place`, `cell_to_world`...). Places
des `Peon`, des `Peon` fermiers, des `Caserne`. Décor procédural par zone
(chevalement + wagonnet + cristaux, moulin + parcelles de blé + puits,
baraquement + forge + aire d'entraînement). `wall_kit.gd` `WallKit` est un kit de
rempart partageable (statique, tout en méthodes statiques).

`main.gd` tient deux mondes parallèles (`world` et `farm_world`), un état de vue,
et route les entrées vers la grille active. Le HUD a une paire d'onglets
BATAILLE / FERME.

## Combat : `unit.gd` `Unit` (Node2D)

Auto-ciblage dans `target_group` selon `target_priority`, `take_damage(amount,
source)`, texte de dégâts flottant. `muzzle()` = point de tir visible.

- `enemy.gd` `Enemy` : types grognard / rôdeur / colosse / soigneur / spectre
  (traverse le mur de combattants) / sorcier (à distance). Modificateurs blindé /
  rapide / regen / spectre / champion (boss tous les 5). Flocking par séparation.
- `fighter.gd` `Fighter` : guerrière (mur au corps à corps) / archère (à distance,
  fragile). Vendables.
- `tower.gd` `Tower` : canon / gatling / mortier (AoE lobée) / givre (nova de zone
  de proximité, pas un projectile). 5 niveaux, priorité de cible cyclable,
  synergie de voisinage orthogonal (+8 % par voisin de même type).
- `peon.gd` `Peon` : mineur ou fermier, produit seulement en phase combat,
  rendements décroissants par groupe.
- `caserne.gd` `Caserne` : payée en nourriture, placée dans la garnison, empiler
  le même type monte le niveau d'envoi.
- `projectile.gd` : à tête chercheuse, arc lobé pour le mortier, splash.

## Vagues : `wave_manager.gd` `WaveManager`

14 vagues façonnées à la main puis procédurales. Champion ajouté toutes les 5
vagues. `wave_summary(w)` alimente l'aperçu de la prochaine vague. En course aux
rois, `start_wave` draine aussi les monstres reçus des autres joueurs
(`MatchDirector.drain_incoming()`).

## HUD : `hud.gd` (CanvasLayer)

Barre haute (panneau du roi avec médaillon et barre de PV, deux pastilles de
ressource avec taux "+X/s" live, compteur de vague, boutons vitesse / musique,
LANCER), colonne gauche de cartes de construction, colonne droite contextuelle
(prochaine vague en BATAILLE, résumé économie en FERME), panneau de récap de fin
de vague avec choix de renfort (draft roguelite), overlay de fin de partie.

En mode course aux rois : rail des joueurs (nom + barre de PV du roi + clic pour
spectateur), sélecteur de cible, panneau d'envoi de troupes. En DUEL : panneau du
roi adverse (médaillon crâne, bord rouge) + panneau "Envoyer l'assaut".
