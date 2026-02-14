$Hostname = $args[0]
$Passphrase = $args[1]

if ((-not $Hostname) -or (-not $Passphrase) ) {
    Write-Host "Usage: .\Create-SSHKeyPair.ps1 <Hostname> <Passphrase>"
    exit 1
}

ssh-keygen.exe -t ed25519 -b 4096 -f "$env:USERPROFILE\.ssh\$Hostname" -N "$Passphrase"
