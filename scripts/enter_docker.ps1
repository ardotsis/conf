[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Os,
    [Parameter(Mandatory = $true)]
    [array] $Username
)

$Docker = "docker.exe"
$env:DOCKER_CLI_HINTS = "false"
$ImageName = "conf-${Os}"
$ContainerName = "${ImageName}-cont"

& $Docker exec `
    --interactive `
    --tty `
    --workdir "/home/$Username" `
    --user "$Username" `
    "$ContainerName" zsh `
    --login
