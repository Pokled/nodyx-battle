// King's Race — lanceur (SDK Nodyx v1, surface widget).
//
// L'iframe de surface est `sandbox="allow-scripts"` et rien d'autre : pas de
// popups, pas de navigation du top, `connect-src` ferme. Et `nodyx.openExternal`
// est specifie mais PAS encore cable cote hote (ExtensionSurface.svelte ne passe
// pas `actions.external`) -> c'est un no-op silencieux.
// Donc ce widget ne peut PAS ouvrir le jeu tout seul. Il prepare le lien + le
// code de salon, l'utilisateur ouvre dans un nouvel onglet.
// (Si un jour l'hote cable openExternal, on l'appelle aussi, en bonus.)
//
// Permission : identity ["username"] — pour prefixer le pseudo dans l'URL.

const STYLE = `
  .wrap {
    background: var(--nodyx-bg-elevated, #12121a);
    color: var(--nodyx-fg, #e2e8f0);
    border: 1px solid var(--nodyx-border, rgba(255,255,255,.08));
    border-radius: var(--nodyx-radius-md, 8px);
    padding: var(--nodyx-space-4, 18px);
    font-family: var(--nodyx-font, system-ui, sans-serif);
  }
  .tag {
    display: inline-block; font-size: 10px; font-weight: 700;
    letter-spacing: .09em; text-transform: uppercase;
    padding: 2px 9px; border-radius: 999px; margin-bottom: 12px;
    color: var(--nodyx-accent, #e6b84d);
    border: 1px solid var(--nodyx-accent, #e6b84d);
  }
  .h { font-size: 19px; font-weight: 800; margin-bottom: 4px; }
  .blurb { font-size: 13px; color: var(--nodyx-fg-muted, #6b7280); line-height: 1.5; margin-bottom: var(--nodyx-space-4, 16px); }
  .row { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
  input {
    padding: 8px 11px; font-size: 14px;
    background: var(--nodyx-bg, #08080c); color: var(--nodyx-fg, #e2e8f0);
    border: 1px solid var(--nodyx-border, rgba(255,255,255,.12));
    border-radius: var(--nodyx-radius-sm, 6px);
  }
  input.code { flex: 0 0 110px; text-transform: uppercase; letter-spacing: .14em; }
  input.link { flex: 1 1 240px; font-size: 12px; }
  button {
    padding: 9px 18px; font-size: 13px; font-weight: 700; cursor: pointer;
    border: none; border-radius: var(--nodyx-radius-sm, 6px);
    font-family: inherit; transition: opacity .15s;
  }
  button:hover { opacity: .85; }
  .primary { background: var(--nodyx-accent, #e6b84d); color: var(--nodyx-accent-fg, #1a1400); }
  .ghost { background: transparent; color: var(--nodyx-fg-muted, #9ca3af); border: 1px solid var(--nodyx-border, rgba(255,255,255,.14)); }
  .codeline { font-size: 15px; margin: 4px 0 12px; }
  .codeline b { font-size: 22px; letter-spacing: .18em; color: var(--nodyx-accent, #e6b84d); }
  .step { font-size: 13px; color: var(--nodyx-fg-muted, #9ca3af); line-height: 1.55; margin: 10px 0 6px; }
  .foot { margin-top: 12px; font-size: 12px; color: var(--nodyx-fg-muted, #6b7280); }
  .warn { margin-top: 4px; font-size: 13px; color: var(--nodyx-warning, #d98c4d); }
  a.open { display:inline-block; margin-top:8px; font-size:13px; font-weight:700;
    color: var(--nodyx-accent, #e6b84d); }
`

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

function code4() {
  let s = ''
  for (let i = 0; i < 4; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]
  return s
}

export function mount({ root, nodyx }) {
  const style = document.createElement('style')
  style.textContent = STYLE
  root.append(style)

  const wrap = document.createElement('div')
  wrap.className = 'wrap'
  root.append(wrap)

  function el(tag, cls, txt) {
    const n = document.createElement(tag)
    if (cls) n.className = cls
    if (txt != null) n.textContent = txt   // jamais innerHTML avec une valeur externe
    return n
  }

  function gameUrl(code) {
    const cfg = nodyx.config
    const name = nodyx.user && nodyx.user.username ? nodyx.user.username : ''
    const base = String(cfg.game_url).replace(/\/+$/, '')
    return base + '/?net=ws'
      + '&host=' + encodeURIComponent(cfg.relay_host)
      + '&room=' + encodeURIComponent(code)
      + (name ? '&name=' + encodeURIComponent(name) : '')
  }

  function showLink(codeRaw) {
    const cfg = nodyx.config
    const code = String(codeRaw || '').trim().toUpperCase()
    if (!code || !cfg.game_url || !cfg.relay_host) return
    const url = gameUrl(code)

    // bonus : si un jour l'hote cable openExternal, ca ouvre direct.
    try { nodyx.openExternal(url) } catch (e) {}

    wrap.replaceChildren(
      el('div', 'tag', nodyx.t('label')),
      el('div', 'h', nodyx.t('heading')),
    )
    const cl = el('div', 'codeline')
    cl.append(document.createTextNode(nodyx.t('room_is') + ' '), el('b', null, code))
    wrap.append(cl)
    wrap.append(el('div', 'step', nodyx.t('step_open')))

    const link = el('input', 'link')
    link.readOnly = true
    link.value = url
    link.addEventListener('focus', () => link.select())
    const copy = el('button', 'primary', nodyx.t('copy'))
    copy.addEventListener('click', () => {
      link.focus(); link.select()
      var done = false
      try { done = document.execCommand('copy') } catch (e) {}
      copy.textContent = nodyx.t(done ? 'copied' : 'copy_manual')
      setTimeout(() => { copy.textContent = nodyx.t('copy') }, 2000)
    })
    var openRow = el('div', 'row')
    openRow.append(link, copy)
    wrap.append(openRow)

    var a = el('a', 'open', nodyx.t('open_here'))
    a.href = url; a.target = '_blank'; a.rel = 'noopener'
    wrap.append(a)

    var back = el('button', 'ghost', nodyx.t('back'))
    back.style.marginTop = '14px'
    back.addEventListener('click', render)
    wrap.append(back)
  }

  function render() {
    const cfg = nodyx.config
    const configured = Boolean(cfg.game_url && cfg.relay_host)

    wrap.replaceChildren(
      el('div', 'tag', nodyx.t('label')),
      el('div', 'h', nodyx.t('heading')),
      el('div', 'blurb', nodyx.t('blurb')),
    )

    if (!configured) {
      wrap.append(el('div', 'warn', nodyx.t('not_configured')))
      return
    }

    const row = el('div', 'row')
    const create = el('button', 'primary', nodyx.t('create'))
    const input = el('input', 'code')
    input.placeholder = nodyx.t('code_placeholder')
    input.maxLength = 8
    const join = el('button', 'ghost', nodyx.t('join'))

    create.addEventListener('click', () => showLink(code4()))
    join.addEventListener('click', () => showLink(input.value))
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') showLink(input.value) })

    row.append(create, input, join)
    wrap.append(row)

    if (nodyx.user && nodyx.user.username) {
      wrap.append(el('div', 'foot', nodyx.t('as', { name: nodyx.user.username })))
    }
  }

  render()
  const offs = [
    nodyx.on('config', render),
    nodyx.on('locale', render),
  ]
  return { unmount() { offs.forEach((off) => off()) } }
}
