<#
.SYNOPSIS
  merge-back.ps1 — merge one task branch back into the phase branch (--no-ff, single writer).

.DESCRIPTION
  Usage:
    merge-back.ps1 <PHASE_BRANCH> <BRANCH> <TASK_ID>

  Exit 0  — merged, or nothing to merge (already up to date) — both are success.
  Exit 1  — merge conflict; conflicting files listed on stderr, merge aborted.
  Exit 2  — bad usage / unknown branch / dirty tree / not a git repository.

  Idempotent: re-running after a successful merge reports "already merged" and exits 0.
  NEVER merges into the feature branch or development — PHASE_BRANCH only.
  NEVER uses --squash.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)] [string] $PhaseBranch,
  [Parameter(Mandatory = $true, Position = 1)] [string] $Branch,
  [Parameter(Mandatory = $true, Position = 2)] [string] $TaskId
)

$ErrorActionPreference = 'Continue'

function Write-Err([string] $msg) { [Console]::Error.WriteLine($msg) }
function Die([string] $msg)  { Write-Err "merge-back: $msg"; exit 2 }
function Fail([string] $msg) { Write-Err "merge-back: FAIL: $msg"; exit 1 }

git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Die 'not a git repository' }

foreach ($b in @($PhaseBranch, $Branch)) {
  git rev-parse --verify --quiet $b *> $null
  if ($LASTEXITCODE -ne 0) { Die "unknown branch: $b" }
}

if ($PhaseBranch -in @('development', 'master', 'main')) {
  Die "refusing to merge into '$PhaseBranch' - PHASE_BRANCH only"
}

$dirty = @(git status --porcelain | Where-Object { $_ })
if ($dirty.Count -gt 0) {
  $dirty | ForEach-Object { Write-Err "  $_" }
  Die 'working tree is dirty - commit or stash before merging back'
}

git checkout $PhaseBranch *> $null
if ($LASTEXITCODE -ne 0) { Die "cannot checkout $PhaseBranch" }

$ahead = @(git log "$PhaseBranch..$Branch" --oneline | Where-Object { $_ })
if ($ahead.Count -eq 0) {
  Write-Output "merge-back: nothing to merge - $Branch has no commits beyond $PhaseBranch (already merged?)"
  exit 0
}

git merge --no-ff $Branch -m "feat(${TaskId}): merge into $PhaseBranch" *> $null
if ($LASTEXITCODE -eq 0) {
  Write-Output "merge-back: OK $TaskId - $Branch -> $PhaseBranch (--no-ff)"
  exit 0
}

$conflicts = @(git diff --name-only --diff-filter=U | Where-Object { $_ })
if ($conflicts.Count -gt 0) {
  Write-Err "merge-back: MERGE CONFLICT merging $Branch into $PhaseBranch ($TaskId)"
  Write-Err '  conflicting files:'
  $conflicts | ForEach-Object { Write-Err "    $_" }
  git merge --abort *> $null
  Write-Err "  merge aborted - $PhaseBranch left untouched; resolve manually"
  Fail "${TaskId}: merge conflict"
}

Fail "${TaskId}: merge failed (no conflicts reported - see git output above)"
