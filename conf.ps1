[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfRepoDir = $PSScriptRoot
$SymlinkDirPairs = @(
    # FORMAT : [Windows directory],  [Dotfiles directory]

    # VSCode
    @("${Env:APPDATA}\Code\User", "$ConfRepoDir\data\profiles\default\.config\Code\User"),
    # PowerShell
    @("${Env:USERPROFILE}\Documents\PowerShell", "$ConfRepoDir\win\config\PowerShell"),
    # NeoVim
    @("${Env:USERPROFILE}\.config\nvim", "$ConfRepoDir\data\profiles\default\.config\nvim")

    # CAUTION: Do NOT forget to add a "comma (,)" for each array.
)

function Set-XdgEnvVars {
    [Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", "$env:USERPROFILE\.config", "User")
    [Environment]::SetEnvironmentVariable("XDG_DATA_HOME", "$env:USERPROFILE\.local\share", "User")
    [Environment]::SetEnvironmentVariable("XDG_CACHE_HOME", "$env:USERPROFILE\.cache", "User")
    [Environment]::SetEnvironmentVariable("XDG_STATE_HOME", "$env:USERPROFILE\.local\state", "User")
}


function Set-Symlink([string] $WinDir, [string] $RepoDir) {
    if (-not (Test-Path -Path $WinDir)) {
        New-Item -Path $winDir -ItemType Directory
    }

    Get-ChildItem -Path $RepoDir | ForEach-Object {
        $winItem = Join-Path -Path $WinDir -ChildPath $_.Name
        $repoItem = $_.FullName

        if (Test-Path -Path $_.FullName -PathType Leaf) {
            New-Item -ItemType SymbolicLink -Path $winItem -Target $repoItem -Force | Out-Null
        }
        elseif (Test-Path -Path $_.FullName -PathType Container) {
            Set-Symlink -WinDir $winItem -RepoDir $repoItem
        }
    }
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    return $isAdmin
}

function main() {
    if (-not (Test-Administrator)) {
        Write-Output "Not running as Administrator. Restarting..."
        $scriptPath = $PSCommandPath
        Start-Process  -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        exit 0
    }

    # Set-XdgEnvVars

    foreach ($dirPair in $SymlinkDirPairs) {
        $winDir, $repoDir = $dirPair

        if (-not (Test-Path -Path $repoDir)) {
            Write-Warning ""
        }

        Set-Symlink -WinDir $winDir -RepoDir $repoDir
    }
}

main
