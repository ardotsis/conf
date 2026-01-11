param (
    [string]$msg,
    [switch]$all = $false
)

if (-not $msg) {
    $msg = "update: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss (zzz)"))"
}

git fetch
git merge
git add -A
git commit -m "$msg"
if (-not $?) {
    exit 1
}

git push

if ($all) {
    $branch = git branch --show-current
    if ($branch -ne "main") {
        git checkout main
        git merge dev
        git push
        git checkout dev
    }
}
