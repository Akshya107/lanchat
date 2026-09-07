# One-time install on Windows. Share ONLY this command — no zip:
#
#   irm https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.ps1 | iex
#
# Then open a new Command Prompt and type:  lanchat
# Uninstall:  irm .../get-lanchat.ps1 -OutFile $env:TEMP\get-lanchat.ps1; & $env:TEMP\get-lanchat.ps1 -Uninstall

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$Owner = if ($env:LANCHAT_GH_OWNER) { $env:LANCHAT_GH_OWNER } else { "Akshya107" }
$Repo = if ($env:LANCHAT_GH_REPO) { $env:LANCHAT_GH_REPO } else { "lanchat" }
$Branch = if ($env:LANCHAT_GH_BRANCH) { $env:LANCHAT_GH_BRANCH } else { "main" }
$Data = Join-Path $env:LOCALAPPDATA "lanchat"
$Bin = Join-Path $Data "bin"

if ($Uninstall) {
    Write-Host "Removing lanchat…"
    if (Test-Path $Data) { Remove-Item -Recurse -Force $Data }
    Write-Host "Removed the lanchat command. Python stays installed."
    exit 0
}

function Find-Python {
    foreach ($cmd in @("py", "python", "python3")) {
        $exe = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $exe) { continue }
        try {
            & $exe -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
            if ($LASTEXITCODE -eq 0) { return $exe.Source }
        } catch { }
    }
    return $null
}

Write-Host "Installing lanchat…"

$Python = Find-Python
if (-not $Python) {
    Write-Host "Python is missing. Installing with winget…"
    winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $Python = Find-Python
}
if (-not $Python) {
    throw "Python 3.9+ is still missing. Close this window, open a new one, and run the install command again."
}

Write-Host "Using Python at $Python"
New-Item -ItemType Directory -Force -Path $Data, $Bin | Out-Null

$Src = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "pyproject.toml"))) {
    $Src = $PSScriptRoot
    Write-Host "Installing from this folder"
} elseif ($Owner) {
    $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/install/src.tgz.b64"
    Write-Host "Downloading lanchat…"
    $tmp = Join-Path $env:TEMP "lanchat-src"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $b64 = Join-Path $env:TEMP "lanchat-src.b64"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $b64
    $bytes = [Convert]::FromBase64String((Get-Content -Raw $b64))
    $tgz = Join-Path $env:TEMP "lanchat-src.tgz"
    [IO.File]::WriteAllBytes($tgz, $bytes)
    tar -xzf $tgz -C $tmp
    $Src = $tmp
} else {
    throw "This installer is not on GitHub yet. Run it from the lanchat folder, or set LANCHAT_GH_OWNER."
}

& $Python -m venv (Join-Path $Data "venv")
$VenvPy = Join-Path $Data "venv\Scripts\python.exe"
& $VenvPy -m pip install -q --upgrade pip
& $VenvPy -m pip install -q $Src

$ChatExe = Join-Path $Data "venv\Scripts\lanchat.exe"
$Shim = Join-Path $Bin "lanchat.cmd"
@"
@echo off
"$ChatExe" %*
"@ | Set-Content -Encoding ASCII $Shim

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$Bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$Bin", "User")
    $env:Path = "$env:Path;$Bin"
}

Write-Host ""
Write-Host "Done. Close this window, open a new Command Prompt, type:"
Write-Host "  lanchat"
Write-Host "and press Enter."
