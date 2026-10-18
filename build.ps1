# -NoRun     builds and updates the SD card images, but does not start the emulator at the end
# -Full      compiles every module and makes the font and the emulator settings again, whether or not anything has changed
# -Jobs <n>  how many modules to compile at the same time, as many as the computer has processors if not given
# -Start <x> which way to start the emulator at the end, za, zb, zf or zd, in place of the one chosen at the foot of this script
Param( [switch]$NoRun, [switch]$Full, [int]$Jobs = 0, [string]$Start = '' )
$ErrorActionPreference = 'Stop'


###################################################################################################################################
#region version table
#   vers    date          who   description
#   ----    ----          ---   -----------
#   v0.01   xx-Jan-2026   sdo   First compilations.
#   v0.03   20-May-2026   sdo   Begin to attempt to do away with the heap.
#   v0.04    9-Oct-2026   sdo   Start to look at this again, and tidy paths, and function zz to run.
#   v0.05   15-Oct-2026   sdo   The root folder holding the tools is found by looking upwards, not written in.
#   v0.06   15-Oct-2026   sdo   The SD card image is made by the first build, from a NextZXOS card already on the PC.
#   v0.07   18-Oct-2026   sdo   Rebuilt on poc4uat's build script: sources in src, everything made in build, a dated copy of
#                               every log in logs, only what has changed is compiled, three SD card images (base, zb, za),
#                               the zf, za, zb and zd starts, and the checks for fixed addresses and for use of the ROM.
#   v0.08   18-Oct-2026   sdo   v0.05 and v0.06 again on top of v0.07: the tools are found by looking upwards, and the base
#                               card is copied from the NextZXOS card that comes with ZEsarUX; the licence goes on the card
#                               as zxpaging.lic; tools\make-sld.py copied from poc4uat, so zd shows the source.
#   v0.09   18-Oct-2026   sdo   The font is made by src\create-font.ps1 into build\font.bin, when it is not there or is
#                               older than the script; there is no src\font.fon any more.
#   v0.10   18-Oct-2026   sdo   The emulator settings for zf, za, zb and zd are made in build when src\zesarux.cfg, or this
#                               script, is newer than them, not at every start; the breakpoints in it are commented out.
#   v0.11   18-Oct-2026   sdo   zxpaging: a copy of poc2demo as it stood at v0.10, under its new name, to be shared.
###################################################################################################################################
$myScriptVersion = 'v0.11'
###################################################################################################################################
#endregion


###################################################################################################################################
#region helper functions
Function dt {
    [System.DateTime]::Now.ToString( 'yyyy-MM-dd HH:mm:ss' )
}

Function dts {
    [System.DateTime]::Now.ToString( 'yyyyMMdd-HHmmss' )
}

Function Log( [string]$Text, [string]$Colour ) {
    $Colours = @('Black','White','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','Gray')
    $DateTime = "$(dt)"
    Write-Host $DateTime -NoNewline
    If ( [string]::IsNullOrEmpty( $Text ) ) {
        Write-Host
    } Else {
        If ( [string]::IsNullOrEmpty( $Colour ) ) {
            Write-Host "  $Text"
        } ElseIf ( $Colour -in $Colours ) {
            Write-Host "  $Text" -ForegroundColor $Colour
        } Else {
            Write-Host "  $Text" -ForegroundColor DarkRed
        }
    }
    $Output = ( $DateTime + '  ' + $Text ).Trim()
    If ( -not [string]::IsNullOrEmpty( $myScriptLog ) ) {
        Add-Content -Path $myScriptLog -Value $Output -Force -Encoding Ascii
    }
    Start-Sleep -Milliseconds 20
}

Function Debug( [string]$Text ) {
    If ( $Debug ) { Log $Text DarkCyan }
}

Function Logger( $List ) {
    If ( [string]::IsNullOrEmpty( $List ) ) {
        Log '...(nothing to list)...'
        Return
    }
    $List.Split( [System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries ) |
        ForEach-Object { Log "    $_" }
}

Function Abort( [string]$Text ) {
    If ( -not [string]::IsNullOrEmpty( $Text ) ) { Log $Text Red }
    Log '...aborting...' Red
    Save-Log
    Write-Host
    # N.B: exit status 1, so that whatever ran the build can tell it failed, it was "Break Script", which left it 0
    Exit 1
}

Function Quit( [string]$Text ) {
    If ( -not [string]::IsNullOrEmpty( $Text ) ) { Log $Text }
    Log '...script quitting...'
    Save-Log
    Write-Host
    Break Script
}

Function IsNumeric( [string]$Value ) {
    Try {
        $Null = [convert]::ToInt32( $Value )
    } Catch {
        Return $False
    }
    Return $True
}

Function Save-Log {
    # the very last thing the script does, however it ends: keeps this build's log, by copying it into the logs folder
    # beside the script under a name that carries the date and time the build started, e.g. build.log.2026-10-11-12-30-05.log
    # ...build.log itself is wiped at the start of every build, the copies in the logs folder are never touched again
    # N.B: this must not stop the script or hide why it is ending, so anything that goes wrong in here is only reported
    If ( [string]::IsNullOrEmpty( $myScriptLog ) -or $script:LogSaved ) { Return }
    $script:LogSaved = $True
    Try {
        $LogsPath = Join-Path -Path $myScriptPath -ChildPath 'logs'
        If ( -not ( Test-Path -Path $LogsPath -PathType Container ) ) { $Null = New-Item -Path $LogsPath -ItemType Directory }
        $LogCopy = Join-Path -Path $LogsPath -ChildPath "$($myScriptName).log.$($myScriptStart.ToString( 'yyyy-MM-dd-HH-mm-ss' )).log"
        Log "...log kept as:  $LogCopy"
        Copy-Item -Path $myScriptLog -Destination $LogCopy -Force
    } Catch {
        Write-Host "...could not keep a copy of the log:  $_" -ForegroundColor Red
    }
}

Function Run( [string]$Program, [object[]]$Arguments, [switch]$AllowFailure, [string]$Only ) {
    # runs one of the build tools (the compiler, the assembler, the SD card image tool) and puts a faithful record of it in the log:
    # the exact command line, every line the tool printed, to its output and to its error stream alike, in the order they
    # came, and the tool's exit status...
    # ...a status other than 0 stops the build, unless -AllowFailure says that failing is expected (e.g. deleting a file that
    # may not be there yet), the status is always returned in $script:RunStatus
    # -Only <text> logs just the lines containing that text (and says how many there were in all), for long listings
    $CommandLine = ( @( $Program ) + @( $Arguments | ForEach-Object { If ( "$_" -match '\s' ) { '"' + "$_" + '"' } Else { "$_" } } ) ) -join ' '
    Log "    > $CommandLine" DarkGray

    # each line is logged the moment the tool prints it, so the screen and the log both follow the tool as it runs...
    # ...N.B: this relies on PowerShell 7.2 or later, where a line on a tool's error stream is just data: older versions
    # treat it as a failure of the script when $ErrorActionPreference is 'Stop', which is why the script checks the
    # version when it starts, 'Stop' stays in force throughout
    $Total = 0
    $Shown = 0
    & $Program @Arguments 2>&1 | ForEach-Object {
        $IsError = $_ -is [System.Management.Automation.ErrorRecord]
        ForEach ( $Line In ( "$_" -split "`r?`n" ) ) {
            $Total++
            If ( [string]::IsNullOrEmpty( $Only ) -or $Line.Contains( $Only ) ) {
                $Shown++
                If ( $IsError ) { Log "    ! $Line" Yellow } Else { Log "    | $Line" }
            }
        }
    }
    $script:RunStatus = $LastExitCode
    If ( -not [string]::IsNullOrEmpty( $Only ) ) { Log "    ($Shown of $Total lines shown, those containing '$Only')" DarkGray }
    If ( $script:RunStatus -eq 0 ) {
        Log "    = status 0" DarkGray
    } ElseIf ( $AllowFailure ) {
        Log "    = status $($script:RunStatus), which is allowed here" DarkGray
    } Else {
        Abort "...failed, status:  $($script:RunStatus)"
    }
}
#endregion


##################################################################################################################################
#region script setup
$myScriptSpec  = [System.IO.FileInfo]$PSCommandPath
$myScriptPath  = $myScriptSpec.Directory
$myScriptName  = $myScriptSpec.BaseName
$myScriptLog   = Join-Path -Path $myScriptPath -ChildPath "$($myScriptName).log"
$myScriptStart = [System.DateTime]::Now      # names this build's copy of the log, see Save-Log
$LogSaved      = $False

If ( Test-Path -Path $myScriptLog -PathType Leaf ) { $Null = Remove-Item -Path $myScriptLog -Force }

$myUsername = 'sdo'                          # not the real one, the log may be shared

Log
Log
Log 'script...'
Log "...script:     $myScriptSpec"
Log "...path:       $myScriptPath"
Log "...log file:   $myScriptLog"
Log "...version:    $myScriptVersion"
Log "...username:   $myUsername"
Log '...done...'

# the way this script captures what the build tools print needs PowerShell 7.2 or later, see Run()
If ( $PSVersionTable.PSVersion -lt [version]'7.2' ) { Abort "...this script needs PowerShell 7.2 or later, this is $($PSVersionTable.PSVersion)" }
Log "...powershell: $($PSVersionTable.PSVersion)"

# anything that goes wrong in the script itself, as opposed to in one of the tools, is put in the log too before the build stops
Trap {
    Log "...the build script itself failed:  $_" Red
    ForEach ( $TraceLine In ( "$($_.ScriptStackTrace)" -split "`r?`n" ) ) { Log "    $TraceLine" Red }
    Log '...aborting...' Red
    Save-Log
    Write-Host
    Break
}
#endregion


###################################################################################################################################
#region define locations and tools
$CompilerName   = 'boriel'
$LinkerName     = 'sjasmplus'
$EmulatorName   = 'cspect'
$EmulatorName   = 'zesarux'
$ToolsName      = 'tools'
$ProjectName    = $myScriptPath.Name        # the folder this script is in: the nex file and the card images are named after it

# the root folder that holds the tools is found, not written in: it is the nearest folder above this script's that has the
# compiler in it (boriel\zxbc.py), so the project works wherever it is put, at any depth below the root
$RootPath       = $myScriptPath
While ( $RootPath -and -not ( Test-Path -Path ( Join-Path -Path $RootPath.FullName -ChildPath "$CompilerName\zxbc.py" ) -PathType Leaf ) ) {
    $RootPath = $RootPath.Parent
}
If ( -not $RootPath ) { Abort "...no folder above $myScriptPath has the compiler in it ($CompilerName\zxbc.py)" }
$RootPath       = $RootPath.FullName
Log "...root:       $RootPath"

$DocsPath       = Join-Path -Path $RootPath -ChildPath 'docs'
$DownloadsPath  = Join-Path -Path $RootPath -ChildPath 'downloads'
$CompilerPath   = Join-Path -Path $RootPath -ChildPath $CompilerName
$LinkerPath     = Join-Path -Path $RootPath -ChildPath $LinkerName
$EmulatorPath   = Join-Path -Path $RootPath -ChildPath $EmulatorName
$ToolsPath      = Join-Path -Path $RootPath -ChildPath $ToolsName
$ProjectPath    = $myScriptPath.FullName

# the main tools...
$Compiler       = Join-Path -Path $CompilerPath -ChildPath 'zxbc.py'
$Linker         = Join-Path -Path $LinkerPath   -ChildPath "$LinkerName.exe"
$Emulator       = Join-Path -Path $EmulatorPath -ChildPath "$EmulatorName.exe"
$hdfmonkey      = Join-Path -Path $ToolsPath    -ChildPath 'hdfmonkey.exe'

# where things are within the project folder, which is the folder this script is in...
#   src     everything we write: the .bas sources, the nex layout (.cfg), the font, the text of the opening screen
#   build   everything the build makes on the way to the nex file, compiled code, listings, maps, data pages: all of it can be deleted
#           at any time, the next build makes it again, nothing in there is ever edited by hand
#   logs    a dated copy of every build's log
# ...the tools are run from the project folder, and are given these as short relative paths, which keeps the log readable
Set-Location -Path $myScriptPath
$SourceDir = 'src'
$BuildDir  = 'build'
$DataDir   = Join-Path -Path $BuildDir -ChildPath 'data'
ForEach ( $Folder In @( $BuildDir, $DataDir ) ) {
    If ( -not ( Test-Path -Path $Folder -PathType Container ) ) { $Null = New-Item -Path $Folder -ItemType Directory }
}

$CardSource   = Join-Path -Path $EmulatorPath -ChildPath 'tbblue.mmc'                # where the base card image comes from, if it has to be made: the NextZXOS card that comes with ZEsarUX
$CardBase     = "$($ProjectName)-base.mmc"                                        # the untouched NextZXOS card image, see "populate the SD card images"
$CardBrowser  = "$($ProjectName)-zb.mmc"                                          # a copy of the base with the nex file and the licence on it
$CardAutoExec = "$($ProjectName)-za.mmc"                                          # the same with autoexec.bas on it too
$NexName      = "$($ProjectName).nex"
$NexPath      = $NexName                                                        # relative, for the tools: beside this script, with the card images
$NexFile      = Join-Path -Path $myScriptPath -ChildPath $NexPath                # in full, for reading it back

# define MMU page addresses...
$Addr_0000 = 0x0000
$Addr_2000 = 0x2000
$Addr_4000 = 0x4000
$Addr_6000 = 0x6000
$Addr_8000 = 0x8000
$Addr_A000 = 0xA000
$Addr_C000 = 0xC000
$Addr_E000 = 0xE000
#endregion


###################################################################################################################################
#region show tooling versions
Log '...versions...'
Function versions {
    python $Compiler --version 2>&1
    & $Linker        --version 2>&1
    & $Emulator      --version 2>&1
}
Logger ( versions | Out-String )
#endregion


###################################################################################################################################
#region the heap, and the compiler's options
# there is ONE heap (it is where strings are built), and it sits at the very end of the core data page...
# ...i.e. the last $HeapSize bytes below $E000 (the core data page is in MMU 6), so the fixed variables growing up from $C000 keep one continuous run of free space...
# ...the core and every stage are compiled with exactly the same --heap-size and --heap-address, so they all share that one heap...
# ...that is what lets a stage pass a string to a core routine: the stage builds it in the heap, and the core frees it from the same heap...
# ...giving the address explicitly also keeps the heap out of the compiled file, otherwise it would be placed in front of the code...
# ...only the core prepares the heap (once, at start up, see the top of core.bas), a stage must never do so...
# ...the loader uses no strings, so it gets no heap at all
$HeapSize  = 1024
$Addr_Heap = $Addr_E000 - $HeapSize
$HeapNone  = 0

# every module is compiled twice, once to assembler (never used by the build, it is there for us to read) and once to
# the binary that goes into the nex file, with a map of where everything ended up...
# ...the options that every module shares are here, so that they cannot drift apart
$CompilerOptions = @( '--headerless', '--explicit', '--strict', '--zxnext', '-i', '--arch', 'zxnext', '--opt-strategy', 'size' )
#endregion


###################################################################################################################################
#region list the modules
# every module the build compiles, and what each needs beyond the shared options: where it is to run, the warnings to
# silence, and its heap...
# ...N.B: this is the ONE list of them, a new stage or library is added to $Stages here and nowhere else in this script
$Stages = @( 'init', 'left', 'centre', 'right', 'lib-demo' )

$Modules = @()
# the boot loader, it uses no strings, so it gets no heap at all
$Modules += @{ Name = 'load' ; Org = $Addr_C000 ; Extra = @( '--heap-size', $HeapNone ) }
# the core engine, this sits at address $8000 (MMU 4 and 5), see the memory map at the top of constants.bas
$Modules += @{ Name = 'core' ; Org = $Addr_8000 ; Extra = @( '-W140', '-W160', '--heap-size', $HeapSize, '--heap-address', $Addr_Heap ) }
# the paged stage modules, these all target the MMU3 slot at $6000 (24576)
ForEach ( $Stage In $Stages ) {
    $Modules += @{ Name = "stage-$($Stage)" ; Org = $Addr_6000 ; Extra = @( '-W150', '--heap-size', $HeapSize, '--heap-address', $Addr_Heap ) }
}

Function Get-CompileArguments( $Module, [string]$Format ) {
    # the compiler's command line for one module, $Format is 'asm' or 'bin'
    # N.B: warning 170 is "function is never called", silenced everywhere, every stage includes all of the core's shims and uses a few
    $Name      = $Module.Name
    $Arguments = @( $Compiler, "$SourceDir\$Name.bas", '-f', $Format, '-o', "$BuildDir\$Name.$Format", '--org', $Module.Org, '-W170' ) + $Module.Extra + $CompilerOptions
    If ( $Format -eq 'bin' ) { $Arguments += @( '-M', "$BuildDir\$Name.map" ) }
    $Arguments
}
#endregion


###################################################################################################################################
#region check that no two fixed address variables share a byte
# every "Dim ... At <address>" and every sized #define of an address is worked out to the byte, tools\check-addresses.ps1,
# and the build stops if any two overlap, N.B: it twice happened that one did, and was only found when a test went wrong
$Overlaps = @( & ( Join-Path $myScriptPath.FullName 'tools\check-addresses.ps1' ) -SourceDir $SourceDir )
If ( $Overlaps.Count -gt 0 ) {
    $Overlaps | ForEach-Object { Log "    $_" }
    Abort "...$( $Overlaps.Count ) fault(s) in the fixed addresses, see above"
}
Log "...checked:  no two fixed address variables share a byte"
#endregion


###################################################################################################################################
#region work out which modules need compiling
# a module is compiled only if what the last build made of it can no longer be trusted, that is if...
#   - a full build was asked for (-Full)
#   - its .bin, .asm or .map is not there
#   - its own .bas, or any file that it includes, or that those include in their turn, was written after its .bin was made...
#     ...so a change to constants.bas or globals.bas, which everything includes, compiles everything
#   - the compiler, or the options this script gives it for that module, are not what they were when its .bin was made...
#     ...each module has a small file beside its .bin, <name>.how, which records exactly that
# ...otherwise the files that are in the build folder are used as they are
# N.B: a .bin is given the time its compilation STARTED, not the time it finished, so that a source saved while the
# compiler was running is seen as newer than the .bin by the next build
# N.B: only the core is affected when core.bas changes, the stages reach it through its jump table, whose addresses
# are in constants.bas, they do not depend on where the compiler put anything inside the core

$CompilerVersion = ( python $Compiler --version 2>&1 | Out-String ).Trim()

$IncludesOf = @{}       # for each source file already looked at, the names of the files it includes
Function Get-Sources( [string]$Name ) {
    # the full paths of a module's own source and of everything it includes, directly or not
    # N.B: an include that is not in our src folder is one of the compiler's own library files, those are covered by the
    # compiler's version, see above
    $Found = [ordered]@{}
    $Queue = New-Object System.Collections.Generic.Queue[string]
    $Queue.Enqueue( "$Name.bas" )
    While ( $Queue.Count -gt 0 ) {
        $File = $Queue.Dequeue().ToLower()
        If ( $Found.Contains( $File ) ) { Continue }
        $Path = Join-Path -Path $myScriptPath -ChildPath ( Join-Path -Path $SourceDir -ChildPath $File )
        If ( -not ( Test-Path -Path $Path -PathType Leaf ) ) { Continue }
        $Found[$File] = $Path
        If ( -not $IncludesOf.ContainsKey( $File ) ) {
            $IncludesOf[$File] = @( [regex]::Matches( [System.IO.File]::ReadAllText( $Path ), '(?im)^[ \t]*#[ \t]*include[ \t]+(?:once[ \t]+)?["<]([^">\r\n]+)[">]' ) | ForEach-Object { $_.Groups[1].Value } )
        }
        ForEach ( $Include In $IncludesOf[$File] ) { $Queue.Enqueue( $Include ) }
    }
    @( $Found.Values )
}

Function Get-How( $Module ) {
    # what a module's .how file should say: the compiler, and the two command lines used to compile it
    @( $CompilerVersion, ( ( Get-CompileArguments $Module 'asm' ) -join ' ' ), ( ( Get-CompileArguments $Module 'bin' ) -join ' ' ) ) -join "`n"
}

Function Get-StaleReason( $Module ) {
    # why a module has to be compiled, or nothing at all if what is in the build folder is still good
    $Name = $Module.Name
    If ( -not ( Test-Path -Path "$SourceDir\$Name.bas" -PathType Leaf ) ) { Abort "...there is no $SourceDir\$Name.bas" }
    If ( $Full ) { Return 'a full build was asked for' }
    ForEach ( $Made In @( 'bin', 'asm', 'map', 'how' ) ) {
        If ( -not ( Test-Path -Path "$BuildDir\$Name.$Made" -PathType Leaf ) ) { Return "there is no $Name.$Made" }
    }
    If ( ( [System.IO.File]::ReadAllText( ( Join-Path -Path $myScriptPath -ChildPath "$BuildDir\$Name.how" ) ) ) -ne ( Get-How $Module ) ) { Return 'the compiler or its options have changed' }
    # N.B: the core is padded to 16KB once it has been checked, a build that compiled it and then stopped before that
    # leaves it short, and the next build used it as it was, 14 October 2026
    If ( $Name -eq 'core' -and ( Get-Item -Path "$BuildDir\core.bin" ).Length -ne 16384 ) { Return 'core.bin was never padded to 16KB, an earlier build stopped' }
    $BinTime = ( Get-Item -Path "$BuildDir\$Name.bin" ).LastWriteTimeUtc
    ForEach ( $Source In ( Get-Sources $Name ) ) {
        If ( ( Get-Item -Path $Source ).LastWriteTimeUtc -gt $BinTime ) { Return "$( Split-Path -Path $Source -Leaf ) has changed" }
    }
}

Log '...working out what needs compiling...'
$Stale = @()
ForEach ( $Module In $Modules ) {
    $Reason = Get-StaleReason $Module
    If ( -not [string]::IsNullOrEmpty( $Reason ) ) {
        $Module.Reason = $Reason
        $Stale += $Module
        Log "...to compile:  $($Module.Name)  ($Reason)"
    }
}
Log "...$( $Stale.Count ) of $( $Modules.Count ) modules to compile, the other $( $Modules.Count - $Stale.Count ) are up to date"
#endregion


###################################################################################################################################
#region compile
# the modules do not depend on one another, so several are compiled at the same time, as many as the computer has
# processors unless -Jobs says otherwise (-Jobs 1 compiles them one after another)...
# ...each one's output is held until it has finished and is then put in the log in one piece, exactly as Run() would
# have logged it, so the log reads as if they had been compiled one at a time, in the order they happened to finish
If ( $Jobs -lt 1 ) { $Jobs = [System.Environment]::ProcessorCount }
$Compiled = @{}         # the modules compiled by this build, and when each compilation started
$Failed   = @()

If ( $Stale.Count -gt 0 ) {
    Log "...compiling, up to $Jobs at a time..."
    ForEach ( $Module In $Stale ) {
        # nothing of the old build of a module may survive a compilation that fails, it would look up to date next time
        ForEach ( $Made In @( 'bin', 'how' ) ) {
            If ( Test-Path -Path "$BuildDir\$($Module.Name).$Made" -PathType Leaf ) { Remove-Item -Path "$BuildDir\$($Module.Name).$Made" -Force }
        }
        $Module.Steps = @( @{ What = 'ASM' ; Arguments = @( Get-CompileArguments $Module 'asm' ) }, @{ What = 'bin' ; Arguments = @( Get-CompileArguments $Module 'bin' ) } )
        $Module.Dir   = "$myScriptPath"
    }

    $Stale | ForEach-Object -ThrottleLimit $Jobs -Parallel {
        # N.B: this block runs on its own, it cannot use the script's functions or variables, it is given the module
        # and hands back what the compiler printed, which the script then logs, see below
        $Module = $_
        Set-Location -LiteralPath $Module.Dir
        $Started = [System.DateTime]::Now
        $Steps   = @()
        ForEach ( $Step In $Module.Steps ) {
            $Arguments = @( $Step.Arguments )
            $Lines  = @( & python @Arguments 2>&1 | ForEach-Object { [pscustomobject]@{ IsError = ( $_ -is [System.Management.Automation.ErrorRecord] ) ; Text = "$_" } } )
            $Status = $LastExitCode
            $Steps += [pscustomobject]@{ What = $Step.What ; Arguments = $Arguments ; Lines = $Lines ; Status = $Status }
            If ( $Status -ne 0 ) { Break }
        }
        [pscustomobject]@{ Name = $Module.Name ; Started = $Started ; Seconds = ( [System.DateTime]::Now - $Started ).TotalSeconds ; Steps = $Steps }
    } | ForEach-Object {
        $Result = $_
        $Name   = $Result.Name
        $Good   = $True
        ForEach ( $Step In $Result.Steps ) {
            Log "...compiling to $($Step.What):  $Name"
            Log "    > $( ( @( 'python' ) + @( $Step.Arguments | ForEach-Object { If ( "$_" -match '\s' ) { '"' + "$_" + '"' } Else { "$_" } } ) ) -join ' ' )" DarkGray
            ForEach ( $Printed In $Step.Lines ) {
                ForEach ( $Line In ( $Printed.Text -split "`r?`n" ) ) {
                    If ( $Printed.IsError ) { Log "    ! $Line" Yellow } Else { Log "    | $Line" }
                }
            }
            If ( $Step.Status -eq 0 ) {
                Log "    = status 0" DarkGray
            } Else {
                Log "    = status $($Step.Status)" Red
                $Good = $False
            }
        }
        If ( $Good -and ( Test-Path -Path "$BuildDir\$Name.bin" -PathType Leaf ) ) {
            $Compiled[$Name] = $Result.Started
            Log "...compiled:  $Name  ($( [math]::Round( $Result.Seconds, 1 ) ) seconds)"
        } Else {
            $Failed += $Name
            Log "...FAILED:  $Name" Red
        }
    }

    # a module that failed leaves nothing behind that the next build could take for good...
    ForEach ( $Name In $Failed ) {
        If ( Test-Path -Path "$BuildDir\$Name.bin" -PathType Leaf ) { Remove-Item -Path "$BuildDir\$Name.bin" -Force }
    }
    # ...and one that worked has how it was made written down, and its .bin given the time its compilation started
    ForEach ( $Module In $Stale ) {
        If ( $Compiled.ContainsKey( $Module.Name ) ) {
            [System.IO.File]::WriteAllText( ( Join-Path -Path $myScriptPath -ChildPath "$BuildDir\$($Module.Name).how" ), ( Get-How $Module ) )
            ( Get-Item -Path "$BuildDir\$($Module.Name).bin" ).LastWriteTime = $Compiled[$Module.Name]
        }
    }
    If ( $Failed.Count -gt 0 ) { Abort "...failed to compile:  $( $Failed -join ', ' )" }
    Log '...compiled...'
}

Function Reject( [string]$Name, [string]$Text ) {
    # a module that compiled but fails one of the checks below must not be taken for good by the next build either
    ForEach ( $Made In @( 'bin', 'how' ) ) {
        If ( Test-Path -Path "$BuildDir\$Name.$Made" -PathType Leaf ) { Remove-Item -Path "$BuildDir\$Name.$Made" -Force }
    }
    Abort $Text
}
#endregion


###################################################################################################################################
#region check that nothing uses the ZX Spectrum's system variables
# the compiler's own routine for CHR keeps a value, while it works, at address 23629 ($5C4D, the system variable DEST)...
# ...on our machine that is not a system variable, it is part of whatever page of data is in MMU 2, and two bytes of that
# page were overwritten by every CHR until this was found, see fs_core_char() in core.bas, which is to be used instead...
# ...the assembler listing of every module is looked at, whether this build compiled it or not, it costs nothing
ForEach ( $Module In $Modules ) {
    $Name = $Module.Name
    If ( Select-String -Path "$BuildDir\$Name.asm" -Pattern 'EQU\s+23629' -Quiet ) {
        Reject $Name "...$Name uses CHR, which writes into the paged data at 5C4D, use fs_core_char() instead"
    }
}
Log "...checked:  none of the $( $Modules.Count ) modules uses CHR"
#endregion


###################################################################################################################################
#region check the core
# ...really does start with code at $8000...
# ...because that is the address the loader jumps to...
# ...the compiler puts a module's own data (ordinary variables, array descriptors) in front of its code...
# ...this script used to hide that by wiping the first bytes of core.bin and writing a "di : jp $0100" over them by hand...
# ...now core.bas simply has no such data, and its own start up code is what sits at $8000
$MainLine = Get-Content -Path "$BuildDir\core.map" | Where-Object { $_ -match '__MAIN_PROGRAM__' } | Select-Object -First 1
$MainAddr = ( $MainLine -split ':' )[0].Trim()
If ( $MainAddr -ne '8000' ) { Reject 'core' "...core does not start with code, its code starts at $MainAddr instead of 8000, it must have data in front of it" }
Log '...checked:  core starts with code at 8000'

If ( $Compiled.ContainsKey( 'core' ) ) {
    # check that the core's code stops short of the interrupt handler, which the loader builds at $BDBD, near the top of the second core page...
    # ...the core starts at $8000, so its code may be at most $BDBD - $8000 = 15805 bytes long
    $CoreLimit  = 0xBDBD - 0x8000
    $CoreFile   = Get-Item -Path "$BuildDir\core.bin"
    $CoreLength = $CoreFile.Length
    $CoreSize   = [math]::Round( ( $CoreLength / 16384 ) * 100, 2 )
    Log "...core size:  $CoreLength bytes  ($CoreSize% of 16KB)"
    If ( $CoreLength -gt $CoreLimit ) { Reject 'core' "...core is too big, it is $CoreLength bytes and must not exceed $CoreLimit, it would run into the interrupt handler" }
    Log "...checked:  core is $CoreLength bytes, the limit is $CoreLimit"
    # N.B: the size is written down, because core.bin is about to be padded and can no longer say, see "report the fullest modules"
    Set-Content -Path "$BuildDir\core.size" -Value $CoreLength -Encoding Ascii

    # pad the core.bin file out to its full two pages...
    Log '...padding core.bin...'
    $CoreBytes = [System.IO.File]::ReadAllBytes( $CoreFile.FullName )

    # now pad out the tail to 16KB...
    $PaddedBytes = New-Object Byte[] 16384
    [Array]::Copy( $CoreBytes, $PaddedBytes, $CoreBytes.Length )

    # and save the padded copy, N.B: with the time its compilation started put back, see "work out which modules need compiling"
    [System.IO.File]::WriteAllBytes( $CoreFile.FullName, $PaddedBytes )
    ( Get-Item -Path "$BuildDir\core.bin" ).LastWriteTime = $Compiled['core']
    Log '...padded core.bin to 16KB...'
} Else {
    # N.B: core.bin was padded to 16KB by the build that compiled it, so its real size can no longer be read from the file
    Log '...core.bin is as an earlier build left it, its size was checked then, and it was padded to 16KB then'
}
#endregion


###################################################################################################################################
#region check every stage
# ...really does start with code at $6000
# ...because that is the address the core calls...
# ...the compiler puts a module's own data (ordinary variables, array descriptors, a heap) in front of its code...
# ...so a stage must only use variables declared with "At <address>", and must not use arrays (strings are fine, they live in the shared heap)...
# ...the map file tells us where the compiler placed the first instruction of the main program
# N.B: every stage is checked by every build, whether this build compiled it or not, it costs nothing
ForEach ( $Stage In $Stages ) {
    $Name = "stage-$($Stage)"
    $MainLine = Get-Content -Path "$BuildDir\$($Name).map" | Where-Object { $_ -match '__MAIN_PROGRAM__' } | Select-Object -First 1
    $MainAddr = ( $MainLine -split ':' )[0].Trim()
    If ( $MainAddr -ne '6000' ) { Reject $Name "...$Name does not start with code, its code starts at $MainAddr instead of 6000, it must have data in front of it" }
    Log "...checked:  $Name starts with code at 6000"
    # ...and that it fits in its one 8KB page, anything beyond that would simply be missing when the stage ran
    $StageSize = ( Get-Item -Path "$BuildDir\$($Name).bin" ).Length
    # ...a library keeps the top 512 bytes of its page for its own working storage (A_LIB_PRIVATE in constants.bas), so its code must stop short of that
    $StageLimit = $( If ( $Stage -like 'lib-*' ) { 7680 } Else { 8192 } )
    If ( $StageSize -gt $StageLimit ) { Reject $Name "...$Name is $StageSize bytes, which is more than the $StageLimit it may be" }
    Log "...checked:  $Name is $StageSize bytes of the $StageLimit it may be"
}
#endregion


###################################################################################################################################
#region check for use of ROM
# check that the core and the stages use nothing of the compiler's that needs the ZX Spectrum ROM or its system variables...
# ...neither is there once our own pages are in MMU 0, 1 and 2, see the notes near the top of constants.bas for the whole story...
# ...each is found by a line the compiler's library routine brings with it into the module's .asm file, and only the first
# one found is reported, so the screen commands come before MEMBOT, which their library brings in as well
# N.B: the loader is not checked, it runs before any of our pages are in those slots, while the ROM is still there
$Forbidden = [ordered]@{
    'EQU\s+23629\b'                                 = 'CHR, it keeps a value at $5C4D (DEST), use fs_core_char()'
    'rst\s+28h'                                     = 'floating point (the ROM calculator): STR$, VAL, a Float sum, SIN, SQR and the like, use fs_core_number() for STR$'
    'EQU\s+23(606|612|675|677|681|684|686|688|693|695|697)\b' = 'PRINT, CLS, INK, PLOT or another ULA screen command, use s_core_print_string_at() and the like'
    'EQU\s+(23698|5C92h)\b'                         = 'an array, a Mod on Fixed, LOAD or SAVE (MEMBOT, $5C92)'
    'EQU\s+2367[02]\b'                              = 'RND or RANDOMIZE (the seed and FRAMES system variables)'
    'EQU\s+0?(28E|31E|333)h'                        = 'INKEY$ (the ROM keyboard routines), use fub_core_scan_key()'
    '(jp|call)\s+(1F3D|03F8|03B5|0562|0970)h'       = 'PAUSE, BEEP, LOAD or SAVE (the ROM), see the notes in constants.bas for what to use'
}
ForEach ( $Name In @( 'core' ) + ( $Stages | ForEach-Object { "stage-$_" } ) ) {
    ForEach ( $Pattern In $Forbidden.Keys ) {
        $Hit = Select-String -Path "$BuildDir\$($Name).asm" -Pattern $Pattern | Select-Object -First 1
        If ( $Hit ) { Abort "...$Name uses $($Forbidden[ $Pattern ]), line $($Hit.LineNumber) of $($Name).asm: $($Hit.Line.Trim())" }
    }
    Log "...checked:  $Name uses nothing that needs the ROM or its system variables"
}
#endregion


###################################################################################################################################
#region the font
# src\create-font.ps1 makes the 8x8 font, build\font.bin, where sjasmplus.cfg takes it from... it is made again only if it
# is not there, or if the script was written after it, or if -Full was given
# N.B: the script is run as a program of its own, as it ends with Break Script, which would stop this script too
$FontFile = Join-Path -Path $BuildDir -ChildPath 'font.bin'
If ( $Full -or -not ( Test-Path -Path $FontFile ) -or ( ( Get-Item -Path "$SourceDir\create-font.ps1" ).LastWriteTimeUtc -gt ( Get-Item -Path $FontFile ).LastWriteTimeUtc ) ) {
    Log '...making the font...'
    Run 'pwsh' @( '-NoProfile', '-File', "$SourceDir\create-font.ps1", ( Join-Path -Path $myScriptPath -ChildPath $FontFile ) )
} Else {
    Log '...the font is up to date'
}
#endregion


###################################################################################################################################
#region sjasmplus stitch "nex" file
Log '...linking nex file...'
# N.B: the layout file is in src, and names the files it wants without saying where they are: sjasmplus looks beside the
# layout file first, and then in the folder given by --inc, which is where everything the build has made is, the font
# included, the nex file's own name is given in full (and sjasmplus asks for / not \ in paths)
Run $Linker @( "$SourceDir/sjasmplus.cfg","--inc=$BuildDir", '--msg=all', "--lst=$BuildDir/$($ProjectName).lst", '--lstlab', "-DNEX_FILE=`"$( $NexPath.Replace( '\', '/' ) )`"" )
#endregion


###################################################################################################################################
#region clean-up intermediate bin files
# ...to keep the project tidy...
# ...Remove-Item core.bin, stage-*.bin
#endregion


###################################################################################################################################
#region report on the nex file
# nothing in the file is changed here, this only reads back what sjasmplus wrote into its header, as a check on sjasmplus.cfg
Log '...checking nex file...'
$NexBytes = [System.IO.File]::ReadAllBytes( $NexFile )
$Sig = [System.Text.Encoding]::ASCII.GetString( $NexBytes[0..3] )
If ( $Sig -ne 'Next' ) { Abort "...$NexName does not start with 'Next', it starts with '$Sig'" }
Log "...signature:      $Sig"
Log "...file version:   $( [System.Text.Encoding]::ASCII.GetString( $NexBytes[4..7] ) )"
Log "...RAM required:   $( If ( $NexBytes[8] -eq 0 ) { '768KB' } Else { '1792KB (a 2MB Next)' } )"
Log "...16KB banks:     $( $NexBytes[9] )"
Log "...stack pointer:  $( '{0:X4}' -f [BitConverter]::ToUInt16( $NexBytes, 12 ) )"
Log "...entry address:  $( '{0:X4}' -f [BitConverter]::ToUInt16( $NexBytes, 14 ) )"
Log "...entry bank:     $( $NexBytes[139] )"
#endregion


###################################################################################################################################
#region debugging data
# the file the DeZog debugger in VS Code reads to show the source while the program is stepped through in the emulator:
# which address, in which page, is which line, for every module, see tools\make-sld.py and zd below...
# ...only the modules compiled since the last time are worked out again, and the build goes on without the file if
# it cannot be made, the program does not need it
Log '...debugging data...'
Run 'python' @( 'tools\make-sld.py', $ProjectName, '--jobs', $Jobs ) -AllowFailure
If ( $script:RunStatus -ne 0 ) { Log '...the debugging data is not complete, see above, the build goes on...' Yellow }
#endregion


###################################################################################################################################
#region autoexec
# NextZXOS runs the BASIC program c:/nextzxos/autoexec.bas when it boots, we make one whose single line starts our nex file...
# ...it has to be a real saved BASIC program, not a text file: a 128 byte "+3DOS" header, followed by the program itself...
# ...and the header must say which line to start running from, exactly as if it had been saved with: SAVE "autoexec.bas" LINE 10
Function New-AutoExec( [string]$Path, [string]$Command ) {
    $Text = [System.Text.Encoding]::ASCII.GetBytes( $Command )

    # the program is one line: its line number (10, high byte first), the length of the rest of the line (low byte first),
    # the text of the command, and a carriage return to end the line...
    # ...a line that begins with a dot is a "dot command", NextBASIC keeps the rest of such a line as plain text
    $LineLength = $Text.Length + 1
    $Program    = New-Object Byte[] ( 4 + $LineLength )
    $Program[0] = 0x00
    $Program[1] = 0x0A
    $Program[2] = [byte]( $LineLength -band 255 )
    $Program[3] = [byte]( ( $LineLength -shr 8 ) -band 255 )
    $Text.CopyTo( $Program, 4 )
    $Program[ $Program.Length - 1 ] = 0x0D

    # the header...
    $File = New-Object Byte[] ( 128 + $Program.Length )
    [System.Text.Encoding]::ASCII.GetBytes( 'PLUS3DOS' ).CopyTo( $File, 0 )    # bytes 0-7:   the signature
    $File[8]  = 0x1A                                                            # byte 8:      soft end of file marker
    $File[9]  = 0x01                                                            # byte 9:      issue number
    $File[10] = 0x00                                                            # byte 10:     version number
    $File[11] = [byte]( $File.Length -band 255 )                                # bytes 11-14: the length of the whole file, header included
    $File[12] = [byte]( ( $File.Length -shr 8 ) -band 255 )
    $File[15] = 0x00                                                            # byte 15:     file type, 0 = a BASIC program
    $File[16] = [byte]( $Program.Length -band 255 )                             # bytes 16-17: the length of the program
    $File[17] = [byte]( ( $Program.Length -shr 8 ) -band 255 )
    $File[18] = 10                                                              # bytes 18-19: the line to start running from
    $File[19] = 0
    $File[20] = $File[16]                                                       # bytes 20-21: where the variables start, we have none,
    $File[21] = $File[17]                                                       #              so that is straight after the program
    $Program.CopyTo( $File, 128 )

    # byte 127 is a checksum: the sum of bytes 0 to 126, keeping only the low 8 bits
    $Sum = 0
    For ( $i = 0 ; $i -lt 127 ; $i++ ) { $Sum = ( $Sum + $File[$i] ) -band 255 }
    $File[127] = [byte]$Sum

    [System.IO.File]::WriteAllBytes( $Path, $File )
}

Log '...autoexec...'
$AutoExecName = 'autoexec.bas'
$AutoExecPath = Join-Path -Path $myScriptPath -ChildPath ( Join-Path -Path $BuildDir -ChildPath $AutoExecName )
New-AutoExec -Path $AutoExecPath -Command ".nexload $NexName"
Log '...done...'
#endregion


###################################################################################################################################
#region populate the SD card images
# there are three card images, all beside this script, as is the nex file...
#   <project>-base.mmc        the base: a NextZXOS card exactly as it was made, with nothing of ours on it, the build only
#                             ever reads it, and the emulator is never given it...
#                             ...if it is not there it is copied from $CardSource, and kept read-only
#   <project>-zb.mmc          a copy of the base, with our nex file and the licence on it, and no autoexec.bas,
#                             so NextZXOS boots to its own browser menu, see zb
#   <project>-za.mmc          a copy of the base, with our nex file, the licence and our autoexec.bas on it,
#                             so NextZXOS boots and goes straight into the program, see za
# ...the zb and za cards are only copied from the base when they are not there, after that every build just puts the new
# nex file (and the licence, and on the za card autoexec.bas) on to them, so whatever the program has saved on a card, e.g.
# zxpaging.sav, stays there from build to build...
# ...N.B: to start a card again from the base, delete it, the next build makes it
Function Copy-Card( [string]$From, [string]$To ) {
    # N.B: a copy of a read-only file is read-only too, so that is taken off the copy
    Copy-Item -Path $From -Destination $To
    Set-ItemProperty -Path $To -Name IsReadOnly -Value $False
    Log "    copied from $From, $( ( Get-Item -Path $To ).Length ) bytes"
}

# N.B: removing a file fails if it is not on the card, which is fine, so those steps are allowed to fail
Function Update-Card( [string]$Card, [switch]$AutoExec ) {
    If ( -not ( Test-Path -Path $Card -PathType Leaf ) ) {
        Log "    $Card is not there, making it from the base"
        Copy-Card $CardBase $Card
        # the base comes with an autoexec.bas of its own, the NextZXOS welcome, which would run in place of the browser menu
        Run $hdfmonkey @( 'rm', $Card, "/nextzxos/$AutoExecName" ) -AllowFailure
    }
    Run $hdfmonkey @( 'rm',  $Card, "/$NexName" ) -AllowFailure
    Run $hdfmonkey @( 'put', $Card, $NexPath, "/$NexName" )
    # the licence goes with the program wherever it goes, as the licence itself asks, N.B: under a short plain name
    Run $hdfmonkey @( 'rm',  $Card, "/$($ProjectName).lic" ) -AllowFailure
    Run $hdfmonkey @( 'put', $Card, 'LICENSE', "/$($ProjectName).lic" )
    If ( $AutoExec ) {
        Run $hdfmonkey @( 'rm',  $Card, "/nextzxos/$AutoExecName" ) -AllowFailure
        Run $hdfmonkey @( 'put', $Card, "$BuildDir\$AutoExecName", "/nextzxos/$AutoExecName" )
    }
    Run $hdfmonkey @( 'ls',  $Card )
    Run $hdfmonkey @( 'ls',  $Card, '/nextzxos' ) -Only 'autoexec'
}

Log "...base card:  $CardBase"
If ( -not ( Test-Path -Path $CardBase -PathType Leaf ) ) {
    If ( -not ( Test-Path -Path $CardSource -PathType Leaf ) ) {
        Abort "...there is no base SD card image, and no $CardSource to copy one from (a NextZXOS card image that nothing has been added to)"
    }
    Log "    $CardBase is not there, making it"
    Copy-Card $CardSource $CardBase
    Set-ItemProperty -Path $CardBase -Name IsReadOnly -Value $True
}

Log "...browser card:  $CardBrowser"
Update-Card $CardBrowser
Log "...autoexec card:  $CardAutoExec"
Update-Card $CardAutoExec -AutoExec
Log '...done...'
#endregion


###################################################################################################################################
#region the emulator settings
# each way of starting the emulator has its own settings file in the build folder, made from src\zesarux.cfg, which is the
# only one ever edited by hand... they are all made again if any of them is not there, or if src\zesarux.cfg, or this
# script (which says what each start changes), was written after them, or if -Full was given
#   zf  no SD card at all, the nex file is handed straight to the emulator
#   za  the card with autoexec.bas on it
#   zb  the card without autoexec.bas
#   zd  no SD card and no breakpoints (the debugger sets its own), and the remote protocol on port 10001 for DeZog
Function Get-EmulatorSettings( [string]$Which ) {
    $Base = @( Get-Content -Path "$SourceDir\zesarux.cfg" )
    If ( $Which -eq 'za' ) { Return @( $Base | Where-Object { $_ -notmatch 'mmc-file' } ) + "--mmc-file $CardAutoExec" }
    If ( $Which -eq 'zb' ) { Return @( $Base | Where-Object { $_ -notmatch 'mmc-file' } ) + "--mmc-file $CardBrowser" }
    If ( $Which -eq 'zd' ) { Return @( $Base | Where-Object { $_ -notmatch 'mmc|breakpoint' } ) + '--enable-remoteprotocol' + '--remoteprotocol-port 10001' }
    Return @( $Base | Where-Object { $_ -notmatch 'mmc' } )
}
$EmulatorStarts = @( 'zf', 'za', 'zb', 'zd' )
$EmulatorNewest = ( Get-Item -Path "$SourceDir\zesarux.cfg", $PSCommandPath | Sort-Object -Property LastWriteTimeUtc | Select-Object -Last 1 ).LastWriteTimeUtc
$EmulatorStale  = @( $EmulatorStarts | Where-Object { -not ( Test-Path -Path "$BuildDir\zesarux-$_.cfg" ) -or ( Get-Item -Path "$BuildDir\zesarux-$_.cfg" ).LastWriteTimeUtc -lt $EmulatorNewest } )
If ( $Full -or $EmulatorStale.Count -gt 0 ) {
    ForEach ( $Which In $EmulatorStarts ) { Get-EmulatorSettings $Which | Set-Content -Path "$BuildDir\zesarux-$Which.cfg" -Encoding Ascii }
    Log "...emulator settings made from $SourceDir\zesarux.cfg:  $( ( $EmulatorStarts | ForEach-Object { "$BuildDir\zesarux-$_.cfg" } ) -join ', ' )"
} Else {
    Log '...the emulator settings are up to date'
}
#endregion


###################################################################################################################################
#region prepare runtime functions
# there are three ways to start the emulator...
#   zf  fast:   hands our nex file straight to ZEsarUX, which loads it itself with no NextZXOS boot at all...
#               ...N.B: NextZXOS has not run, so anything it would normally have set up is not there, and there is no SD card
#   za  auto:   boots NextZXOS from the card image that has autoexec.bas on it, which runs .nexload on our nex file
#   zb  browse: boots NextZXOS from the card image that has no autoexec.bas, so it stops at its own menu,
#               from where the Browser shows what is on the card, and our nex file can be started by hand
# ...each has its own emulator settings file in the build folder, made by the build from src\zesarux.cfg, see "the emulator
# settings" above, so breakpoints etc. only ever need changing in that one place

Function Start-Keys {
    # tools\zesarux-keys.ahk makes a PC keyboard type what it says into the program: the number pad, Ctrl and the
    # punctuation keys, which ZEsarUX on its own loses or changes, see the top of that file...
    # ...it only acts while a ZEsarUX window has the keyboard, and starting it again just replaces the one running
    $AutoHotkey = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
    $KeysScript = Join-Path -Path $myScriptPath -ChildPath 'tools\zesarux-keys.ahk'
    If ( ( Test-Path -Path $AutoHotkey ) -and ( Test-Path -Path $KeysScript ) ) {
        Start-Process -FilePath $AutoHotkey -ArgumentList "`"$KeysScript`""
        Log '    the PC keyboard script is running (tools\zesarux-keys.ahk)' DarkGray
    } Else {
        Log '    AutoHotkey is not installed, the number pad and Ctrl will not work as the PC keyboard says' Yellow
    }
}
Function Start-Emulator( [string]$Name, [string]$Program ) {
    Start-Keys
    $Config   = "$BuildDir\zesarux-$Name.cfg"                # made by the build, see "the emulator settings"

    $Arguments = @( '--configfile', $Config )
    If ( -not [string]::IsNullOrEmpty( $Program ) ) { $Arguments += $Program }
    Log "    > $Emulator $( $Arguments -join ' ' )" DarkGray
    & $Emulator @Arguments
    $Status = $LastExitCode
    Write-Host
    Log "...emulator status:  $Status"
    Write-Host
}

Function za {
    Log '...launching emulator (via NextZXOS, autoexec.bas starts the program)...'
    Start-Emulator 'za' ''
}

Function zb {
    Log '...launching emulator (via NextZXOS, to its browser menu)...'
    Start-Emulator 'zb' ''
}

Function zd {
    # the same as zf, with the remote protocol switched on for the DeZog debugger in VS Code to connect to, see
    # .vscode\launch.json in the workspace: the debugger loads the nex file itself, so none is given here...
    # ...N.B: on port 10001, not the usual 10000, so that a debugging session and a background test can both run,
    # and without this file's breakpoints, the debugger sets its own
    Log '...launching emulator (for the debugger, waiting for VS Code to connect on port 10001)...'
    # one left running from the last debugging session will do, the debugger loads the new nex file into it
    $Listening = $False
    Try { $Probe = New-Object System.Net.Sockets.TcpClient ; $Probe.Connect( '127.0.0.1', 10001 ) ; $Listening = $True ; $Probe.Close() } Catch { }
    Start-Keys
    If ( $Listening ) { Log '    one is already running, and is left as it is' ; Return }
    $Config   = "$BuildDir\zesarux-zd.cfg"                   # made by the build, see "the emulator settings"
    Log "    > $Emulator --configfile $Config" DarkGray
    Start-Process -FilePath $Emulator -ArgumentList @( '--configfile', $Config ) -WorkingDirectory $myScriptPath.FullName
    # ...and not back to VS Code until the emulator is listening, or the debugger would find nobody there
    ForEach ( $Try In 1..40 ) {
        Start-Sleep -Milliseconds 500
        Try { $Probe = New-Object System.Net.Sockets.TcpClient ; $Probe.Connect( '127.0.0.1', 10001 ) ; $Probe.Close() ; Log '    it is listening' ; Return } Catch { }
    }
    Log '    it did not start listening within 20 seconds' Yellow
}

Function zf {
    Log '...launching emulator (fast, straight into the nex file)...'
    Start-Emulator 'zf' $NexPath
}
#endregion


###################################################################################################################################
#region report the fullest modules
# how many bytes each compiled module has left of what it may be, the ten with the least room first...
#   a stage may be 8192 bytes, one page
#   a library may be 7680, it keeps the top 512 bytes of its page for its own working storage
#   the core may be 15805, it must stop short of the interrupt handler, its size is the one written down when it was
#   last compiled, core.bin itself is padded
#   the loader may be 8192, it has one page, N.B: its stack is at the top of that same page while it runs
Log '...room left in the modules, the ten fullest...'
$Room = @()
$CoreSizeFile = "$BuildDir\core.size"
If ( Test-Path -Path $CoreSizeFile -PathType Leaf ) {
    $Size   = [int]( ( Get-Content -Path $CoreSizeFile | Select-Object -First 1 ).Trim() )
    $Limit  = 0xBDBD - 0x8000
    $Room  += [pscustomobject]@{ Name = 'core' ; Size = $Size ; Limit = $Limit ; Free = $Limit - $Size }
}
$Size   = ( Get-Item -Path "$BuildDir\load.bin" ).Length
$Room  += [pscustomobject]@{ Name = 'load' ; Size = $Size ; Limit = 8192 ; Free = 8192 - $Size }
ForEach ( $Stage In $Stages ) {
    $Name   = "stage-$($Stage)"
    $Size   = ( Get-Item -Path "$BuildDir\$($Name).bin" ).Length
    $Limit  = $( If ( $Stage -like 'lib-*' ) { 7680 } Else { 8192 } )
    $Room  += [pscustomobject]@{ Name = $Name ; Size = $Size ; Limit = $Limit ; Free = $Limit - $Size }
}
$Room | Sort-Object -Property Free, Name | Select-Object -First 10 | ForEach-Object {
    Log ( "    {0,6} bytes free   {1,-30} {2,6} of {3,6}" -f $_.Free, $_.Name, $_.Size, $_.Limit )
}
Log "...$( $Room.Count ) modules, $( ( $Room | Measure-Object -Property Free -Sum ).Sum ) bytes free in all"
#endregion


##################################################################################################################################
#region the end
Log
Log
Log '--------------------------------------------------------------'

$myScriptEnd     = Get-Date
$myScriptElapsed = New-TimeSpan -Start $myScriptStart -End $myScriptEnd

If ( [math]::Truncate( $myScriptElapsed.TotalSeconds ) -lt [math]::Round( $myScriptElapsed.TotalSeconds ) ) {
    $myScriptElapsed += New-TimeSpan -Seconds 1
}

$myScriptStartDisplay   = $myScriptStart.ToString( 'ddd dd-MMM-yyyy HH:mm:ss' )
$myScriptEndDisplay     = $myScriptEnd.ToString(   'ddd dd-MMM-yyyy HH:mm:ss' )
$myScriptElapsedDisplay = "                " + $myScriptElapsed.ToString( 'hh\:mm\:ss' )

Log 'script summary...'
Log "...script start:  $myScriptStartDisplay"
Log "...script end:    $myScriptEndDisplay"
Log "...script run:    $myScriptElapsedDisplay"
Log '...script exiting...'
Save-Log
Write-Host
#endregion


###################################################################################################################################
#region run the emulator
# ...choose which of the three this script uses...
#   za      run emulator, let it boot in to NextZXOS, and start the program via autoexec.bas
#   zb      run emulator, let it boot in to NextZXOS, and go to the browser menu
#   zf      run emulator and boot/jump straight in to NEX file, no NextZXOS, no menu, no browser, no autoexec
#   zd      run emulator and leave it waiting for the debugger in VS Code, which loads the NEX file as zf does
$StartWith = 'zf'
If ( $Start -ne '' ) { $StartWith = $Start }
If ( $NoRun ) {
    Log '...not starting the emulator (-NoRun)...'
} ElseIf ( $StartWith -eq 'za' ) {
    za
} ElseIf ( $StartWith -eq 'zb' ) {
    zb
} ElseIf ( $StartWith -eq 'zd' ) {
    zd
} Else {
    zf
}
#endregion


Break Script