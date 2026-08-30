#!/usr/bin/env bash
# Build de l'export Web -> widget/nodyx-battle/game/   (equivalent bash de build_web.ps1)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/c/Users/petit/Documents/godot/Godot_v4.7.2-stable_win64.exe}"

VER="$("$GODOT" --version | tr -d '[:space:]')"
TPLDIR="$APPDATA/Godot/export_templates/${VER%%.official*}"
if [ ! -f "$TPLDIR/web_nothreads_release.zip" ] && [ ! -f "$TPLDIR/web_release.zip" ]; then
	echo "!! Modeles d'export Web absents pour $VER"
	echo "   -> Godot > Editeur > Gerer les modeles d'export > Telecharger"
	echo "   (attendu dans : $TPLDIR)"
	exit 1
fi

OUT="$ROOT/widget/nodyx-battle/game"
mkdir -p "$OUT"
rm -f "$OUT"/* 2>/dev/null || true

echo "Export Web -> $OUT"
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$OUT/index.html"
echo "OK. Test local :  python tools/serve_web.py  puis  http://localhost:8060/"
