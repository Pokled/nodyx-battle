#!/usr/bin/env bash
# Empaquette l'extension Nodyx (SDK v1) au format .nyx :
#   manifest.json + icon.svg + README.md + i18n/*.json   (manifest a la racine).
#
# Le jeu (game/) n'est PAS dedans : trop gros + types non acceptes. Il vit dans
# le BUNDLE APPLICATIF (dist/kings-race-app-<ver>.zip, produit par build_web.sh),
# que l'instance telecharge une fois a l'installation et sert elle-meme ensuite.
# Le manifeste porte son empreinte sha256 (renseignee par build_web.sh).
#
#   bash tools/pack_widget.sh   ->  dist/kings-race-<version>.nyx
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, sys, zipfile, pathlib
root = pathlib.Path(sys.argv[1])
src = root / "widget" / "nodyx-battle"
m = json.loads((src / "manifest.json").read_text(encoding="utf-8"))
name, ver = m["id"], m["version"]

if m.get("app", {}).get("sha256", "").strip("0") == "":
    print("!! manifest.json : app.sha256 est un placeholder.")
    print("   Lance d'abord :  GODOT=godot bash tools/build_web.sh")
    sys.exit(1)

out = root / "dist"; out.mkdir(exist_ok=True)
nyx = out / f"{name}-{ver}.nyx"
if nyx.exists(): nyx.unlink()
files = ["manifest.json", "icon.svg", "README.md", "i18n/en.json", "i18n/fr.json"]
with zipfile.ZipFile(nyx, "w", zipfile.ZIP_DEFLATED) as z:
    for rel in files:
        p = src / rel
        if p.exists():
            z.write(p, rel)
print("OK ", nyx)
with zipfile.ZipFile(nyx) as z:
    for i in z.infolist():
        print(f"  {i.filename}  ({i.file_size} o)")
print()
print(f"Bundle applicatif attendu : {m['app']['url']}")
print(f"  sha256 {m['app']['sha256']}")
PY
echo
echo "Installe : Nodyx > Admin > Extensions > Installer un fichier (glisser le .nyx)."
echo "L'instance recupere le bundle applicatif depuis app.url, verifie l'empreinte,"
echo "et sert le jeu depuis /api/v1/extensions/kings-race/<ver>/app/ . Accorde 'realtime'."
