[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Os,
    [Parameter(Mandatory = $true)]
    [string] $Username,
    [Parameter(Mandatory = $false)]
    [string] $WorkDir = "/home/$Username"
)

$Docker = "docker.exe"
$env:DOCKER_CLI_HINTS = "false"
$ImageName = "conf-${Os}"
$ContainerName = "${ImageName}-cont"

& $Docker exec `
    --interactive `
    --tty `
    --workdir "$WorkDir" `
    --user "$Username" `
    "$ContainerName" zsh `
    --login
