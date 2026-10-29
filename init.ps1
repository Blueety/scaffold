# Project Init Script (Windows PowerShell)
# Usage: .\init.ps1 <project-name>
# Example: .\init.ps1 my-app

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

$ErrorActionPreference = "Stop"
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
    $content = $content -replace '\{\{PROJECT_NAME\}\}', $ProjectName
    [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.UTF8Encoding]::new($false))
}

# Init git
Push-Location $TargetDir
git init 2>$null
Pop-Location

Write-Host ""
Write-Host "Project '$ProjectName' created!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  cd $ProjectName"
Write-Host "  1. Initialize your tech stack (npm init, create-next-app, etc.)"
Write-Host "  2. Ask your local agent to fill in AGENTS.md, CONTEXT.md and docs/"
Write-Host "  3. git add . && git commit -m 'init: project scaffold + tech stack'"
