param (
    [string]$CommitMessage,
    [switch]$All
)

if (-not $CommitMessage) {
    $CommitMessage = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
}

Write-Host "Commit message: $CommitMessage"

git fetch
git merge

git add -A
git commit -m "$CommitMessage"
git push

if ($All) {
    "llll"
}
