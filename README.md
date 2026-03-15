# Astonia 3.5 — Quick Start

Two PowerShell scripts to run the server and client locally on Windows.
Each has a `.bat` wrapper that handles execution policy automatically.

Use `run-server.bat` / `run-client.bat` from **cmd** or any terminal, or
`.\run-server.ps1` / `.\run-client.ps1` directly from **PowerShell**.

## Prerequisites

| Component       | Needed for | Auto-installed? |
|-----------------|------------|-----------------|
| Docker Desktop  | Server     | Yes (via winget) |
| MSYS2 + Clang64 | Client build | No — see below |

> If you already have a pre-built `moac.exe` in `astonia_community_client\bin\`, you can skip MSYS2 entirely.

## Server

```powershell
.\run-server.ps1                    # start MariaDB + game server (pulls Docker images on first run)
.\run-server.ps1 -Status            # show container health
.\run-server.ps1 -Logs              # tail live output (Ctrl+C to stop)
.\run-server.ps1 -Stop              # graceful shutdown
.\run-server.ps1 -Restart           # restart everything
```

The server runs inside Docker containers with `restart: unless-stopped` — processes that crash are restarted automatically. The entrypoint also monitors `chatserver` and all 30 area `server35` instances.

### Create an account and character

```powershell
.\run-server.ps1 -CreateAccount -Email you@mail.com -Password secret
# note the account ID printed (usually 1 for the first account)

.\run-server.ps1 -CreateCharacter -AccountId 1 -Name Ishtar -Class MWG
```

Classes: `MWG` (Mage Warrior God) and others defined by the server.

### Ports

| Port range    | Purpose            |
|---------------|--------------------|
| 27584 – 27620 | Game area servers  |
| 8080 – 8090   | Game area servers  |
| 5554          | Chat server (internal, not exposed) |
| 3306          | MariaDB (internal, not exposed)     |

## Client

```powershell
# permission:
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\run-client.ps1 -User Ishtar -Password secret                   # connect to localhost
.\run-client.ps1 -User Ishtar -Password secret -Server 1.2.3.4   # connect to a remote server
.\run-client.ps1                                                   # reuse saved credentials
.\run-client.ps1 -ShowHelp                                         # print UI option bits
```

On first run the script prompts for character name and password if not provided. Credentials are saved to `.client-config` for subsequent launches.

**Manual run:** The client must run with its **working directory** set to `astonia_community_client` (the folder that contains `bin` and `res`). From the repo root: `cd astonia_community_client` then `.\bin\moac.exe -u Name -p pass -d localhost -v 35 -o 71`. Do not run from inside `bin` or the game will exit without a window.

### Optional parameters

| Flag       | Description                              | Default   |
|------------|------------------------------------------|-----------|
| `-Server`  | Hostname or IP                           | localhost |
| `-Port`    | Override default port                    | 27584     |
| `-Options` | UI option bitfield (see `-ShowHelp`)     | 71        |
| `-Width`   | Window width                             | auto      |
| `-Height`  | Window height                            | auto      |

Default options value `71` enables: dark GUI (1) + context menu (2) + action bar (4) + sound (64).

### Building the client from source

If `bin\moac.exe` doesn't exist the script tries to build it automatically via MSYS2. If MSYS2 isn't installed, it prints setup instructions. You can also trigger a build manually:

```powershell
.\run-client.ps1 -Build
```

MSYS2 one-time setup (in the **Clang64** shell):

```bash
pacman -Syu
pacman -Sy mingw-w64-clang-x86_64-clang mingw-w64-clang-x86_64-libpng \
  mingw-w64-clang-x86_64-libzip mingw-w64-clang-x86_64-mimalloc \
  mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja make zip \
  mingw-w64-clang-x86_64-dwarfstack mingw-w64-clang-x86_64-zig \
  mingw-w64-clang-x86_64-rustup
make build-sdl3 build-sdl3-mixer
rustup toolchain install stable-x86_64-pc-windows-gnullvm
rustup default stable-x86_64-pc-windows-gnullvm
```

## Typical first-time workflow

```powershell
# 1. Start the server (installs Docker Desktop if needed, pulls images, inits DB)
.\run-server.ps1

# 2. Create your account and character
.\run-server.ps1 -CreateAccount -Email me@mail.com -Password hunter2
.\run-server.ps1 -CreateCharacter -AccountId 1 -Name Ishtar -Class MWG

# 3. Launch the client
.\run-client.ps1 -User Ishtar -Password hunter2
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "running scripts is disabled" | Use the `.bat` wrappers instead (`run-server.bat`, `run-client.bat`), or run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once in PowerShell. |
| "Docker CLI not found" | Open Docker Desktop, wait for it to start, re-run the script. |
| "Timed out waiting for Docker daemon" | Start Docker Desktop manually, then re-run. |
| Client build fails | Make sure you're using the MSYS2 Clang64 shell for the one-time setup. |
| Can't connect to server | Check `.\run-server.ps1 -Status` — all containers should be running. |
| "create_account failed" | The server container must be running. Start it first. |
