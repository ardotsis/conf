# General
##################################
#            General             #
##################################
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

###################################
#             Alias              #
################################## Aliases
Set-Alias -Name nv -Value nvim -Force

##################################
#            Utility             #
##################################
function poi {
    Clear-RecycleBin -Confirm:$false
}

function Get-TextBox {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [Parameter(Mandatory = $false)]
        [int]$Width = 34
    )

    $S = "#"
    $Inner = $Width - 2
    $Space = $Inner - $Text.Length

    if ($Space -lt 0) {
        Write-Warning "Width is too small for the provided text."
        return
    }

    $Left = [Math]::Floor($Space / 2)
    $Right = $Space - $Left

    $Result = @(
        ($S * $Width)
        ($S + (" " * $Left) + $Text + (" " * $Right) + $S)
        ($S * $Width)
    )

    Write-Output $Result
    Write-Output $Result | Set-Clipboard
}

function yt-all {
    param ([string] $url)
    yt-dlp.exe --yes-playlist --output '.\%(upload_date)s %(title)s [%(id)s]' --format 'bestvideo+bestaudio' --write-thumbnail $url --cookies-from-browser firefox
}

function yt-wav {
    param ([string] $url)
    yt-dlp.exe --output '.\%(title)s' -x --audio-format wav $url
}
