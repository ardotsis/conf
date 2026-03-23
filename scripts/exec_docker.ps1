[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Os,
    [Parameter(Mandatory = $true)]
    [string] $Username,
    [Parameter(Mandatory = $false)]
    [string] $Exec = "",
    [Parameter(Mandatory = $false)]
    [string] $WorkDir
)

if (-not $WorkDir) {
    if ($Username -eq "root") {
        $WorkDir = "/root"
    }
    else {
        $WorkDir = "/home/$Username"
    }
}

$Docker = "docker.exe"
$env:DOCKER_CLI_HINTS = "false"
$ImageName = "conf-${Os}"
$ContainerName = "${ImageName}-container"

if ( ( $Exec -eq "" ) -or ($Exec -eq "zsh")  ) {
    $FinalExec = @("zsh", "--login")
}
else {
    $FinalExec = @($Exec)
}

& $Docker exec `
    --interactive `
    --tty `
    --workdir "$WorkDir" `
    --user "$Username" `
    "$ContainerName" `
    $FinalExec `
