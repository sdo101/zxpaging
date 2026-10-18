# checks that no two of the program's fixed address variables share a byte: every "Dim x As <type> At <address>" and every
# "#define A_x <address>  'size n" in the source is worked out to the byte, and any two that overlap are reported...
# ...the build runs this before it compiles anything, and stops if it finds an overlap, see build.ps1
# N.B: why this exists: twice in October 2026 a variable was given bytes that another already had (gub_core_stage at
# A_CORE + 34, inside a four byte counter, and gub_core_file_handle at A_CORE + 76, inside the monitor's counts, which
# was a #define with no size), and each time it was only found because something went wrong in a test
#
# how the addresses are grouped, because not every overlap is a fault:
#   the core data page ($C000 to $DFFF) is one memory that the core and every stage share, so everything there, from
#   whichever file, is checked against everything else... except inside the scratch areas (A_TEXT_BUFFER, A_GEN_VARS),
#   which each stage uses for its own short lived purposes, and which are checked one module at a time
#   the library's private storage (A_LIB_PRIVATE, the top of the paged code slot) is each library page's own, so it is
#   checked one module at a time: a stage or library file and the files it includes
#   a block, a #define with a size, may hold the variables that make it up (A_CORE holds the core's), so a
#   variable inside a block is not an overlap, but two blocks that partly overlap are, and so are two variables
#   two that are meant to share bytes say so: one of them names the other on its own line
#   the size of a #define is in its comment, 'size n, or the comment begins with n bytes
#   a #define with no size is a name for an address and nothing more, unless it is in the core data page, where it is
#   reported, it must be given a size: that is how the second overlap above went unseen
# returns nothing if all is well, otherwise one line for each fault
param([string]$SourceDir = (Join-Path $PSScriptRoot '..\src'))

$files = Get-ChildItem $SourceDir -Filter *.bas
$values = @{}        # every name's value, for working out the addresses: #defines and Consts
$exprs  = @{}
foreach($f in $files){
    foreach($line in [IO.File]::ReadAllLines($f.FullName)){
        if($line -match "^\s*#define\s+(\w+)\s+([^']+?)\s*(?:'.*)?$"){ $exprs[$Matches[1]] = $Matches[2] }
        elseif($line -match "^\s*Const\s+(\w+)\s+As\s+\w+\s*=\s*([^']+?)\s*(?:'.*)?$"){ $exprs[$Matches[1]] = $Matches[2] }
    }
}
function Value([string]$name, [int]$depth = 0){
    if($values.ContainsKey($name)){ return $values[$name] }
    if($depth -gt 20 -or -not $exprs.ContainsKey($name)){ return $null }
    $v = Evaluate $exprs[$name] ($depth + 1); $values[$name] = $v; $v
}
function Evaluate([string]$text, [int]$depth = 0){
    $t = $text -replace '\$([0-9A-Fa-f]+)', '0x$1' -replace '%([01]+)', { [Convert]::ToInt32($_.Groups[1].Value, 2) }
    $bad = $false
    $t = [regex]::Replace($t, '\b[A-Za-z_]\w*\b', { param($m) if($m.Value -match '^0x'){ return $m.Value }; $v = Value $m.Value $depth; if($null -eq $v){ $script:bad = $true; return '0' }; "$v" })
    if($script:bad){ $script:bad = $false; return $null }
    if($t -notmatch '^[\s0-9xA-Fa-f+\-*/()]+$'){ return $null }
    try { [int](Invoke-Expression $t) } catch { $null }
}

# --- every fixed address thing, with the module it belongs to
$size = @{ byte = 1; ubyte = 1; integer = 2; uinteger = 2; long = 4; ulong = 4; fixed = 4; float = 5; string = 2 }
$items = @()
foreach($f in $files){
    $n = 0
    foreach($line in [IO.File]::ReadAllLines($f.FullName)){
        $n++
        if($line -match "^\s*Dim\s+(\w+)\s+As\s+(\w+)\s+At\s+([^']+?)\s*(?:'.*)?$"){
            $a = Evaluate $Matches[3]; $s = $size[$Matches[2].ToLower()]
            if($null -ne $a -and $s){ $items += [pscustomobject]@{ Name = $Matches[1]; From = $a; To = $a + $s - 1; Block = $false; File = $f.Name; Line = $n; Expr = $Matches[3]; Text = $line } }
        } elseif($line -match "^\s*#define\s+(A_\w+)\s+([^']+?)\s*(?:'(.*))?$"){
            $a = Value $Matches[1]; $comment = $Matches[3]
            if($null -eq $a){ continue }
            if($comment -match '(?i)\bsize\s+(\d+)' -or $comment -match '^\s*(?:\.\.\.)?(\d+)\s+bytes\b'){ $items += [pscustomobject]@{ Name = $Matches[1]; From = $a; To = $a + [int]$Matches[1] - 1; Block = $true; File = $f.Name; Line = $n; Expr = ''; Text = $line } ; $items[-1].Name = ($line -replace '^\s*#define\s+(\w+).*$','$1') }
            elseif($a -ge 0xC000 -and $a -le 0xDFFF -and $comment -notmatch '(?i)no size|a point') { $items += [pscustomobject]@{ Name = ($line -replace '^\s*#define\s+(\w+).*$','$1'); From = $a; To = $a - 1; Block = $true; File = $f.Name; Line = $n; Expr = 'NOSIZE'; Text = $line } }
        }
    }
}

# which module each file belongs to: a file that is not included by another is a module, and owns what it includes
$includes = @{}
foreach($f in $files){ $includes[$f.Name] = @(Select-String -Path $f.FullName -Pattern '^\s*#include\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
function Closure($name, $seen){ if($seen.Contains($name)){ return }; [void]$seen.Add($name); foreach($i in $includes[$name]){ if($includes.ContainsKey($i)){ Closure $i $seen } } }
$shared = @('constants.bas', 'globals.bas')
$modules = $files.Name | Where-Object { $_ -notin $shared -and $_ -notmatch '-include\.bas$' }

$faults = New-Object Collections.Generic.List[string]
foreach($i in $items | Where-Object { $_.Expr -eq 'NOSIZE' }){ $faults.Add("$($i.File):$($i.Line): $($i.Name) is in the core data page but has no size, give its comment 'size n") }
$sized = @($items | Where-Object { $_.Expr -ne 'NOSIZE' })
# the blocks that others are built on: the first name in any address, e.g. A_CORE in "At A_CORE + 76"
$containers = New-Object Collections.Generic.HashSet[string]
foreach($e in @($exprs.Values) + @($items | ForEach-Object { $_.Expr })){ if("$e" -match '^\s*\(?\s*(A_\w+)'){ [void]$containers.Add($Matches[1]) } }

$scratch = @('A_TEXT_BUFFER', 'A_GEN_VARS')
$scratchItems = @($sized | Where-Object { $_.Name -in $scratch -and $_.File -in $shared })
$libPrivate = Value 'A_LIB_PRIVATE'
function InScratch($it){ foreach($b in $scratchItems){ if($it.From -ge $b.From -and $it.To -le $b.To -and $it.Name -ne $b.Name){ return $true } }; $false }
function InPrivate($it){ $libPrivate -ne $null -and $it.From -ge $libPrivate -and $it.From -lt $libPrivate + 512 -and $it.Name -ne 'A_LIB_PRIVATE' }

function Check($list, $where){
    $l = @($list | Sort-Object From, @{ e = { -($_.To) } })
    for($x = 0; $x -lt $l.Count; $x++){
        for($y = $x + 1; $y -lt $l.Count -and $l[$y].From -le $l[$x].To; $y++){
            $p = $l[$x]; $q = $l[$y]
            if($p.Name -eq $q.Name -and $p.From -eq $q.From){ continue }
            $inside = $q.From -ge $p.From -and $q.To -le $p.To
            # a block may hold variables, and smaller blocks, entirely
            # a block may hold smaller blocks, and it may hold variables if it is one that others are built on, e.g. A_CORE
            # or A_DEMO, but a block that is data itself holds no variables
            if($inside -and $p.Block -and ($q.Block -or $containers.Contains($p.Name))){ continue }
            # two that are meant to share, one of them names the other on its own line, e.g. "the same byte as gub_core_stage"
            if($p.Text -match "\b$($q.Name)\b" -or $q.Text -match "\b$($p.Name)\b"){ continue }
            $faults.Add(("{0}: {1} ({2}:{3}, {4:X4} to {5:X4}) and {6} ({7}:{8}, {9:X4} to {10:X4}) share bytes" -f $where, $p.Name, $p.File, $p.Line, $p.From, $p.To, $q.Name, $q.File, $q.Line, $q.From, $q.To))
        }
    }
}

# the core data page, shared by everything, the scratch areas' insides and the library's private storage apart
Check ($sized | Where-Object { -not (InScratch $_) -and -not (InPrivate $_) -and $_.From -ge 0xC000 }) 'the core data'
# each module on its own: its scratch area uses and its private storage
foreach($m in $modules){
    $seen = New-Object Collections.Generic.HashSet[string]; Closure $m $seen
    Check ($sized | Where-Object { $seen.Contains($_.File) -and $_.File -notin $shared -and ((InScratch $_) -or (InPrivate $_)) }) $m
}
$faults | Select-Object -Unique
