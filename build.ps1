# ==============================================================================
# TranslateAssistant 自动化打包脚本 (Auto Build to Single .exe)
# ==============================================================================

$ErrorActionPreference = "Stop"
$WorkspaceDir = $PSScriptRoot
$ScriptPath = Join-Path $WorkspaceDir "TranslateAssistant.ah2"
$DistDir = Join-Path $WorkspaceDir "dist"
$OutputExe = Join-Path $DistDir "TranslateAssistant.exe"
$ConfigFile = Join-Path $WorkspaceDir "config.ini"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   TranslateAssistant 自动化打包为独立 .exe 工具" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. 查找 AutoHotkey v2 Base 引擎
$baseAhk = $null
$commonAhkPaths = @(
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
    (Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)

foreach ($p in $commonAhkPaths) {
    if ($p -and (Test-Path $p)) {
        $baseAhk = $p
        break
    }
}

if (-not $baseAhk) {
    Write-Host "[!] 未找到 AutoHotkey v2 基础环境，无法完成打包。" -ForegroundColor Red
    exit 1
}

Write-Host "[+] 找到 Base 运行内核: $baseAhk" -ForegroundColor Green

# 2. 查找或准备 Ahk2Exe 编译器
$ahk2exe = $null
$compilerPaths = @(
    "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe",
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe",
    (Join-Path $WorkspaceDir "tools\compiler\Ahk2Exe.exe")
)

foreach ($cp in $compilerPaths) {
    if ($cp -and (Test-Path $cp)) {
        $ahk2exe = $cp
        break
    }
}

if (-not $ahk2exe) {
    Write-Host "[*] 本地未找到编译器 Ahk2Exe，正在尝试通过 AHK-UX 组件初始化..." -ForegroundColor Yellow
    $uxPath = Join-Path (Split-Path (Split-Path $baseAhk)) "UX\AutoHotkeyUX.exe"
    $installScript = Join-Path (Split-Path (Split-Path $baseAhk)) "UX\install-compiler.ahk"

    if ((Test-Path $uxPath) -and (Test-Path $installScript)) {
        try {
            Start-Process -FilePath $uxPath -ArgumentList "`"$installScript`"" -Wait
            $checkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
            if (Test-Path $checkPath) {
                $ahk2exe = $checkPath
            }
        } catch {}
    }

    # 若未能自动安装，使用绿色版下载方案
    if (-not $ahk2exe) {
        $toolsDir = Join-Path $WorkspaceDir "tools\compiler"
        if (-not (Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
        $zipPath = Join-Path $toolsDir "Ahk2Exe.zip"

        Write-Host "[*] 正在从官方镜像下载免安装编译组件..." -ForegroundColor Cyan
        $downloadUrl = "https://github.com/AutoHotkey/Ahk2Exe/releases/latest/download/Ahk2Exe.zip"
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $toolsDir -Force
            Remove-Item -Path $zipPath -Force
            $ahk2exe = Join-Path $toolsDir "Ahk2Exe.exe"
        } catch {
            Write-Host "[!] 下载失败，请手动下载 Ahk2Exe.exe 放置到 $toolsDir 目录下。" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "[+] 找到编译器组件: $ahk2exe" -ForegroundColor Green

# 3. 执行编译打包
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

Write-Host "[*] 正在编译构建 $OutputExe ..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $ahk2exe -ArgumentList "/in `"$ScriptPath`" /out `"$OutputExe`" /base `"$baseAhk`"" -PassThru -Wait -NoNewWindow

$retry = 0
while (-not (Test-Path $OutputExe) -and $retry -lt 15) {
    Start-Sleep -Seconds 1
    $retry++
}

if (Test-Path $OutputExe) {
    # 拷贝一份 config.ini 到输出目录
    Copy-Item -Path $ConfigFile -Destination (Join-Path $DistDir "config.ini") -Force

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "[√] 打包成功！独立可执行程序已生成至:" -ForegroundColor Green
    Write-Host "    $DistDir" -ForegroundColor White
    Write-Host ""
    Write-Host "    dist 文件夹内容:" -ForegroundColor DarkGray
    Write-Host "    ├── TranslateAssistant.exe (绿色单文件，免装 AutoHotkey)" -ForegroundColor DarkGray
    Write-Host "    └── config.ini             (外置配置文件，随时修改)" -ForegroundColor DarkGray
    Write-Host "==========================================================" -ForegroundColor Green
} else {
    Write-Host "[-] 打包失败，请检查编译输出日志。" -ForegroundColor Red
}
