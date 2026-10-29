# Project Init Script (Windows PowerShell)
# Usage: .\init.ps1 <project-name>
# Example: .\init.ps1 my-app

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

$ErrorActionPreference = "Stop"

# Validate the project name: only [A-Za-z0-9._-]. Blocks path traversal (/ and ..),
# shell and regex metacharacters ($ \ space quotes), and .git.
# Keep this rule in sync with init.sh.
if ($ProjectName -notmatch '^[A-Za-z0-9._-]+$' -or
    $ProjectName -eq '.' -or $ProjectName -eq '..' -or $ProjectName -eq '.git' -or
    $ProjectName.StartsWith('-')) {
    Write-Host "Error: invalid project name '$ProjectName'" -ForegroundColor Red
    Write-Host "Allowed: letters, digits, dot, underscore, hyphen. Not '.', '..', '.git', or a leading '-'."
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

# Replace project name placeholder in every template file that carries it
foreach ($f in (Get-ChildItem -Path $TargetDir -Recurse -File -Force)) {
    $content = Get-Content $f.FullName -Raw -Encoding UTF8
    if ($content -notmatch '\{\{PROJECT_NAME\}\}') { continue }
    try {
        $replaced = $content -replace '\{\{PROJECT_NAME\}\}', $ProjectName
        [System.IO.File]::WriteAllText($f.FullName, $replaced, [System.Text.UTF8Encoding]::new($false))
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
$gitErrFile = [System.IO.Path]::GetTempFileName()
Push-Location $TargetDir
$gitOutput = & git init 2>$gitErrFile
$gitCode = $LASTEXITCODE
Pop-Location
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

Write-Host ""
Write-Host "Project '$ProjectName' created!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  cd $ProjectName"
Write-Host "  1. Initialize your tech stack (npm init, create-next-app, etc.)"
Write-Host "  2. Ask your local agent to fill in AGENTS.md, CONTEXT.md and docs/"
Write-Host "  3. git add . && git commit -m 'init: project scaffold + tech stack'"
