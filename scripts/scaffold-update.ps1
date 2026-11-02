# Windows entry point for scripts/scaffold-update.sh.
#
# Why this exists: bash.exe on PATH is often the WSL stub in System32. It cannot
# run Windows paths, and its own error message gets eaten by the console code
# page, so the user sees a line of '?' and exit 1 with no way to tell what went
# wrong. This wrapper locates Git for Windows' bash first.
#
# This file MUST stay pure ASCII: PowerShell 5.1 reads a BOM-less .ps1 using the
# ANSI code page, so any non-ASCII literal here would be corrupted.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\scaffold-update.ps1 ..\my-project
#   powershell -ExecutionPolicy Bypass -File scripts\scaffold-update.ps1 ..\my-project --write

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'scaffold-update.sh'
if (-not (Test-Path -LiteralPath $script)) {
    Write-Error "not found: $script"
    exit 2
}

# Walk up from any git.exe on PATH to find the Git install root, then take its
# bundled bash. Under Git's own sh, PATH may point at mingw64/bin, so a fixed
# relative parent is not reliable.
$candidates = New-Object System.Collections.Generic.List[string]
foreach ($p in @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files\Git\usr\bin\bash.exe',
    'C:\Program Files (x86)\Git\bin\bash.exe'
)) { $candidates.Add($p) }

$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCmd) {
    $dir = Split-Path -Parent $gitCmd.Source
    for ($i = 0; $i -lt 4 -and $dir; $i++) {
        $candidates.Add((Join-Path $dir 'bin\bash.exe'))
        $candidates.Add((Join-Path $dir 'usr\bin\bash.exe'))
        $dir = Split-Path -Parent $dir
    }
}

$bash = $null
foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { $bash = $c; break }
}

if (-not $bash) {
    Write-Host 'error: cannot find bash.exe. Install Git for Windows, or run:' -ForegroundColor Red
    Write-Host '  bash scripts/scaffold-update.sh <project-dir>'
    exit 2
}

# Probe it: the WSL stub fails right here, before the script ever starts.
& $bash -c 'exit 0' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "error: $bash cannot run (WSL stub?). Use Git's bash:" -ForegroundColor Red
    Write-Host "  `"C:\Program Files\Git\bin\bash.exe`" scripts/scaffold-update.sh <project-dir>"
    exit 2
}

& $bash $script @args
exit $LASTEXITCODE
