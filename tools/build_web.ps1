# Build de l'export Web -> widget/nodyx-battle/game/
# Usage :  pwsh tools/build_web.ps1
#
# Prerequis : modeles d'export "Web" installes pour la version EXACTE de l'editeur
# (Editeur > Gerer les modeles d'export).  Le script verifie et previent sinon.

$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$godot  = "C:\Users\petit\Documents\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { $godot = "C:\Users\petit\Documents\godot\Godot_v4.7.2-stable_win64.exe" }

$ver = (& $godot --version) -replace '\s',''
$tpl = "$env:APPDATA\Godot\export_templates\$($ver -replace '\.official.*$','')"
if (-not (Test-Path "$tpl\web_nothreads_release.zip") -and -not (Test-Path "$tpl\web_release.zip")) {
    Write-Host "!! Modeles d'export Web absents pour $ver" -ForegroundColor Red
    Write-Host "   -> ouvre Godot, Editeur > Gerer les modeles d'export > Telecharger"
    Write-Host "   (attendu dans : $tpl)"
    exit 1
}

$out = Join-Path $root "widget\nodyx-battle\game"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -File -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Host "Export Web -> $out"
& $godot --headless --path $root --export-release "Web" (Join-Path $out "index.html")
if ($LASTEXITCODE -ne 0) { Write-Host "echec de l'export ($LASTEXITCODE)" -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host "OK. Test local :  python tools/serve_web.py  puis  http://localhost:8060/" -ForegroundColor Green
