param (
    [string]$msg,
    [switch]$main = $false
)

if (-not $msg) {
    $msg = "update: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss (zzz)"))"
}

git fetch
git merge
git add -A
git commit -m "$msg"
# TODO: you cant update if working tree is clean
if (-not $?) {
    exit 1
}

git push

if ($main) {
    $currentBranch = git branch --show-current
    if ($currentBranch -ne "main") {
        git checkout main
        git merge $currentBranch
        git push
        git checkout $currentBranch
    }
}
