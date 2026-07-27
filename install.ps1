#Requires -Version 5.1
<#
.SYNOPSIS
    Installs git-sync-all on Windows.

.DESCRIPTION
    Windows counterpart to the Makefile. Copies git-sync-all into a prefix
    directory, generates a .cmd shim so the tool works from PowerShell and
    cmd.exe, and adds the bin directory to the user PATH.

    git-sync-all is a Bash program: Git for Windows (Git Bash) must be
    installed. This script locates its bash.exe and wires everything up.

.PARAMETER Prefix
    Installation directory. Default: %LOCALAPPDATA%\Programs\git-sync-all
    Creates <Prefix>\bin, <Prefix>\lib and <Prefix>\config.

.PARAMETER Link
    Do not copy anything. Generate forwarders that call the script in this
    repository, so 'git pull' updates the installation. Equivalent to
    'make link' on POSIX systems.

.PARAMETER Uninstall
    Remove a previous installation from <Prefix>.

.PARAMETER NoPathUpdate
    Do not modify the user PATH.

.EXAMPLE
    .\install.ps1
    Installs to %LOCALAPPDATA%\Programs\git-sync-all and updates PATH.

.EXAMPLE
    .\install.ps1 -Link
    Installs forwarders pointing at this repository (auto-updates on git pull).

.EXAMPLE
    .\install.ps1 -Uninstall
    Removes the installation.

.LINK
    https://github.com/markus-michalski/git-sync-all
#>
[CmdletBinding()]
param(
    [string]$Prefix = "$env:LOCALAPPDATA\Programs\git-sync-all",
    [switch]$Link,
    [switch]$Uninstall,
    [switch]$NoPathUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$LibNames = @('core', 'config', 'cli', 'repo-discovery', 'git-ops', 'sync', 'inventory', 'issues')
$ConfigExamples = @('config.conf.example', 'repos.yml.example')

# ── Output helpers ───────────────────────────────────────────────────────────

function Write-Info { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Write-Ok { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-WarnMsg { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }

function Stop-WithError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

# ── Environment detection ────────────────────────────────────────────────────

# Locate the bash.exe that ships with Git for Windows.
# WSL's System32\bash.exe is deliberately excluded: it cannot see Windows paths
# the same way and would break the installed shim.
function Find-Bash {
    $candidates = New-Object System.Collections.Generic.List[string]

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        # Git for Windows layout: <root>\cmd\git.exe next to <root>\bin\bash.exe
        $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
        $candidates.Add((Join-Path $gitRoot 'bin\bash.exe'))
    }

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs")) {
        if ($base) { $candidates.Add((Join-Path $base 'Git\bin\bash.exe')) }
    }

    $onPath = Get-Command bash.exe -All -ErrorAction SilentlyContinue
    if ($onPath) {
        foreach ($cmd in $onPath) {
            if ($cmd.Source -notmatch '\\System32\\') { $candidates.Add($cmd.Source) }
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

# Convert a Windows path to its MSYS equivalent (C:\foo -> /c/foo).
function ConvertTo-MsysPath {
    param(
        [Parameter(Mandatory)][string]$Bash,
        [Parameter(Mandatory)][string]$Path
    )

    $converted = & $Bash -c "cygpath -u '$($Path -replace "'", "'\''")'" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($converted)) {
        Stop-WithError "Failed to convert path to MSYS format: $Path"
    }
    return $converted.Trim()
}

function Test-Prerequisites {
    $bash = Find-Bash
    if (-not $bash) {
        Stop-WithError @"
Git Bash not found. git-sync-all is a Bash program and needs Git for Windows.

Install it from https://git-scm.com/download/win and run this script again.
"@
    }

    $majorVersion = (& $bash -c 'echo ${BASH_VERSINFO[0]}' 2>$null)
    if ([string]::IsNullOrWhiteSpace($majorVersion) -or [int]$majorVersion -lt 4) {
        Stop-WithError "Bash 4.0+ required, found version '$majorVersion' at $bash"
    }

    Write-Info "Using bash: $bash (version $majorVersion.x)"
    return $bash
}

# ── File operations ──────────────────────────────────────────────────────────

# Copy a shell script, normalising CRLF to LF and writing UTF-8 without BOM.
# Both matter: bash chokes on a BOM before the shebang, and a checkout with
# core.autocrlf=true would otherwise install scripts with CR line endings.
function Copy-ScriptFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Stop-WithError "Source file missing: $Source"
    }

    $text = [System.IO.File]::ReadAllText($Source)
    $text = $text -replace "`r`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Destination, $text, $utf8NoBom)
}

function New-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Generate the cmd.exe shim that makes 'git-sync-all' callable from
# PowerShell and cmd.exe. Forward slashes keep bash happy with the path.
function New-CmdShim {
    param(
        [Parameter(Mandatory)][string]$ShimPath,
        [Parameter(Mandatory)][string]$Bash,
        [Parameter(Mandatory)][string]$TargetScript
    )

    $target = $TargetScript -replace '\\', '/'
    $content = @"
@echo off
REM Generated by install.ps1 - do not edit; re-run the installer instead.
setlocal
set "GSA_BASH=$Bash"
if not exist "%GSA_BASH%" set "GSA_BASH=bash.exe"
"%GSA_BASH%" "$target" %*
exit /b %ERRORLEVEL%
"@

    # cmd.exe is unreliable with LF-only batch files, so force CRLF regardless
    # of how this installer script itself was checked out.
    $crlf = ($content -replace "`r`n", "`n") -replace "`n", "`r`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ShimPath, $crlf, $utf8NoBom)
}

# Generate the Git Bash entry point. In copy mode this is the real script;
# in link mode it is a one-line forwarder into the repository.
function New-BashForwarder {
    param(
        [Parameter(Mandatory)][string]$ForwarderPath,
        [Parameter(Mandatory)][string]$TargetMsysPath
    )

    $content = @"
#!/usr/bin/env bash
# Generated by install.ps1 (link mode) - forwards to the git-sync-all checkout.
# Updates to that checkout take effect immediately.
exec "$TargetMsysPath" "`$@"
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ForwarderPath, ($content -replace "`r`n", "`n"), $utf8NoBom)
}

# ── PATH handling ────────────────────────────────────────────────────────────

function Get-UserPathEntries {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrEmpty($userPath)) { return @() }
    return @($userPath -split ';' | Where-Object { $_ -ne '' })
}

function Test-PathEntry {
    param([Parameter(Mandatory)][string]$Directory)
    $normalized = $Directory.TrimEnd('\', '/')
    foreach ($entry in Get-UserPathEntries) {
        if ($entry.TrimEnd('\', '/') -ieq $normalized) { return $true }
    }
    return $false
}

function Add-ToUserPath {
    param([Parameter(Mandatory)][string]$Directory)

    if (Test-PathEntry -Directory $Directory) {
        Write-Info "PATH already contains $Directory"
        return
    }

    $entries = @(Get-UserPathEntries) + $Directory
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
    Write-Ok "Added to user PATH: $Directory"
    Write-WarnMsg "Open a new terminal for the PATH change to take effect."
}

function Remove-FromUserPath {
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-PathEntry -Directory $Directory)) { return }

    $normalized = $Directory.TrimEnd('\', '/')
    $entries = @(Get-UserPathEntries | Where-Object { $_.TrimEnd('\', '/') -ine $normalized })
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
    Write-Ok "Removed from user PATH: $Directory"
}

# ── Uninstall ────────────────────────────────────────────────────────────────

# Removes only files this installer creates, so a shared prefix such as
# %LOCALAPPDATA%\Programs stays intact.
function Invoke-Uninstall {
    param([Parameter(Mandatory)][string]$Prefix)

    $binDir = Join-Path $Prefix 'bin'
    $libDir = Join-Path $Prefix 'lib'
    $configDir = Join-Path $Prefix 'config'

    $files = @(
        (Join-Path $binDir 'git-sync-all'),
        (Join-Path $binDir 'git-sync-all.cmd')
    )
    foreach ($name in $LibNames) { $files += (Join-Path $libDir "$name.sh") }
    foreach ($name in $ConfigExamples) { $files += (Join-Path $configDir $name) }

    $removed = 0
    foreach ($file in $files) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
            $removed++
        }
    }

    # Drop directories only when they are empty - never delete foreign content.
    foreach ($dir in @($libDir, $configDir, $binDir, $Prefix)) {
        if ((Test-Path -LiteralPath $dir -PathType Container) -and
            -not (Get-ChildItem -LiteralPath $dir -Force)) {
            Remove-Item -LiteralPath $dir -Force
        }
    }

    if (-not $NoPathUpdate) { Remove-FromUserPath -Directory $binDir }

    if ($removed -eq 0) {
        Write-WarnMsg "No git-sync-all installation found in $Prefix"
    } else {
        Write-Ok "Uninstalled git-sync-all from $Prefix ($removed files removed)"
    }
}

# ── Install ──────────────────────────────────────────────────────────────────

function Invoke-Install {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Bash
    )

    $binDir = Join-Path $Prefix 'bin'
    $sourceScript = Join-Path $RepoRoot 'bin\git-sync-all'

    if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
        Stop-WithError "Not a git-sync-all checkout: $sourceScript not found"
    }

    New-Directory -Path $binDir

    $installedScript = Join-Path $binDir 'git-sync-all'

    if ($Link) {
        # Windows symlinks need elevation or Developer Mode, so a forwarder
        # script gives the same "updates on git pull" behaviour without either.
        $targetMsys = ConvertTo-MsysPath -Bash $Bash -Path $sourceScript
        New-BashForwarder -ForwarderPath $installedScript -TargetMsysPath $targetMsys
        New-CmdShim -ShimPath (Join-Path $binDir 'git-sync-all.cmd') -Bash $Bash -TargetScript $sourceScript
        Write-Ok "Linked git-sync-all -> $sourceScript"
    } else {
        $libDir = Join-Path $Prefix 'lib'
        $configDir = Join-Path $Prefix 'config'
        New-Directory -Path $libDir
        New-Directory -Path $configDir

        Copy-ScriptFile -Source $sourceScript -Destination $installedScript

        foreach ($name in $LibNames) {
            Copy-ScriptFile -Source (Join-Path $RepoRoot "lib\$name.sh") `
                -Destination (Join-Path $libDir "$name.sh")
        }

        # bin/ and lib/ stay siblings, so the script resolves GSA_LIB_DIR on
        # its own - no path patching needed, unlike the Makefile install.
        foreach ($name in $ConfigExamples) {
            $source = Join-Path $RepoRoot "config\$name"
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                Copy-ScriptFile -Source $source -Destination (Join-Path $configDir $name)
            }
        }

        New-CmdShim -ShimPath (Join-Path $binDir 'git-sync-all.cmd') -Bash $Bash -TargetScript $installedScript
        Write-Ok "Installed git-sync-all to $Prefix"
    }

    if (-not $NoPathUpdate) { Add-ToUserPath -Directory $binDir }

    Write-Host ""
    Write-Info "Run 'git-sync-all --help' to get started."
    Write-Info "Create a config with 'git-sync-all --init-config'."
}

# ── Main ─────────────────────────────────────────────────────────────────────

function Invoke-Main {
    # Resolve to an absolute path without requiring the directory to exist yet.
    $resolvedPrefix = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine((Get-Location).Path, $Prefix))

    if ($Uninstall) {
        Invoke-Uninstall -Prefix $resolvedPrefix
        return
    }

    $bash = Test-Prerequisites
    Invoke-Install -Prefix $resolvedPrefix -Bash $bash
}

Invoke-Main
