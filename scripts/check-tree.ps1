# check-tree.ps1
#
# Verifies that the documented scaffold tree, templates/, and the real output of
# init.sh / init.ps1 all agree.
#
# Phase A (filesystem only):
#   - exactly ONE fenced code block in the repo is rooted at "my-project-name/".
#     More than one means the tree was copied somewhere and will drift.
#   - that block's file set equals templates/ verbatim.
#   - that block's directory set equals templates/ directories plus the empty
#     src/ that the scripts create (git cannot track empty directories).
#
# Phase B (end to end, skipped with -SkipEndToEnd):
#   - run init.sh and init.ps1 into two temp directories
#   - each output tree equals the documented tree
#   - both outputs are identical to each other, byte for byte
#   - every output file is byte-identical to its template with {{PROJECT_NAME}} replaced
#   - no {{PROJECT_NAME}} placeholder survives, and .git was created
#
# The source stays pure ASCII on purpose: Windows PowerShell 5.1 reads a BOM-less
# .ps1 with the ANSI codepage and would mangle any non-ASCII literal, so the tree
# glyphs are built from code points instead of being written literally.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1 [-BashPath <path>] [-SkipEndToEnd]

[CmdletBinding()]
param(
    [string]$BashPath,
    [switch]$SkipEndToEnd
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$RepoRoot    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TemplateDir = Join-Path $RepoRoot 'templates'
$InitSh      = Join-Path $RepoRoot 'init.sh'
$InitPs1     = Join-Path $RepoRoot 'init.ps1'
$RootLine    = 'my-project-name/'
$ProbeName   = 'check-tree-probe'
$Failed      = $false

# Tree glyphs by code point: box drawings light vertical / vertical-and-right /
# up-and-right / horizontal.
$CellPipe = [string][char]0x2502 + '   '                                          # "|" + 3 spaces
$CellBlank = '    '                                                               # 4 spaces
$MarkerBranch = [string][char]0x251C + [string][char]0x2500 + [string][char]0x2500 + ' '
$MarkerLast   = [string][char]0x2514 + [string][char]0x2500 + [string][char]0x2500 + ' '

function Fail([string]$Message) {
    Write-Host "  FAIL $Message" -ForegroundColor Red
    $script:Failed = $true
}

function New-StringSet { New-Object 'System.Collections.Generic.HashSet[string]' }

function Get-FencedBlocks([string]$Path) {
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $blocks = @()
    $i = 0
    while ($i -lt $lines.Count) {
        if ($lines[$i].StartsWith('```')) {
            $start = $i
            $j = $i + 1
            while ($j -lt $lines.Count -and -not $lines[$j].StartsWith('```')) { $j++ }
            if ($j -ge $lines.Count) { throw "unterminated code fence in $Path at line $($start + 1)" }
            $body = @()
            if ($j -gt $start + 1) { $body = @($lines[($start + 1)..($j - 1)]) }
            $blocks += @{ Path = $Path; Line = $start + 2; Body = $body }
            $i = $j + 1
        }
        else { $i++ }
    }
    return $blocks
}

function Parse-Tree($Block) {
    $files = New-StringSet
    $dirs  = New-StringSet
    $stack = @()
    $body = @($Block.Body)
    for ($k = 1; $k -lt $body.Count; $k++) {
        $line = $body[$k]
        if ($line.Trim().Length -eq 0) { continue }
        $where = "$($Block.Path):$($Block.Line + $k)"
        $rest = $line
        $depth = 0
        while ($rest.StartsWith($CellPipe) -or $rest.StartsWith($CellBlank)) {
            $rest = $rest.Substring(4)
            $depth++
        }
        if ($rest.StartsWith($MarkerBranch)) { $rest = $rest.Substring(4) }
        elseif ($rest.StartsWith($MarkerLast)) { $rest = $rest.Substring(4) }
        else { throw "$where cannot parse tree line: $line" }
        $name = [regex]::Replace($rest, '\s{2,}#.*$', '').Trim()
        if ($name.Length -eq 0) { throw "$where empty tree entry: $line" }
        if ($depth -gt $stack.Count) { throw "$where indentation jumps more than one level: $line" }
        if ($depth -eq 0) { $stack = @() } else { $stack = @($stack[0..($depth - 1)]) }
        $isDir = $name.EndsWith('/')
        $name = $name.TrimEnd('/')
        $stack += $name
        $full = $stack -join '/'
        if ($isDir) { [void]$dirs.Add($full) } else { [void]$files.Add($full) }
    }
    return @{ Files = $files; Dirs = $dirs }
}

function Get-RelativeTree([string]$Root) {
    $prefix = $Root.TrimEnd('\', '/')
    $files = New-StringSet
    $dirs  = New-StringSet
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force)) {
        $rel = $item.FullName.Substring($prefix.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($rel -eq '.git' -or $rel.StartsWith('.git/')) { continue }
        if ($item.PSIsContainer) { [void]$dirs.Add($rel) } else { [void]$files.Add($rel) }
    }
    return @{ Files = $files; Dirs = $dirs }
}

function Compare-Set([string]$Label, $Expected, $Actual) {
    $missing = @($Expected | Where-Object { -not $Actual.Contains($_) } | Sort-Object)
    $extra   = @($Actual   | Where-Object { -not $Expected.Contains($_) } | Sort-Object)
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
        Write-Host "  ok   $Label ($($Expected.Count) entries)" -ForegroundColor Green
        return
    }
    Fail $Label
    foreach ($m in $missing) { Write-Host "         missing: $m" -ForegroundColor Red }
    foreach ($e in $extra)   { Write-Host "         extra:   $e" -ForegroundColor Red }
}

function Report-Diffs([string]$Label, $Diffs, [string]$Unit) {
    if ($Diffs.Count -eq 0) {
        Write-Host "  ok   $Label ($Unit, byte-identical)" -ForegroundColor Green
        return
    }
    Fail "$Label - $($Diffs.Count) $Unit differ"
    foreach ($d in ($Diffs | Select-Object -First 10)) { Write-Host "         $d" -ForegroundColor Red }
    if ($Diffs.Count -gt 10) { Write-Host "         ... and $($Diffs.Count - 10) more" -ForegroundColor Red }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# Byte-for-byte comparison of two generated trees. Compare-Set only checks the file
# NAMES, so a divergence in content (an extra newline, a different encoding, a
# substitution that only one script performs) used to pass the self-check silently.
function Compare-Content([string]$Label, [string]$DirA, [string]$DirB, $Files) {
    $diffs = @()
    foreach ($rel in ($Files | Sort-Object)) {
        $a = Join-Path $DirA ($rel -replace '/', '\')
        $b = Join-Path $DirB ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) {
            $diffs += "$rel (missing on one side)"
            continue
        }
        if ((Get-Sha256 $a) -ne (Get-Sha256 $b)) {
            $diffs += ('{0} (A={1}B B={2}B)' -f $rel,
                       (Get-Item -LiteralPath $a).Length, (Get-Item -LiteralPath $b).Length)
        }
    }
    Report-Diffs $Label $diffs "$($Files.Count) files"
}

# Same, but the expected bytes are the template with {{PROJECT_NAME}} replaced.
# This catches anything the copy step does to a file that is not the placeholder:
# CRLF folding, encoding damage, a stray byte appended by one of the scripts.
function Get-TemplateBytes([string]$Path, [string]$Name) {
    $bytes  = [System.IO.File]::ReadAllBytes($Path)
    $needle = [System.Text.Encoding]::UTF8.GetBytes('{{PROJECT_NAME}}')
    $repl   = [System.Text.Encoding]::UTF8.GetBytes($Name)
    $out    = New-Object 'System.Collections.Generic.List[byte]'
    $i = 0
    while ($i -lt $bytes.Length) {
        $hit = $false
        if ($i + $needle.Length -le $bytes.Length) {
            $hit = $true
            for ($j = 0; $j -lt $needle.Length; $j++) {
                if ($bytes[$i + $j] -ne $needle[$j]) { $hit = $false; break }
            }
        }
        if ($hit) {
            foreach ($b in $repl) { [void]$out.Add($b) }
            $i += $needle.Length
        }
        else {
            [void]$out.Add($bytes[$i]); $i++
        }
    }
    return ,$out.ToArray()
}

function Compare-TemplateContent([string]$Label, [string]$TemplateRoot, [string]$ProjectDir,
                                 [string]$Name, $Files) {
    $diffs = @()
    foreach ($rel in ($Files | Sort-Object)) {
        $tpl = Join-Path $TemplateRoot ($rel -replace '/', '\')
        $gen = Join-Path $ProjectDir  ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $gen)) { $diffs += "$rel (not generated)"; continue }
        $want = Get-TemplateBytes $tpl $Name
        $got  = [System.IO.File]::ReadAllBytes($gen)
        if ($want.Length -ne $got.Length) {
            $diffs += ('{0} (template-with-name={1}B generated={2}B)' -f $rel, $want.Length, $got.Length)
            continue
        }
        for ($k = 0; $k -lt $want.Length; $k++) {
            if ($want[$k] -ne $got[$k]) {
                $diffs += ('{0} (first differing byte at offset {1})' -f $rel, $k)
                break
            }
        }
    }
    Report-Diffs $Label $diffs "$($Files.Count) files"
}

function Find-Bash {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    )
    # Git for Windows may live elsewhere; derive its root from git.exe itself
    # (<root>\cmd\git.exe -> <root>).
    $git = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command 'git' -ErrorAction SilentlyContinue }
    if ($git -and $git.Source) {
        $root = Split-Path -Parent (Split-Path -Parent $git.Source)
        $candidates += (Join-Path $root 'bin\bash.exe')
        $candidates += (Join-Path $root 'usr\bin\bash.exe')
    }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    # The WSL stub at %SystemRoot%\System32\bash.exe is deliberately rejected: it
    # cannot run this repo's scripts against Windows paths.
    return $null
}

function Assert-Generated([string]$Label, [string]$ProjectDir, $Expected) {
    if (-not (Test-Path -LiteralPath $ProjectDir)) { Fail "$Label produced no project directory"; return }
    $gen = Get-RelativeTree $ProjectDir
    Compare-Set "$Label files vs documented tree" $Expected.Files $gen.Files
    Compare-Set "$Label dirs  vs documented tree" $Expected.Dirs  $gen.Dirs
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir '.git'))) { Fail "$Label did not create .git" }
    $left = @(Get-ChildItem -LiteralPath $ProjectDir -Recurse -File -Force |
              Where-Object { $_.FullName -notlike '*\.git\*' } |
              Where-Object { [System.IO.File]::ReadAllText($_.FullName) -like '*{{PROJECT_NAME}}*' })
    if ($left.Count -gt 0) {
        Fail "$Label left {{PROJECT_NAME}} in $($left.Count) file(s)"
        foreach ($f in $left) { Write-Host "         $($f.FullName)" -ForegroundColor Red }
    }
    $readme = Join-Path $ProjectDir 'README.md'
    if ((Test-Path -LiteralPath $readme) -and
        ([System.IO.File]::ReadAllText($readme) -notlike "*$ProbeName*")) {
        Fail "$Label did not substitute the project name into README.md"
    }
}

# ---------------------------------------------------------------- Phase A
Write-Host ''
Write-Host '== Phase A: documented tree vs templates/ ==' -ForegroundColor Cyan

$trees = @()
foreach ($md in @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.md')) {
    foreach ($b in @(Get-FencedBlocks $md.FullName)) {
        if ($b.Body.Count -gt 0 -and $b.Body[0].Trim() -eq $RootLine) { $trees += $b }
    }
}

if ($trees.Count -ne 1) {
    Fail "expected exactly 1 fenced tree rooted at '$RootLine', found $($trees.Count)"
    foreach ($t in $trees) { Write-Host "         $($t.Path):$($t.Line)" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    exit 1
}

$docTree = Parse-Tree $trees[0]
$tplTree = Get-RelativeTree $TemplateDir
$expectedDirs = New-StringSet
foreach ($d in $tplTree.Dirs) { [void]$expectedDirs.Add($d) }
[void]$expectedDirs.Add('src')   # empty directory the scripts create explicitly

Write-Host "  tree: $($trees[0].Path):$($trees[0].Line)"
Compare-Set 'documented files vs templates/' $docTree.Files $tplTree.Files
Compare-Set 'documented dirs  vs templates/ + src' $expectedDirs $docTree.Dirs

# templates/ must be LF-only. init.sh substitutes placeholders with sed, and MSYS sed
# folds CRLF to LF, while init.ps1 preserves bytes - so a CR in any template would make
# the two scripts produce different output.
$crFiles = @()
foreach ($f in @(Get-ChildItem -LiteralPath $TemplateDir -Recurse -File -Force)) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes -contains [byte]13) { $crFiles += $f.FullName.Substring($TemplateDir.Length + 1) }
}
if ($crFiles.Count -gt 0) {
    Fail "templates/ must be LF-only, found CR in: $($crFiles -join ', ')"
    Write-Host '         init.sh (sed) would fold CRLF to LF while init.ps1 keeps it, so the two' -ForegroundColor Red
    Write-Host '         scripts would produce different output. Normalize the file to LF.' -ForegroundColor Red
} else {
    Write-Host '  ok   templates/ has no CR (both init scripts stay byte-identical)' -ForegroundColor Green
}

# ---------------------------------------------------------------- Phase B
if (-not $SkipEndToEnd) {
    Write-Host ''
    Write-Host '== Phase B: init.sh / init.ps1 real output ==' -ForegroundColor Cyan

    if (-not $BashPath) { $BashPath = Find-Bash }
    if (-not $BashPath) {
        Fail 'bash.exe not found; pass -BashPath <path> or use -SkipEndToEnd'
    }
    else {
        $stamp = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $tmpSh = Join-Path ([System.IO.Path]::GetTempPath()) "check-tree-sh-$stamp"
        $tmpPs = Join-Path ([System.IO.Path]::GetTempPath()) "check-tree-ps-$stamp"
        New-Item -ItemType Directory -Path $tmpSh, $tmpPs -Force | Out-Null
        try {
            Push-Location $tmpSh
            try { & $BashPath $InitSh $ProbeName | Out-Null } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { Fail "init.sh exited $LASTEXITCODE" }

            Push-Location $tmpPs
            # 6>$null drops Write-Host output, which bypasses the pipeline
            try { & $InitPs1 $ProbeName 6>$null | Out-Null } finally { Pop-Location }

            Assert-Generated 'init.sh ' (Join-Path $tmpSh $ProbeName) $docTree
            Assert-Generated 'init.ps1' (Join-Path $tmpPs $ProbeName) $docTree

            $sh = Get-RelativeTree (Join-Path $tmpSh $ProbeName)
            $ps = Get-RelativeTree (Join-Path $tmpPs $ProbeName)
            Compare-Set 'init.sh vs init.ps1 files' $sh.Files $ps.Files
            Compare-Set 'init.sh vs init.ps1 dirs ' $sh.Dirs  $ps.Dirs
            Compare-Content 'init.sh vs init.ps1 content' `
                (Join-Path $tmpSh $ProbeName) (Join-Path $tmpPs $ProbeName) $sh.Files
            Compare-TemplateContent 'templates/ vs init.sh output' `
                $TemplateDir (Join-Path $tmpSh $ProbeName) $ProbeName $tplTree.Files
        }
        finally {
            Remove-Item -LiteralPath $tmpSh, $tmpPs -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ''
if ($Failed) {
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
