[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Os,
    [switch] $Build,
    [switch] $Cache,
    [switch] $Test,
    [array] $Params,
    [switch] $CleanStart
)

# Paths
$RepoDir = Split-Path -Path $PSScriptRoot -Parent
$DockerDir = "${RepoDir}\docker"

# Docker system
$env:DOCKER_CLI_HINTS = "false" # Disable unnecessary docker message
$Docker = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
$ImageName = "conf-${Os}"
$ImageTag = "latest"
$ContainerName = "${ImageName}-container"
$Dockerfile = "${DockerDir}\${Os}.Dockerfile"

$GuestAppDir = "/app"
$GuestDevAppDir = "/app-live"
$GuestDockerDir = $DockerDir.Replace("$RepoDir", "$GuestAppDir").Replace("\", "/")


if ($CleanStart) {
    Clear-Host
}

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
    if (-not (& $Docker ps)) {
        Write-Verbose "Launching Docker engine..."
        Start-Process -FilePath "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        while (-not (& $Docker ps)) {
            Start-Sleep -Seconds 2
        }
    }

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
            -ids (Get-ObjectIds -type "cont" -filter "ancestor=$ImageName") | Out-Null

        Write-Verbose "Delete none images"
        Remove-Objects `
            -type "img" `
            -ids (Get-ObjectIds -type "img" -filter "dangling=true") | Out-Null


        Write-Verbose "Delete old images"
        Remove-Objects `
            -type "img" `
            -ids (Get-ObjectIds -type "img" -filter "reference=$ImageName") | Out-Null

        $buildArgs = [System.Collections.Generic.List[string]]::new([string[]]@(
                "build",
                "--file", "$Dockerfile",
                "--tag", "${ImageName}:${ImageTag}",
                "--build-arg", "GUEST_APP_DIR=$GuestAppDir",
                "--build-arg", "GUEST_DOCKER_DIR=$GuestDockerDir",
                "$RepoDir"
            ))

        if (-not $Cache) {
            $buildArgs.Insert(1, "--no-cache")
        }

        & $Docker $buildArgs
    }
    else {
        Write-Verbose "Delete old containers"
        Remove-Objects `
            -type "cont" `
            -ids (Get-ObjectIds -type "cont" -filter "ancestor=$ImageName") | Out-Null
    }

    Write-Verbose "Running..."
    if ($Build) {
        Write-Output "--------- Docker Session ---------"
    }

    $isTest = $Test.ToString().ToLower()

    $runArgs = @(
        "run",
        "--rm",
        "--interactive",
        "--tty",
        "--hostname=$Os",
        "--mount", "type=bind,source=$RepoDir,target=$GuestDevAppDir,readonly",
        "--env", "DOCKER=true",
        "--env", "DOCKER_CONF_PARAMS=$Params",
        "--env", "DOCKER_IS_TEST=$isTest",
        "--env", "DOCKER_APP_DIR=$GuestAppDir",
        "--env", "DOCKER_DEV_APP_DIR=$GuestDevAppDir",
        "--name", $ContainerName,
        $ImageName
    )

    & $Docker @runArgs
}

main
