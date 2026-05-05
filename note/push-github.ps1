# 提交并推送到远程 origin（通常为 GitHub）
# 本文件须以 UTF-8（建议带 BOM）保存，否则 Windows PowerShell 5.1 可能把中文解析乱导致报错。
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\note\push-github.ps1 -Message "说明"
#   .\note\push-github.ps1 -m "说明"
# 工作区无变更：跳过提交，直接 push。有变更但未带 -Message：报错退出。
# 可选：-SkipCommit 只推送；-DryRun 仅 dry-run push；-ForcePush 使用 --force-with-lease。

param(
    [Alias('m')]
    [string]$Message = '',
    [switch]$SkipCommit,
    [switch]$DryRun,
    [switch]$ForcePush
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot

function Test-GitDirty {
    $porcelain = git status --porcelain 2>$null
    return ($null -ne $porcelain -and $porcelain.Length -gt 0)
}

try {
    $null = git rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "当前目录不是 Git 仓库。"
    }

    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq 'HEAD') {
        Write-Error "处于 detached HEAD，请先切换到分支再推送。"
    }

    Write-Host "仓库: $RepoRoot"
    Write-Host "分支: $branch"
    Write-Host "远程: origin"

    $dirty = Test-GitDirty

    if (-not $SkipCommit) {
        if ($dirty) {
            $msg = $Message.Trim()
            if ([string]::IsNullOrWhiteSpace($msg)) {
                Write-Error "工作区有未提交变更，请使用 -Message（或 -m）填写提交说明。"
            }
            Write-Host "执行: git add -A" -ForegroundColor DarkGray
            git add -A
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

            Write-Host "执行: git commit -m ..." -ForegroundColor DarkGray
            git commit -m $msg
            if ($LASTEXITCODE -ne 0) {
                Write-Error "git commit 失败（若无改动可检查是否被忽略或钩子拦截）。"
            }
        }
        else {
            Write-Host "工作区干净，跳过提交。" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "已指定 -SkipCommit：跳过 add/commit。" -ForegroundColor DarkGray
    }

    $gitPushArgs = @('push', '-u', 'origin', $branch)
    if ($DryRun) {
        $gitPushArgs = @('push', '--dry-run', '-u', 'origin', $branch)
        Write-Host "[DryRun] push 不会真正上传。" -ForegroundColor Cyan
    }
    elseif ($ForcePush) {
        $gitPushArgs = @('push', '--force-with-lease', '-u', 'origin', $branch)
        Write-Host "[ForcePush] 使用 --force-with-lease。" -ForegroundColor Yellow
    }

    & git @gitPushArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}
