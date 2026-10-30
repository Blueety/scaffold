# Project Init Script (Windows PowerShell)
# Usage: .\init.ps1 <project-name>
# Example: .\init.ps1 my-app

param(
    [Parameter(Mandatory=$true)]
    [AllowEmptyString()]
    [string]$ProjectName
)

$ErrorActionPreference = "Stop"

# Validate the project name. This must accept exactly the same set as init.sh -
# otherwise a name works under WSL and fails on Windows.
# Allowed: ASCII letters/digits/dot/underscore/hyphen, plus any non-ASCII character
# (Chinese included). Anything else - whitespace, control characters, quotes, path
# separators, shell metacharacters - is rejected by the character class.
# Also rejected: '.', '..', '.git' (case-insensitive), a leading '-', a trailing '.'
# (Windows silently strips it), the reserved device names CON/PRN/AUX/NUL/COM0-9/LPT0-9,
# and invisible / Unicode-whitespace characters (see init.sh - the two sets must match).
if ($ProjectName -notmatch '^([\w.-]|[^\x00-\x7F])+$' -or
    $ProjectName -eq '.' -or $ProjectName -eq '..' -or $ProjectName -eq '.git' -or
    $ProjectName.StartsWith('-') -or $ProjectName.EndsWith('.') -or
    $ProjectName -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$' -or
    $ProjectName -match '[\u00A0\u00AD\u2000-\u200F\u2028\u2029\u202F\u205F\u2060\u3000\uFEFF]') {
    Write-Host "Error: invalid project name '$ProjectName'" -ForegroundColor Red
    Write-Host "Allowed: letters, digits, dot, underscore, hyphen, and non-ASCII characters (Chinese included)."
    Write-Host "Not '.', '..', '.git', a leading '-', a trailing '.', a Windows device name,"
    Write-Host "or anything containing spaces, quotes, path separators or shell metacharacters."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetDir = Join-Path (Get-Location) $ProjectName
$TemplateDir = Join-Path $ScriptDir "templates"

# Check if target directory already exists
if (Test-Path $TargetDir) {
    Write-Host "Error: Directory '$ProjectName' already exists" -ForegroundColor Red
    exit 1
}

# Check if template directory exists
if (-not (Test-Path $TemplateDir)) {
    Write-Host "Error: Template directory not found at '$TemplateDir'" -ForegroundColor Red
    exit 1
}

Write-Host "Creating project: $ProjectName" -ForegroundColor Cyan

# Create directory structure (src has no template file, so it is listed explicitly)
New-Item -ItemType Directory -Path (Join-Path $TargetDir "src") -Force | Out-Null

# Assert the directory really landed on this name. Windows rewrites trailing dots and
# reserves device names; if that happens every later path points somewhere else.
if (-not (Test-Path -LiteralPath $TargetDir)) {
    Write-Host "Error: '$ProjectName' was not created as '$TargetDir' (the name was rewritten by the filesystem)" -ForegroundColor Red
    exit 1
}

# Copy template files.
# The list is derived from templates/ itself, never hardcoded: hardcoding Chinese
# filenames breaks under Windows PowerShell 5.1, which reads this BOM-less script
# with the ANSI codepage and mangles every non-ASCII literal.
# The directory layout under templates/ matches the generated project 1:1,
# so the script does no remapping.
$templateFiles = Get-ChildItem -Path $TemplateDir -Recurse -File -Force
foreach ($file in $templateFiles) {
    $relative = $file.FullName.Substring($TemplateDir.TrimEnd('\', '/').Length).TrimStart('\', '/')
    $dstPath = Join-Path $TargetDir $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $dstPath) -Force | Out-Null
    Copy-Item -Path $file.FullName -Destination $dstPath -Force
}

if (-not (Test-Path (Join-Path $TargetDir "AGENTS.md"))) {
    Write-Host "Error: template copy failed, AGENTS.md not found in '$TemplateDir'" -ForegroundColor Red
    exit 1
}

# Substitute the placeholder at the byte level so the script stays transparent to
# BOMs, CRLF and non-UTF-8 bytes. Get-Content -Raw -Encoding UTF8 would drop a BOM and
# turn invalid bytes into U+FFFD, while init.sh's sed works on the byte stream and
# preserves both. ISO-8859-1 maps 1 byte to 1 char losslessly, so a byte array can be
# round-tripped through String.Replace with the replacement pre-encoded as UTF-8.
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$needle = '{{PROJECT_NAME}}'
$replacement = $latin1.GetString([System.Text.Encoding]::UTF8.GetBytes($ProjectName))
foreach ($f in (Get-ChildItem -Path $TargetDir -Recurse -File -Force)) {
    try {
        $text = $latin1.GetString([System.IO.File]::ReadAllBytes($f.FullName))
        if (-not $text.Contains($needle)) { continue }
        [System.IO.File]::WriteAllBytes($f.FullName, $latin1.GetBytes($text.Replace($needle, $replacement)))
    }
    catch {
        Write-Host "Error: failed to substitute placeholder in '$($f.FullName)': $_" -ForegroundColor Red
        exit 1
    }
}

# Init git, then assert it actually happened instead of reporting success blindly
if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
    Write-Host "Error: git not found on PATH" -ForegroundColor Red
    Write-Host "The project files were created at '$TargetDir' but no git repository was initialized."
    Write-Host "Install git, then run: cd `"$TargetDir`"; git init"
    exit 1
}

# Redirect stderr to a file rather than 2>&1: with $ErrorActionPreference='Stop' a
# native command's stderr wrapped into the success stream can abort the script.
#
# All git calls use `git -C $TargetDir` instead of Push-Location. Windows rewrites
# trailing dots and reserves device names; when that happens Push-Location fails
# inside the relaxed-$ErrorActionPreference window below and git would silently run
# in the caller's directory, leaving a stray repository behind.
$gitErrFile = [System.IO.Path]::GetTempFileName()
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gitOutput = & git -C $TargetDir init 2>$gitErrFile
$gitCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
$gitErr = (Get-Content $gitErrFile -Raw -ErrorAction SilentlyContinue)
Remove-Item $gitErrFile -Force -ErrorAction SilentlyContinue

if ($gitCode -ne 0) {
    Write-Host "Error: git init failed (exit $gitCode)" -ForegroundColor Red
    foreach ($line in $gitOutput) { Write-Host "  $line" -ForegroundColor Red }
    if ($gitErr) { Write-Host "  $gitErr" -ForegroundColor Red }
    Write-Host "The project files were created at '$TargetDir' but no git repository was initialized."
    Write-Host "Fix the cause above, then run: cd `"$TargetDir`"; git init"
    exit 1
}

if (-not (Test-Path (Join-Path $TargetDir '.git'))) {
    Write-Host "Error: git init reported success but '$TargetDir\.git' does not exist" -ForegroundColor Red
    exit 1
}

# Run a git command inside $TargetDir; on failure report stderr and the manual command.
# stderr goes to a file rather than 2>&1 so it does not end up in $out.
function Invoke-Git {
    param([string[]]$GitArgs, [string]$Manual)
    $errFile = [System.IO.Path]::GetTempFileName()
    # $ErrorActionPreference='Stop' turns any native command's stderr into a
    # terminating error (NativeCommandError), even when redirected to a file - a
    # plain `git add` warning would abort the script. Relax it for the call.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & git -C $TargetDir @GitArgs 2>$errFile
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    $err = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)
    Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) {
        Write-Host "Error: git $($GitArgs -join ' ') failed (exit $code)" -ForegroundColor Red
        foreach ($line in $out) { Write-Host "  $line" -ForegroundColor Red }
        if ($err) { Write-Host "  $err" -ForegroundColor Red }
        Write-Host "Run it manually: cd `"$TargetDir`"; $Manual"
        exit 1
    }
}

# Turn off path quoting. With the default core.quotepath=true git octal-escapes and
# quotes non-ASCII paths (this scaffold ships docs/agents/*.md with Chinese names),
# so an agent reading `git status --short` / `git diff --name-only` would get paths
# it cannot use as-is.
Invoke-Git @('config', 'core.quotepath', 'false') 'git config core.quotepath false'

# Enable the shipped git hooks. .git/hooks is not version controlled, so hooks live
# in .githooks/ and core.hooksPath points there. Without this the gate check would be
# a one-off.
Invoke-Git @('config', 'core.hooksPath', '.githooks') 'git config core.hooksPath .githooks'

# Record the hook and the checker as executable in the git index. Windows has no
# executable bit, so `git add` would record 100644 and a later clone on Linux/macOS
# would silently skip the hook.
$targetPrefixLength = $TargetDir.TrimEnd('\', '/').Length + 1
foreach ($rel in @('scripts', '.githooks')) {
    $relDir = Join-Path $TargetDir $rel
    foreach ($f in (Get-ChildItem -Path $relDir -File -Recurse -ErrorAction SilentlyContinue)) {
        $relPath = $f.FullName.Substring($targetPrefixLength).Replace('\', '/')
        Invoke-Git @('add', '--chmod=+x', '--', $relPath) "git add --chmod=+x $relPath"
    }
}

Write-Host ""
Write-Host "Project '$ProjectName' created!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  cd $ProjectName"
Write-Host "  1. Initialize your tech stack (npm init, create-next-app, etc.)"
Write-Host "  2. Ask your local agent to fill in AGENTS.md, CONTEXT.md and docs/"
Write-Host "  3. git add . && git commit -m 'init: project scaffold + tech stack'"
