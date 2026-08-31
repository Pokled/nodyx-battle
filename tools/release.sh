#!/usr/bin/env bash
# Release d'une version de l'activite King's Race, en une commande.
#
#   bash tools/release.sh 0.4.4            # version explicite
#   bash tools/release.sh patch            # bump du dernier chiffre
#
# Fait, dans l'ordre :
#   1. bump manifest.json (version + app.url vers la future release GitHub)
#   2. build de l'export web + zip deterministe + sha256/bytes -> manifest
#   3. gardes : compilation Godot (0 erreur) + banc d'essai du pont
#   4. pack du .nyx
#   5. commit + push sur main
#   6. gh release create <tag> avec le zip du bundle
#
# Ensuite, sur la box de l'instance :  scripts/ops/install-activity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MANIFEST="widget/nodyx-battle/manifest.json"
GODOT="${GODOT:-godot}"
REPO="Pokled/nodyx-battle"

[ $# -eq 1 ] || { echo "usage: bash tools/release.sh <version|patch>"; exit 1; }

CUR="$(python3 -c "import json;print(json.load(open('$MANIFEST'))['version'])")"
if [ "$1" = "patch" ]; then
	NEW="$(python3 -c "v='$CUR'.split('.'); v[-1]=str(int(v[-1])+1); print('.'.join(v))")"
else
	NEW="$1"
fi
TAG="v$NEW"
echo "── King's Race $CUR -> $NEW ($TAG) ──"

git diff --quiet && git diff --cached --quiet || { echo "!! arbre de travail sale, commite ou stash d'abord"; exit 1; }
if git rev-parse "$TAG" >/dev/null 2>&1; then echo "!! le tag $TAG existe deja"; exit 1; fi

# 1. bump manifest
python3 - "$MANIFEST" "$NEW" "$REPO" <<'PY'
import json, sys
p, new, repo = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.load(open(p))
m["version"] = new
m.setdefault("app", {})
m["app"]["url"] = f"https://github.com/{repo}/releases/download/v{new}/kings-race-app-{new}.zip"
json.dump(m, open(p, "w"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
PY

# 2. build (injecte sha256/bytes dans le manifest)
GODOT="$GODOT" GODOT_SILENCE_ROOT_WARNING=1 bash tools/build_web.sh | grep -E "bundle :|sha256 :"

# 3. gardes
echo "── compilation Godot ──"
ERR="$("$GODOT" --headless --editor --path . --quit 2>&1 | grep -iE 'SCRIPT ERROR|Parse Error|error at' || true)"
[ -z "$ERR" ] || { echo "$ERR"; echo "!! erreurs de compilation, release annulee"; exit 1; }
echo "  ok"
echo "── banc d'essai du pont ──"
node tools/test-activity-bridge.mjs | tail -1

# 4. pack .nyx
bash tools/pack_widget.sh | grep -E "^OK "

# 5. commit + push
git add -A scripts widget/nodyx-battle "$MANIFEST"
git commit -m "release: King's Race $NEW"
git push origin main

# 6. release GitHub
gh release create "$TAG" "dist/kings-race-app-$NEW.zip" \
	--repo "$REPO" --title "$TAG" --notes "King's Race $NEW"

echo
echo "✔ $TAG publiee."
echo "  Sur la box :  sudo bash /var/www/nexus/scripts/ops/install-activity.sh"
