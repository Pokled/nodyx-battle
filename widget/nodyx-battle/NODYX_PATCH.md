# Câbler `nodyx.openExternal` dans Nodyx (optionnel — pour le 1-clic)

`nodyx.openExternal(url)` est spécifié (`SPECS/NODYX_SDK_REFERENCE.md §5.8` :
« lien externe, confirmation utilisateur ») mais **pas branché** : le message
`host.external` arrive jusqu'à `host.ts` (URL validée par `isSafeExternalUrl`) puis
appelle `actions.external?.(url)` — or `ExtensionSurface.svelte` ne passe pas
`external` dans les actions (« Les autres actions arrivent avec les lots suivants »).
Résultat : no-op silencieux, l'extension King's Race ne peut pas ouvrir le jeu et
tombe sur le mode « copie le lien ».

Un `window.open` direct depuis le handler de message serait **bloqué par le
navigateur** (l'activation utilisateur ne traverse pas `postMessage`). La bonne
approche, conforme au spec : l'hôte affiche une **confirmation**, et c'est le clic
sur *son* bouton « Ouvrir » qui ouvre l'onglet.

## Patch (`nodyx-frontend/src/lib/components/ExtensionSurface.svelte`)

```svelte
// 1. état
let pendingExternal: string | null = $state(null)

// 2. dans l'objet actions passé à createHostHandler(...) :
//    (à côté de resize / toast)
external: (url: string) => { pendingExternal = url },

// 3. dans le template, à la racine du composant :
{#if pendingExternal}
  <div class="ext-external-confirm" role="dialog" aria-modal="true">
    <p>{$t('extensions.open_external') /* "Ouvrir ce lien externe ?" */}</p>
    <code>{pendingExternal}</code>
    <div class="row">
      <button onclick={() => {
        window.open(pendingExternal, '_blank', 'noopener,noreferrer')
        pendingExternal = null
      }}>{$t('common.open')}</button>
      <button class="ghost" onclick={() => (pendingExternal = null)}>{$t('common.cancel')}</button>
    </div>
  </div>
{/if}
```

`window.open` est ici dans le contexte de la page Nodyx (pas l'iframe sandbox) **et**
déclenché par un vrai clic → pas de blocage popup.

Bénéfice : toute extension qui appelle `nodyx.openExternal` marche, pas seulement
celle-ci. Une fois en place, King's Race ouvre le jeu en 1 clic (le fallback
« copie le lien » reste comme filet).
