[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Aliases
Set-Alias -Name nv -Value nvim -Force


# =============================== Old config ===============================

function yt-all {
    param ([string] $url)
    yt-dlp.exe --yes-playlist --output '.\%(upload_date)s %(title)s [%(id)s]' --format 'bestvideo+bestaudio' --write-thumbnail $url --cookies-from-browser firefox
}

function yt-wav {
    param ([string] $url)
    yt-dlp.exe --output '.\%(title)s' -x --audio-format wav $url
}


$ItemMaps = @(
    @('Screenshot *.png', 'E:\Downloads\.Images\Screenshots'),
    @('^IMG_\d+\.png$', '.\Maybe-iPhone'),
    @('^.{15}\.(jpg|png)$', '.\Maybe-Twitter'),
    @('^.\.txt$', '.\Maybe-YouTube'),
    @('^.\.txt$', '.\Text-Files')
)


function Invoke-OrganizeFolder {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Path = '.'
    )

    foreach ($item in $ItemMaps) {
        Get-ChildItem -Path $Path | Where-Object { $_.Name -match $item[0] } | ForEach-Object {
            $_.Name
        }
    }
}
