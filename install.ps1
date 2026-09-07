# Install as the `chat` command. From the project folder:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# Then open cmd, type: chat
# Uninstall:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Data = Join-Path $env:LOCALAPPDATA "ephemeral-chat"
$Bin = Join-Path $Data "bin"

function Find-Python {
    $cmds = @("py", "python", "python3")
    foreach ($cmd in $cmds) {
        $exe = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $exe) { continue }
        try {
            & $exe -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
            if ($LASTEXITCODE -eq 0) { return $exe.Source }
        } catch { }
    }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
        if ($LASTEXITCODE -eq 0) { return "py" }
    }
    return $null
}

if ($Uninstall) {
    if (Test-Path $Data) { Remove-Item -Recurse -Force $Data }
    Write-Host "Removed ephemeral-chat from $Data"
    Write-Host "If you added $Bin to PATH, you can remove that entry."
    exit 0
}

$Python = Find-Python
if (-not $Python) {
    Write-Host "Python 3.9+ is required. Install from https://www.python.org/downloads/"
    Write-Host "Tick 'Add python.exe to PATH', then re-run this script."
    exit 1
}

New-Item -ItemType Directory -Force -Path $Data, $Bin | Out-Null
Write-Host "Installing into $Data"
& $Python -m venv (Join-Path $Data "venv")
$VenvPy = Join-Path $Data "venv\Scripts\python.exe"
& $VenvPy -m pip install -q --upgrade pip
& $VenvPy -m pip install -q $Root

$ChatExe = Join-Path $Data "venv\Scripts\lanchat.exe"
$ChatShim = Join-Path $Bin "lanchat.cmd"
$AliasShim = Join-Path $Bin "chat.cmd"
$OldShim = Join-Path $Bin "ephemeral-chat.cmd"
@"
@echo off
"$ChatExe" %*
"@ | Set-Content -Encoding ASCII $ChatShim
Copy-Item -Force $ChatShim $AliasShim
Copy-Item -Force $ChatShim $OldShim

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$Bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$Bin", "User")
    $env:Path = "$env:Path;$Bin"
    Write-Host "Added $Bin to your user PATH."
}

Write-Host ""
Write-Host "Installed. Close and reopen Command Prompt, then type:"
Write-Host "  lanchat"
Write-Host "and press Enter. Type /quit or Ctrl+C to close the session."
