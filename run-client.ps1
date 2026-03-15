#Requires -Version 5.1
<#
.SYNOPSIS
    Astonia 3.5 Community Client - build (if needed) and launch.
.DESCRIPTION
    One script for the client: installs MSYS2 deps if missing, builds the client
    if needed, then launches with correct working directory (client root, for res/)
    and PATH (MSYS2 Clang64 bin, for libpng/SDL DLLs). Saves credentials to
    .client-config. Use from repo root: .\run-client.ps1 -User Name -Password pass
.PARAMETER User
    Character name (required on first run; saved to .client-config).
.PARAMETER Password
    Character password (required on first run; saved to .client-config).
.PARAMETER Server
    Server hostname or IP.  Default: localhost.
.PARAMETER Port
    Override default server port (27584 for v3.5).
.PARAMETER Options
    Bitfield of UI options (see -Help for bits).  Default: 71 (dark gui +
    context menu + action bar + sound).
.PARAMETER Width
    Window width.
.PARAMETER Height
    Window height.
.PARAMETER Build
    Force a rebuild of the client even if the binary exists.
.PARAMETER ShowHelp
    Print the option-bit reference table and exit.
.EXAMPLE
    .\run-client.ps1 -User Ishtar -Password secret
    .\run-client.ps1 -User Ishtar -Password secret -Server 192.168.1.50
    .\run-client.ps1 -Build
#>
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Run')]  [string]$User,
    [Parameter(ParameterSetName = 'Run')]  [string]$Password,
    [Parameter(ParameterSetName = 'Run')]  [string]$Server = 'localhost',
    [Parameter(ParameterSetName = 'Run')]  [int]$Port,
    [Parameter(ParameterSetName = 'Run')]  [int]$Options = -1,
    [Parameter(ParameterSetName = 'Run')]  [int]$Width,
    [Parameter(ParameterSetName = 'Run')]  [int]$Height,
    [Parameter(ParameterSetName = 'Build')][switch]$Build,
    [Parameter(ParameterSetName = 'Help')] [switch]$ShowHelp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ClientDir  = Join-Path $PSScriptRoot 'astonia_community_client'
$BinDir     = Join-Path $ClientDir 'bin'
$MoacExe    = Join-Path $BinDir 'moac.exe'
$ConfigFile = Join-Path $PSScriptRoot '.client-config'

function Log  { param([string]$M) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $M" }
function Warn { param([string]$M) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WARNING: $M" -ForegroundColor Yellow }
function Err  { param([string]$M) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $M"   -ForegroundColor Red }

# ---------------------------------------------------------------------------
#  Option reference
# ---------------------------------------------------------------------------
$OptionTable = @'
  Bit  Value  Description
  ---  -----  -----------
   0       1  Dark GUI (by Tegra)
   1       2  Right-click context menu
   2       4  Action bar / Enter-to-chat keybindings
   3       8  Three inventory rows (smaller bottom window)
   4      16  Sliding top equipment bar
   5      32  Bigger health / mana bars
   6      64  Sound
   7     128  Large font
   8     256  True full-screen
   9     512  Legacy mouse-wheel logic
  10    1024  Faster inventory access
  11    2048  Reduced animation buffer (faster, more stutter)
  12    4096  Store settings in %APPDATA%
  13    8192  Load/save minimaps
  14   16384  Gamma +1
  15   32768  Gamma +2
  16   65536  Less-sensitive sliding top bar
  17  131072  Reduced lighting (better performance)
  18  262144  Disable minimap

  Default used by this script: 71  (dark gui + context menu + action bar + sound)
'@

if ($ShowHelp) { Write-Host $OptionTable; exit 0 }

# ---------------------------------------------------------------------------
#  Persistent config (simple key=value)
# ---------------------------------------------------------------------------
function Read-Config {
    $cfg = @{}
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile | ForEach-Object {
            if ($_ -match '^(\w+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
        }
    }
    return $cfg
}

function Save-Config {
    param([hashtable]$Cfg)
    $lines = $Cfg.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }
    Set-Content $ConfigFile ($lines -join "`n") -Encoding UTF8
}

# ---------------------------------------------------------------------------
#  Build client
# ---------------------------------------------------------------------------
function Find-Msys2 {
    if (Test-Path 'C:\msys64\usr\bin\bash.exe') { return 'C:\msys64' }

    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' `
                            -ErrorAction SilentlyContinue |
           Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like '*MSYS2*' }
    if ($reg -and $reg.InstallLocation) { return $reg.InstallLocation }
    return $null
}

# Path to MSYS2 Clang64 bin (for runtime DLLs: libpng, SDL3, etc.). Used when launching the game.
function Get-Msys2Clang64Bin {
    $msys2 = Find-Msys2
    if ($msys2) {
        $bin = Join-Path $msys2 'clang64\bin'
        if (Test-Path $bin) { return $bin }
    }
    if (Test-Path 'C:\msys64\clang64\bin') { return 'C:\msys64\clang64\bin' }
    return $null
}

function Test-Msys2ClientReady {
    param([string]$Msys2Root)
    $clang = Join-Path $Msys2Root 'clang64\bin\clang.exe'
    $sdl3 = Join-Path $Msys2Root 'clang64\lib\pkgconfig\sdl3.pc'
    return (Test-Path $clang) -and (Test-Path $sdl3)
}

function Install-Msys2ClientDeps {
    param([string]$Msys2Root)
    $clientUnix = '/' + $ClientDir.Substring(0, 1).ToLower() + ($ClientDir.Substring(2) -replace '\\', '/')
    $shellCmd = Join-Path $Msys2Root 'msys2_shell.cmd'
    if (-not (Test-Path $shellCmd)) {
        throw 'msys2_shell.cmd not found - cannot install dependencies automatically.'
    }
    $pkgs = 'git mingw-w64-clang-x86_64-pkg-config mingw-w64-clang-x86_64-clang mingw-w64-clang-x86_64-libpng mingw-w64-clang-x86_64-libzip mingw-w64-clang-x86_64-mimalloc mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja make zip mingw-w64-clang-x86_64-dwarfstack mingw-w64-clang-x86_64-zig mingw-w64-clang-x86_64-rustup'
    Log 'Installing MSYS2 Clang64 packages (first time may take several minutes) ...'
    & $shellCmd -clang64 -defterm -no-start -c "pacman -Sy --noconfirm -q && pacman -S --noconfirm -q $pkgs"
    if ($LASTEXITCODE -ne 0) { throw 'pacman install failed.' }
    Log 'Building SDL3 and SDL3_mixer ...'
    & $shellCmd -clang64 -defterm -no-start -c "cd '$clientUnix' && make build-sdl3 build-sdl3-mixer"
    if ($LASTEXITCODE -ne 0) { throw 'make build-sdl3 build-sdl3-mixer failed.' }
    Log 'Setting up Rust toolchain ...'
    & $shellCmd -clang64 -defterm -no-start -c "rustup toolchain install stable-x86_64-pc-windows-gnullvm && rustup default stable-x86_64-pc-windows-gnullvm"
    if ($LASTEXITCODE -ne 0) { throw 'rustup setup failed.' }
    Log 'Dependencies installed.'
}

function Invoke-ClientBuild {
    $msys2 = Find-Msys2
    if (-not $msys2) {
        Err 'MSYS2 is required to build the client but was not found.'
        Write-Host ''
        Write-Host '  Install MSYS2 from https://www.msys2.org/ then re-run this script.'
        exit 1
    }

    if (-not (Test-Msys2ClientReady $msys2)) {
        Log 'MSYS2 Clang64 toolchain or SDL3 not found - installing dependencies ...'
        Install-Msys2ClientDeps $msys2
    }

    $clientUnix = '/' + $ClientDir.Substring(0, 1).ToLower() + ($ClientDir.Substring(2) -replace '\\', '/')
    $shellCmd = Join-Path $msys2 'msys2_shell.cmd'
    if (Test-Path $shellCmd) {
        Log 'Ensuring Rust toolchain is set ...'
        & $shellCmd -clang64 -defterm -no-start -c "rustup toolchain install stable-x86_64-pc-windows-gnullvm 2>/dev/null; rustup default stable-x86_64-pc-windows-gnullvm"
        if ($LASTEXITCODE -ne 0) {
            throw 'Rust toolchain setup failed. In MSYS2 Clang64 run: rustup default stable-x86_64-pc-windows-gnullvm. If you see "not enough space on the disk", free space and re-run.'
        }
        Log "Building client via MSYS2 Clang64 ($msys2) ..."
        $makeCmd = "cd '$clientUnix' && make -j`$(nproc)"
        & $shellCmd -clang64 -defterm -no-start -c $makeCmd
    } else {
        $bash = Join-Path $msys2 'usr\bin\bash.exe'
        $clang64Bin = Join-Path $msys2 'clang64\bin'
        Log "Building client via MSYS2 ($msys2) ..."
        $env:MSYSTEM = 'CLANG64'
        $env:CHERE_INVOKING = '1'
        $env:PATH = "$clang64Bin;$env:PATH"
        & $bash -lc "cd '$clientUnix' && make -j`$(nproc)"
    }
    if ($LASTEXITCODE -ne 0) { throw "Client build failed (exit $LASTEXITCODE)." }
    Log 'Build complete.'
}

# ---------------------------------------------------------------------------
#  Launch
# ---------------------------------------------------------------------------
function Start-Client {
    # Load saved config, overlay with explicit params
    $cfg = Read-Config

    if (-not $User)     { $User     = $cfg['User'] }
    if (-not $Password) { $Password = $cfg['Password'] }
    if ($Server -eq 'localhost' -and $cfg['Server']) { $Server = $cfg['Server'] }
    if ($Options -eq -1) {
        if ($cfg['Options']) { $Options = [int]$cfg['Options'] } else { $Options = 71 }
    }

    # Prompt for missing required values
    if (-not $User) {
        $User = Read-Host 'Character name'
        if (-not $User) { throw 'Character name is required.' }
    }
    if (-not $Password) {
        $Password = Read-Host 'Password'
        if (-not $Password) { throw 'Password is required.' }
    }

    # Save for next time
    $cfg['User']     = $User
    $cfg['Password'] = $Password
    $cfg['Server']   = $Server
    $cfg['Options']  = "$Options"
    Save-Config $cfg

    # Ensure binary exists
    if (-not (Test-Path $MoacExe)) {
        Warn "Client binary not found at $MoacExe"
        Log  'Attempting to build ...'
        Invoke-ClientBuild
        if (-not (Test-Path $MoacExe)) { throw "Build succeeded but $MoacExe still missing." }
    }

    # Assemble arguments
    $moacArgs = @('-u', $User, '-p', $Password, '-d', $Server, '-v', '35', '-o', "$Options")
    if ($Port)   { $moacArgs += @('-t', "$Port") }
    if ($Width)  { $moacArgs += @('-w', "$Width") }
    if ($Height) { $moacArgs += @('-h', "$Height") }

    # Client needs: (1) working directory = client root so res/ is found, (2) PATH includes
    # MSYS2 Clang64 bin so libpng16-16.dll, SDL3, etc. are found.
    $clang64Bin = Get-Msys2Clang64Bin
    if ($clang64Bin) {
        $env:PATH = "$clang64Bin;$env:PATH"
    } else {
        Warn 'MSYS2 Clang64 bin not found; if the game fails with a missing-DLL error, install MSYS2 and build the client with this script first.'
    }

    Log "Launching: moac.exe $($moacArgs -join ' ')"
    $proc = Start-Process -FilePath $MoacExe -ArgumentList $moacArgs -WorkingDirectory $ClientDir -PassThru
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        Log "Client exited with code $($proc.ExitCode)."
        if ($proc.ExitCode -eq 105 -or $proc.ExitCode -eq -1) {
            Log 'Tip: Missing DLLs usually mean MSYS2 Clang64 bin is not on PATH; this script adds it when possible. Run from repo root: .\run-client.ps1'
        }
    }
}

# ---------------------------------------------------------------------------
#  Entry
# ---------------------------------------------------------------------------
try {
    switch ($PSCmdlet.ParameterSetName) {
        'Build' { Invoke-ClientBuild }
        'Help'  { Write-Host $OptionTable }
        default { Start-Client }
    }
} catch {
    Err "$_"
    exit 1
}
