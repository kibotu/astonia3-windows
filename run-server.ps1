#Requires -Version 5.1
<#
.SYNOPSIS
    Astonia 3.5 Community Server - set up, start, and manage.
.DESCRIPTION
    Uses Docker Compose to run MariaDB + the game server. Handles first-time
    Docker installation, container lifecycle, account/character creation, and
    graceful shutdown. Containers auto-restart on crash via Docker policy.
.PARAMETER Stop
    Gracefully stop all Astonia containers.
.PARAMETER Restart
    Restart all containers.
.PARAMETER Logs
    Tail live container logs (Ctrl+C to stop tailing).
.PARAMETER Status
    Show container health and port mappings.
.PARAMETER CreateAccount
    Create a game account.  Requires -Email and -Password.
.PARAMETER CreateCharacter
    Create a character.  Requires -AccountId, -Name, and -Class (e.g. MWG).
.EXAMPLE
    .\run-server.ps1                        # start everything
    .\run-server.ps1 -Stop                  # shut down
    .\run-server.ps1 -CreateAccount -Email me@mail.com -Password s3cret
    .\run-server.ps1 -CreateCharacter -AccountId 1 -Name Ishtar -Class MWG
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Stop')]                  [switch]$Stop,
    [Parameter(ParameterSetName = 'Restart')]                [switch]$Restart,
    [Parameter(ParameterSetName = 'Logs')]                   [switch]$Logs,
    [Parameter(ParameterSetName = 'Status')]                 [switch]$Status,
    [Parameter(ParameterSetName = 'Account', Mandatory)]     [switch]$CreateAccount,
    [Parameter(ParameterSetName = 'Account', Mandatory)]     [string]$Email,
    [Parameter(ParameterSetName = 'Account', Mandatory)]     [string]$Password,
    [Parameter(ParameterSetName = 'Character', Mandatory)]   [switch]$CreateCharacter,
    [Parameter(ParameterSetName = 'Character', Mandatory)]   [int]$AccountId,
    [Parameter(ParameterSetName = 'Character', Mandatory)]   [string]$Name,
    [Parameter(ParameterSetName = 'Character', Mandatory)]   [string]$Class
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ServerDir   = Join-Path $PSScriptRoot 'astonia_community_server35'
$DockerDir   = Join-Path $ServerDir    'docker'
$ComposeFile = Join-Path $DockerDir    'docker-compose.yml'

function Log  { param([string]$M) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $M" }
function Warn { param([string]$M) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WARNING: $M" -ForegroundColor Yellow }
function Err  { param([string]$M) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $M"   -ForegroundColor Red }

# ---------------------------------------------------------------------------
#  Docker pre-flight
# ---------------------------------------------------------------------------
function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Log 'Docker CLI not found on PATH.'

        $installed = Get-ItemProperty `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like '*Docker Desktop*' }

        if (-not $installed) {
            Log 'Installing Docker Desktop via winget ...'
            & winget install -e --id Docker.DockerDesktop `
                --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw 'winget install failed - install Docker Desktop manually.' }
            Write-Warning 'Docker Desktop was just installed. Please restart your terminal and re-run this script.'
            exit 0
        }
        Write-Warning 'Docker Desktop is installed but docker is not on PATH. Open Docker Desktop, then re-run.'
        exit 1
    }

    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Log 'Docker daemon not running - starting Docker Desktop ...'
        Start-Process 'Docker Desktop' -ErrorAction SilentlyContinue
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep 3
            docker info 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Log 'Docker daemon is ready.'; return }
        }
        throw 'Timed out waiting for Docker daemon. Start Docker Desktop manually.'
    }
}

# ---------------------------------------------------------------------------
#  Compose wrapper
# ---------------------------------------------------------------------------
function Invoke-Compose {
    $all = @('compose', '-f', $ComposeFile) + $args
    Log "  > docker $($all -join ' ')"
    & docker $all
    if ($LASTEXITCODE -ne 0) { throw "docker compose exited with code $LASTEXITCODE" }
}

function Wait-DbHealthy {
    param([int]$TimeoutSec = 90)
    Log 'Waiting for MariaDB to be healthy ...'
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $h = docker inspect --format '{{.State.Health.Status}}' 'astonia-db' 2>$null
        if ($h -eq 'healthy') { Log 'MariaDB is healthy.'; return }
        Start-Sleep 2
    }
    Warn "MariaDB did not report healthy within ${TimeoutSec}s - continuing."
}

# ---------------------------------------------------------------------------
#  First-time init
# ---------------------------------------------------------------------------
function Initialize-Once {
    $motd = Join-Path $ServerDir 'motd.txt'
    if (-not (Test-Path $motd)) {
        Set-Content $motd 'Welcome to Astonia Community Server' -Encoding UTF8
        Log 'Created motd.txt'
    }
    $logsDir = Join-Path $DockerDir 'logs'
    if (-not (Test-Path $logsDir)) {
        New-Item $logsDir -ItemType Directory -Force | Out-Null
    }
}

# ---------------------------------------------------------------------------
#  Actions
# ---------------------------------------------------------------------------
function Start-Server {
    Initialize-Once

    Log 'Starting Astonia server (Docker Compose) ...'
    Log '  First run pulls images - this may take a few minutes.'
    Invoke-Compose up -d --pull always
    Wait-DbHealthy

    Write-Host ''
    Log '=== Astonia server is running ==='
    Write-Host ''
    Write-Host '  Game ports : 27584-27620 and 8080-8090 (TCP)'
    Write-Host '  Connect    : .\run-client.ps1 -Server localhost'
    Write-Host ''
    Write-Host '  Manage:'
    Write-Host '    .\run-server.ps1 -Status       # container health'
    Write-Host '    .\run-server.ps1 -Logs          # live log tail'
    Write-Host '    .\run-server.ps1 -Stop          # shut down'
    Write-Host '    .\run-server.ps1 -Restart       # restart'
    Write-Host ''
    Write-Host '  Accounts:'
    Write-Host '    .\run-server.ps1 -CreateAccount -Email you@mail.com -Password pw'
    Write-Host '    .\run-server.ps1 -CreateCharacter -AccountId 1 -Name Ishtar -Class MWG'
    Write-Host ''

    Invoke-Compose ps
}

function Stop-Server {
    Log 'Stopping Astonia server ...'
    Invoke-Compose down
    Log 'All containers stopped.'
}

function Restart-Server { Stop-Server; Start-Server }

function Show-Logs   { Invoke-Compose logs -f --tail 200 }
function Show-Status { Invoke-Compose ps }

function New-Account {
    Log "Creating account for '$Email' ..."
    & docker exec astonia-server ./create_account -e "$Email" "$Password"
    if ($LASTEXITCODE -ne 0) { throw 'create_account failed inside the container.' }
    Log 'Account created. Note the account ID printed above - you need it for -CreateCharacter.'
}

function New-Character {
    Log "Creating character '$Name' (class=$Class) on account $AccountId ..."
    & docker exec astonia-server ./create_character -e "$AccountId" "$Name" "$Class"
    if ($LASTEXITCODE -ne 0) { throw 'create_character failed inside the container.' }
    Log "Character '$Name' created. You can now connect with run-client.ps1."
}

# ---------------------------------------------------------------------------
#  Entry
# ---------------------------------------------------------------------------
try {
    Assert-Docker
    switch ($PSCmdlet.ParameterSetName) {
        'Start'     { Start-Server    }
        'Stop'      { Stop-Server     }
        'Restart'   { Restart-Server  }
        'Logs'      { Show-Logs       }
        'Status'    { Show-Status     }
        'Account'   { New-Account     }
        'Character' { New-Character   }
    }
} catch {
    Err "$_"
    exit 1
}
