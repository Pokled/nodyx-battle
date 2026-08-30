#!/usr/bin/env bash
# Empaquette l'extension Nodyx (SDK v1) au format .nyx :
#   manifest.json + icon.svg + i18n/*.json + ui/*.js  (chemins relatifs, manifest a la racine).
# Le jeu (game/) n'est PAS dedans : trop gros + types non acceptes ; il est servi
# ailleurs (tunnel), l'extension pointe dessus via le champ "URL du jeu" du builder.
#
#   bash tools/pack_widget.sh   ->  dist/kings-race-<version>.nyx
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python - "$ROOT" <<'PY'
import json, sys, zipfile, pathlib
root = pathlib.Path(sys.argv[1])
src = root / "widget" / "nodyx-battle"
m = json.loads((src / "manifest.json").read_text(encoding="utf-8"))
name, ver = m["id"], m["version"]
out = root / "dist"; out.mkdir(exist_ok=True)
nyx = out / f"{name}-{ver}.nyx"
if nyx.exists(): nyx.unlink()
files = ["manifest.json", "icon.svg", "README.md",
         "i18n/en.json", "i18n/fr.json", "ui/widget.js"]
with zipfile.ZipFile(nyx, "w", zipfile.ZIP_DEFLATED) as z:
    for rel in files:
        p = src / rel
        if p.exists():
            z.write(p, rel)          # arcname relatif -> manifest.json a la racine
print("OK ", nyx)
with zipfile.ZipFile(nyx) as z:
    for i in z.infolist():
        print(f"  {i.filename}  ({i.file_size} o)")
PY
echo
echo "Installe : Nodyx > Admin > Extensions > Installer un fichier (glisser le .nyx)."
echo "Puis Admin > Homepage > + widget > King's Race : renseigne 'URL du jeu' + 'Relais'."
