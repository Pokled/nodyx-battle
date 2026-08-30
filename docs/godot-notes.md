# Pièges Godot 4.7 rencontrés

## Validation headless

```bash
# construit le cache de classes / lance l'import, filtre les erreurs
godot --headless --editor --path . --quit    # grep 'SCRIPT ERROR|Parse Error'

# rendu réel pour une capture de QA (PAS --headless)
godot --rendering-driver opengl3 --path . scenes/_shot.tscn --quit-after <frames>
```

Un `class_name` fraîchement ajouté n'est pas reconnu tant qu'un import
`--editor` n'a pas tourné.

## Ruptures 4.7

- Les appels `draw_*` ne sont permis que dans le `_draw()` du CanvasItem
  **propriétaire**. Un helper sur le noeud A qui fait `draw_rect()` mais est
  appelé depuis le `_draw()` du noeud B lève une erreur. Correctif : passer le
  CanvasItem en paramètre et faire `ci.draw_rect(...)`.
- `Control.size` / `set_size` échoue si appelé hors de l'arbre ou en ancrage
  complet. Correctif : `add_child` d'abord, puis
  `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`.
- `_ = expr` comme instruction : erreur de parse. Retirer le paramètre inutilisé
  ou le préfixer `_`.
- Ternaire "Values not mutually compatible" : remplacer par un if/else.
- Un `const` ne peut pas appeler `OS.has_feature()` : utiliser un `var`.

## Svelte / JS côté hôte, pour mémoire

Jamais `structuredClone` sur du `$state` Svelte 5 (le proxy n'est pas clonable) :
`$state.snapshot()` d'abord. Jamais de wrapper à overflow autour de l'éditeur.

## Bug de rendu à connaître

Réassigner `srcObject` sur un `<video>` déclenche l'algorithme de chargement du
média **même si on réassigne le même objet** : l'élément se réinitialise, devient
noir, attend une nouvelle keyframe. Toujours vérifier que le flux change
vraiment avant d'assigner (`if (node.srcObject === s) return`).

## Export web

- Modèles d'export **4.7.2 stable exacts** requis. Sur Linux :
  `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Preset `Web` mono-thread (`thread_support = false`) : aucun en-tête COOP/COEP
  requis, l'export tourne sur n'importe quel hébergeur statique et dans une
  iframe cross-origin.
- `progressive_web_app/ensure_cross_origin_isolation_headers = false` : le
  service worker d'isolation casserait l'embarquement en iframe et n'apporte rien
  à un build mono-thread.
- `html/head_include` charge `nodyx-activity.js` avant `index.js`.
- Sortie `widget/nodyx-battle/game/`, servie par `tools/serve_web.py` (pas de
  COOP/COEP).
