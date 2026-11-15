# Run from Windows with Godot 4.6.3 and matching export templates installed.
param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force -Path "build/windows" | Out-Null
    & $Godot --headless --path . --editor --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }
    & $Godot --headless --path . --export-release "Windows Desktop" "build/windows/SignalFoundry.exe"
    if ($LASTEXITCODE -ne 0) { throw "Windows editor export failed" }
    Copy-Item "docs/GODOT-LICENSE.txt", "docs/GODOT-COPYRIGHT.txt" -Destination "build/windows/"
    Write-Host "Built build/windows/SignalFoundry.exe (unsigned development build)"
} finally { Pop-Location }
