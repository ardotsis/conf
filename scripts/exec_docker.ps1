[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Os,
    [Parameter(Mandatory = $true)]
    [string] $Username,
    [Parameter(Mandatory = $true)]
    [string] $Exec,
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
$ContainerName = "${ImageName}-cont"

& $Docker exec `
    --interactive `
    --tty `
    --workdir "$WorkDir" `
    --user "$Username" `
    "$ContainerName" "$Exec" `
