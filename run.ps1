# ==============================================================================
# TranslateAssistant Start Script
# ==============================================================================

$WorkspaceDir = $PSScriptRoot
$ScriptPath = Join-Path $WorkspaceDir "TranslateAssistant.ah2"
$PortableAhkDir = Join-Path $WorkspaceDir "bin"
$PortableAhkExe = Join-Path $PortableAhkDir "AutoHotkey64.exe"

function Get-AhkExecutable {
    if (Test-Path $PortableAhkExe) {
        return $PortableAhkExe
    }

    $cmd = Get-Command "AutoHotkey64.exe", "AutoHotkey.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    $paths = @(
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            return $p
        }
    }
    return $null
}

$ahkPath = Get-AhkExecutable

if (-not $ahkPath) {
    Write-Host "[!] AutoHotkey v2 not detected in system." -ForegroundColor Yellow
    Write-Host "[*] Trying to install via winget..." -ForegroundColor Cyan

    if (Get-Command "winget" -ErrorAction SilentlyContinue) {
        try {
            winget install --id AutoHotkey.AutoHotkey --source winget --accept-package-agreements --accept-source-agreements --silent
        } catch {
            Write-Host "[-] winget install failed." -ForegroundColor Red
        }
    }

    $ahkPath = Get-AhkExecutable
    if (-not $ahkPath) {
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        Write-Host "Please install AutoHotkey v2 manually:" -ForegroundColor Red
        Write-Host "Run: winget install AutoHotkey.AutoHotkey" -ForegroundColor White
        Write-Host "Or visit: https://www.autohotkey.com/v2/" -ForegroundColor White
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[+] Found AutoHotkey: $ahkPath" -ForegroundColor Green
Write-Host "[*] Launching TranslateAssistant in background..." -ForegroundColor Cyan

Start-Process -FilePath $ahkPath -ArgumentList "`"$ScriptPath`"" -WorkingDirectory $WorkspaceDir

Write-Host "[OK] TranslateAssistant is now running in system tray." -ForegroundColor Green
Write-Host "     - Press Alt + C to translate (Selected text / Screenshot / File)" -ForegroundColor White
Write-Host "     - Right-click tray icon to switch between Copilot and Gemini" -ForegroundColor DarkGray
