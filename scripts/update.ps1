param (
    [string]$msg = ""
)

if (-not $msg) {
    $msg = "update: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss (zzz)"))"
}

git fetch
git merge
git add -A
git commit -m "$msg"
git push
