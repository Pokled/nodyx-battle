# Extension : King's Race

L'extension Nodyx (SDK v1) qui fait tourner NodyxBattle dans un canal vocal.

- `manifest.json` : surface `activity` + champ `app` (URL et empreinte du bundle).
- `icon.svg`, `i18n/` : l'habillage de la fiche d'extension.
- `nodyx-activity.js` : le pont hôte / jeu. Il n'est **pas** dans le `.nyx`, il
  voyage dans le bundle applicatif (chargé par le `<head>` de l'export web).
- `game/` : l'export web, régénéré par `tools/build_web.sh`, hors versionnement.

Empaquetage, publication, dev local : voir [../../docs/nodyx-activity.md](../../docs/nodyx-activity.md).
