[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Os,
    [switch] $Build = $false,
    [switch] $Cache = $false,
    [array] $Params
)

$Docker = "docker.exe"
$env:DOCKER_CLI_HINTS = "false"
$RepoDir = Split-Path -Path $PSScriptRoot
$DockerfilesDir = "${RepoDir}\tests\dockerfiles"
$Dockerfile = "${DockerfilesDir}\$Os"
$ImageName = "conf-${Os}"
$ImageTag = "latest"
$ContainerName = "${ImageName}-cont"
$GuestVolumeDir = "/app"


function Remove-Objects {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $type,
        [Parameter(Mandatory = $false)] # To allow empty/null array
        [array] $ids
    )

    if ($ids.Length -gt 0) {
        switch ($type) {
            "img" { $rm = "rmi" }
            "cont" { $rm = "rm" }
        }

        & $Docker $rm -f $ids | ForEach-Object {
            Write-Verbose "$_"
        }
    }

    return $true
}


function Get-ObjectIds {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $type,
        [Parameter(Mandatory = $true)]
        [string] $filter
    )

    switch ($type) {
        "img" { $cmd = "images" }
        "cont" { $cmd = "ps" }
    }

    return @(& $Docker $cmd --all --format "{{.ID}}" --filter "$filter")
}

function main() {
    if (-not (Test-Path -Path $Dockerfile)) {
        throw "Unknown OS or Dockerfile does't exit. ($Dockerfile)"
    }

    $imgId = Get-ObjectIds -type "img" -filter "reference=$ImageName"
    if ($imgId.Count -eq 0) {
        Write-Verbose "No image. Building"
        $Build = $true
    }

    if ($Build) {
        Write-Verbose "Delete old containers"
        Remove-Objects `
            -type "cont" `
            -ids (Get-ObjectIds -type "cont" -filter "ancestor=$ContainerName") | Out-Null

        Write-Verbose "Delete none images"
        Remove-Objects `
            -type "img" `
            -ids (Get-ObjectIds -type "img" -filter "dangling=true") | Out-Null


        Write-Verbose "Delete old images"
        Remove-Objects `
            -type "img" `
            -ids (Get-ObjectIds -type "img" -filter "reference=$ImageName") | Out-Null

        if ($Cache) {
            & $Docker build --file "$Dockerfile" --tag "${ImageName}:${ImageTag}" "$RepoDir"
        }
        else {
            & $Docker build --no-cache --file "$Dockerfile" --tag "${ImageName}:${ImageTag}" "$RepoDir"
        }
    }

    if ($Build) {
        Write-Output "--------- Docker Session ---------"
    }

    $runArgs = @(
        "--rm",
        "--interactive",
        "--tty",
        "--hostname=somehost",
        "--mount", "type=bind,source=$RepoDir,target=$GuestVolumeDir",
        "--env", "INSTALL_SCRIPT_PARAMS=$Params",
        "--env", "DOTFILES_VOLUME_DIR=$GuestVolumeDir",
        "--name", $ContainerName,
        $ImageName
    )

    & $Docker run @runArgs
}

main
