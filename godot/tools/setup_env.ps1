# Starport Market — Godot environment setup (Windows)
$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path "$Root\godot\project.godot")) {
  $Root = "D:\starport-market"
}
$GodotPkg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "GodotEngine.GodotEngine*" | Select-Object -First 1
$GodotExe = Get-ChildItem $GodotPkg.FullName -Recurse -Filter "Godot_v*_win64.exe" | Where-Object { $_.Name -notmatch "console" } | Select-Object -First 1
$GodotConsole = Get-ChildItem $GodotPkg.FullName -Recurse -Filter "*console.exe" | Select-Object -First 1

Write-Host "Godot:" $GodotExe.FullName
Write-Host "Version:" (& $GodotConsole.FullName --version)

# CLI shim
$bin = Join-Path $Root "tools\bin"
New-Item -ItemType Directory -Force -Path $bin | Out-Null
@"
@echo off
"$($GodotExe.FullName)" %*
"@ | Set-Content (Join-Path $bin "godot.cmd") -Encoding ASCII

# Grok MCP entry
$cfg = Join-Path $env:USERPROFILE ".grok\config.toml"
$txt = Get-Content $cfg -Raw -ErrorAction SilentlyContinue
if ($txt -and $txt -notmatch "godot-mcp") {
  Add-Content $cfg @"

[mcp_servers.godot-mcp]
command = "npx"
args = ["-y", "@coding-solo/godot-mcp"]
enabled = true
startup_timeout_sec = 90

[mcp_servers.godot-mcp.env]
GODOT_PATH = '$($GodotExe.FullName)'
"@
  Write-Host "Added godot-mcp to ~/.grok/config.toml"
}

# Import project once (generates .godot)
$proj = Join-Path $Root "godot"
& $GodotConsole.FullName --path $proj --headless --import 2>&1 | Select-Object -Last 20
Write-Host "Setup complete. Run: tools\bin\godot.cmd --path godot"
Write-Host "Or:  $($GodotExe.FullName) --path $proj"
