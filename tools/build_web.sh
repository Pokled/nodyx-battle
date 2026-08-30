#!/usr/bin/env bash
# Build de l'export Web -> widget/nodyx-battle/game/
#
#   GODOT=/chemin/vers/godot bash tools/build_web.sh
#   (defaut : `godot` dans le PATH)
#
# Multi-plateforme : Linux, macOS, Git Bash / MSYS sur Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || {
	echo "!! Godot introuvable. Installe-le ou lance :  GODOT=/chemin/vers/godot bash tools/build_web.sh"
	exit 1
}

# 4.7.2.stable.official.<hash>  ->  4.7.2.stable
VER="$("$GODOT" --version 2>/dev/null | tr -d '[:space:]')"
TPL="${VER%%.official*}"

case "$(uname -s)" in
	Linux)               TPLDIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TPL" ;;
	Darwin)              TPLDIR="$HOME/Library/Application Support/Godot/export_templates/$TPL" ;;
	MINGW*|MSYS*|CYGWIN*) TPLDIR="${APPDATA:-$HOME/AppData/Roaming}/Godot/export_templates/$TPL" ;;
	*)                   TPLDIR="$HOME/.local/share/godot/export_templates/$TPL" ;;
esac

if [ ! -f "$TPLDIR/web_nothreads_release.zip" ] && [ ! -f "$TPLDIR/web_release.zip" ]; then
	echo "!! Modeles d'export Web absents pour $VER"
	echo "   attendu dans : $TPLDIR"
	echo "   (Editeur > Projet > Gerer les modeles d'export, version EXACTE $TPL)"
	exit 1
fi

OUT="$ROOT/widget/nodyx-battle/game"
mkdir -p "$OUT"
rm -f "$OUT"/* 2>/dev/null || true

echo "Export Web ($VER) -> $OUT"
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$OUT/index.html"

# Le pont d'activite : charge par html/head_include, doit vivre a cote d'index.html.
cp "$ROOT/widget/nodyx-battle/nodyx-activity.js" "$OUT/"

# ── Bundle applicatif : le zip que l'instance Nodyx telecharge une fois ──────
# (mock-parent.html est un outil de dev : HORS du bundle)
DIST="$ROOT/dist"; mkdir -p "$DIST"
VERSION="$(python3 -c "import json;print(json.load(open('$ROOT/widget/nodyx-battle/manifest.json'))['version'])")"
ZIP="$DIST/kings-race-app-$VERSION.zip"
rm -f "$ZIP"
( cd "$OUT" && zip -q -r -X "$ZIP" . -x 'mock-parent.html' )

# Empreinte + taille, injectees dans le manifeste (pack_widget.sh les relira).
python3 - "$ROOT" "$ZIP" <<'PY'
import hashlib, json, os, sys, pathlib
root, zippath = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
b = zippath.read_bytes()
digest = hashlib.sha256(b).hexdigest()
mpath = root / "widget" / "nodyx-battle" / "manifest.json"
m = json.loads(mpath.read_text(encoding="utf-8"))
m.setdefault("app", {})
m["app"]["sha256"] = digest
m["app"]["bytes"]  = len(b)
mpath.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"  bundle : {zippath.name}  ({len(b)} o)")
print(f"  sha256 : {digest}")
print(f"  -> manifest.json app.sha256 / app.bytes mis a jour")
PY

# Banc d'essai local (2 iframes contre un faux hote), copie APRES le zip.
cp "$ROOT/tools/mock-parent.html" "$OUT/"

echo "OK."
echo "  Test local  :  python3 tools/serve_web.py 8060   puis   http://localhost:8060/mock-parent.html"
echo "  Publier     :  televerser '$ZIP' en release GitHub a l'URL de manifest.json app.url"
echo "  Puis        :  bash tools/pack_widget.sh   ->  dist/kings-race-$VERSION.nyx"
