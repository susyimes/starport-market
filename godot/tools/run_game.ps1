$GodotPkg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "GodotEngine.GodotEngine*" | Select-Object -First 1
$GodotExe = Get-ChildItem $GodotPkg.FullName -Recurse -Filter "Godot_v*_win64.exe" | Where-Object { $_.Name -notmatch "console" } | Select-Object -First 1
$proj = Resolve-Path (Join-Path $PSScriptRoot "..")
Write-Host "Launching" $GodotExe.FullName "— path" $proj
Start-Process -FilePath $GodotExe.FullName -ArgumentList @("--path", "$proj")
