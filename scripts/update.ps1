param (
    [string]$CommitMessage,
    [switch]$All = $false
)

if (-not $CommitMessage) {
    $CommitMessage = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
}

Write-Host "Commit message: $CommitMessage"

git fetch
git merge

git add -A
git commit -m "$CommitMessage"
if (-not $?) {
    exit 1
}

git push

if ($All) {
    $branch = git branch --show-current
    if ($branch -ne "main") {
        git checkout main
        git merge dev
        git push
        git checkout dev
    }
}
