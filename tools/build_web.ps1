# Build de l'export Web -> widget/nodyx-battle/game/  (equivalent PowerShell de build_web.sh)
#
#   $env:GODOT = "C:\chemin\vers\Godot_v4.7.2-stable_win64_console.exe"
#   pwsh tools/build_web.ps1
#
# Prerequis : modeles d'export "Web" 4.7.2 stable exacts.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
if (-not (Get-Command $godot -ErrorAction SilentlyContinue) -and -not (Test-Path $godot)) {
    Write-Error "Godot introuvable. Definis `$env:GODOT ou mets 'godot' dans le PATH."
}

$ver = (& $godot --version) -replace '\s',''
$tpl = ($ver -split '\.official')[0]
$tplDir = Join-Path $env:APPDATA "Godot\export_templates\$tpl"
if (-not (Test-Path (Join-Path $tplDir "web_nothreads_release.zip")) -and
    -not (Test-Path (Join-Path $tplDir "web_release.zip"))) {
    Write-Error "Modeles d'export Web absents pour $ver (attendu dans $tplDir)"
}

$out = Join-Path $root "widget\nodyx-battle\game"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -File | Remove-Item -Force

Write-Host "Export Web ($ver) -> $out"
& $godot --headless --path $root --export-release "Web" (Join-Path $out "index.html")
Copy-Item (Join-Path $root "widget\nodyx-battle\nodyx-activity.js") $out
Copy-Item (Join-Path $root "tools\mock-parent.html") $out

Write-Host "OK. Pour le bundle applicatif + l'empreinte, utilise tools/build_web.sh (Git Bash)."
