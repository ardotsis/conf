param (
    [string]$Msg = ""
)

if (-not $Msg) {
    $Msg = "update: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss (zzz)"))"
}

git fetch
git merge
git add -A
git commit -m "$Msg"
git push
