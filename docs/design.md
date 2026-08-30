# Conception

## Le pitch

Un tower-defense où la carte est le héros. Tu farmes une ressource, tu bâtis un
labyrinthe de tours qui exposent les ennemis le plus longtemps possible, tu
recrutes des combattants autonomes, et tu tiens la ligne. Modèle de combat repris
de *Legion TD 2* : une **vague neutre** monte chaque manche (courbe de difficulté
calibrée) et, en multijoueur, tu dépenses de la **nourriture** pour envoyer des
monstres sur un adversaire.

Nord de la conception : `Idea/idee-general.MD` (analyse des motivations des
joueurs) et les jeux qui y sont cités (Bloons TD 6, PvZ, Thronefall, "Sir We Have
an Orc Problem", Tower Factory, Slay the Spire).

## Les piliers

- **Créativité et maîtrise** : plusieurs façons de résoudre une vague, et une
  bonne solution se sent meilleure que les autres.
- **Puissance et progression** : gros chiffres, montées en niveau qui changent le
  jeu (pas des +2 %).
- **Élégance** : aligner les portées, épouser les courbes du chemin.
- **Complexité émergente** : synergies entre tours adjacentes, contraintes qui
  forcent l'invention.
- **Retours** : animations de mort, sons par type, progression visible de la
  menace au fil des manches.

## Deux économies

| Ressource | Produite par | Sert à |
|---|---|---|
| **minerai** | peons dans le rail MINE | tours, défense |
| **nourriture** | fermiers dans le rail FERME | troupes, casernes, offensive |

La tension stratégique : comment répartir ta main-d'œuvre entre défense et
attaque. Rendements décroissants par groupe, production uniquement en phase de
combat (attendre en phase construction ne rapporte rien).

## Spécialités

Le jeu a beaucoup de tours, mais tu n'en choisis que **3 sur 5** en début de
partie (artillerie, mécanique, négoce, garnison, cryomancie). Une spécialité est
un thème avec ses tours et ses bonus de run. De la variété sans la surcharge.

## Le plateau

Flux **vertical** : les ennemis entrent par une porte dans le mur du **haut** et
marchent vers la porte du **roi** en **bas**. L'arène est un rectangle muré,
propre. L'économie (mines, champs, garnison) vit dans une **vue FERME séparée**
(onglet plein écran) pour désencombrer la zone de jeu. Grille de jeu 9 de large
sur 11 de haut.

## Direction artistique

Donjon-forteresse médiéval sombre, éclairé chaud (Tails of Iron, Kingdom Rush,
Legion TD 2). Décor **100 % procédural** : pierre taillée aux contours d'encre
épais, torches murales seulement, bannières cramoisies, une lumière chaude en
plafond, faille verdâtre contenue, trône en gradins. Aucune texture pour le
plateau. Le HUD est lui aussi tout en code (arbre `Control` + `StyleBoxFlat`).

Code couleur : vert/cyan = production/allié, rouge/orange = danger/ennemi, or =
ressources, bleu = magie.

## Anti-turtle

Une « impôt de tourelle » : le prix des tours grimpe de façon quadratique
au-delà d'un plafond, pour qu'un joueur riche ne puisse pas carreler la grille en
un mur invincible. Il doit améliorer (niveaux 4 et 5) et utiliser des
combattants. L'équilibrage se règle sur trois leviers : rampe de PV des ennemis,
surcharge de prix des tours, densité des vagues du mode sans fin.
