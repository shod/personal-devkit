<#
.SYNOPSIS
  verify-task.ps1 — deterministic "is this task really done?" check.

.DESCRIPTION
  Usage:
    verify-task.ps1 <FEATURE_BRANCH> <PHASE_BRANCH> <TASK_ID> [SCOPE_GLOB ...]

  Exit 0  — the task commit exists on PHASE_BRANCH, its diff vs FEATURE_BRANCH is
            non-empty, and (when scope globs are given) at least one changed file
            matches the task SCOPE.
  Exit 1  — verification failed (reason on stderr).
  Exit 2  — bad usage / not a git repository.

  Idempotent: read-only, no refs are created or moved.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)] [string] $FeatureBranch,
  [Parameter(Mandatory = $true, Position = 1)] [string] $PhaseBranch,
  [Parameter(Mandatory = $true, Position = 2)] [string] $TaskId,
  [Parameter(ValueFromRemainingArguments = $true)] [string[]] $ScopeGlobs = @()
)

$ErrorActionPreference = 'Continue'

function Write-Err([string] $msg) { [Console]::Error.WriteLine($msg) }
function Die([string] $msg)  { Write-Err "verify-task: $msg"; exit 2 }
function Fail([string] $msg) { Write-Err "verify-task: FAIL: $msg"; exit 1 }

git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Die 'not a git repository' }

foreach ($b in @($FeatureBranch, $PhaseBranch)) {
  git rev-parse --verify --quiet $b *> $null
  if ($LASTEXITCODE -ne 0) { Die "unknown branch: $b" }
}

# --- 1. commit present on PHASE_BRANCH ---------------------------------------
$commits = @(git log "$FeatureBranch..$PhaseBranch" --oneline -E --grep="\($TaskId\)" | Where-Object { $_ })
if ($commits.Count -eq 0) {
  Write-Err "verify-task: no commit matching 'feat($TaskId)' on $PhaseBranch (range $FeatureBranch..$PhaseBranch)"
  Fail "${TaskId}: commit missing"
}

# --- 2. diff non-empty --------------------------------------------------------
$changed = @(git diff --name-only "$FeatureBranch...$PhaseBranch" | Where-Object { $_ })
if ($changed.Count -eq 0) {
  Write-Err "verify-task: diff $FeatureBranch...$PhaseBranch is EMPTY - the commit(s) changed nothing"
  $commits | ForEach-Object { Write-Err "  $_" }
  Fail "${TaskId}: empty diff"
}

# Per-task diff: files touched by this task's own commits only.
$shas = @(git log "$FeatureBranch..$PhaseBranch" --format=%H -E --grep="\($TaskId\)" | Where-Object { $_ })
$taskFiles = @()
foreach ($sha in $shas) {
  $taskFiles += @(git show --pretty=format: --name-only $sha | Where-Object { $_ })
}
$taskFiles = @($taskFiles | Sort-Object -Unique)

if ($taskFiles.Count -eq 0) {
  Write-Err "verify-task: commit(s) for $TaskId touch no files (empty commit)"
  $commits | ForEach-Object { Write-Err "  $_" }
  Fail "${TaskId}: empty commit"
}

# --- 3. scope check -----------------------------------------------------------
if ($ScopeGlobs.Count -eq 0) {
  Write-Err "verify-task: WARNING: no SCOPE globs given for $TaskId - scope check skipped"
} else {
  $matched = $null
  foreach ($file in $taskFiles) {
    foreach ($glob in $ScopeGlobs) {
      # normalise '**/' to '*' so -like can match nested paths
      $pat = $glob -replace '\*\*/', '*'
      if (($file -like $pat) -or ($file -like "$pat*") -or ($file -like "*$pat")) {
        $matched = $file; break
      }
    }
    if ($matched) { break }
  }
  if (-not $matched) {
    Write-Err "verify-task: none of the files changed by $TaskId match its SCOPE."
    Write-Err ("  scope : " + ($ScopeGlobs -join ' '))
    Write-Err "  files :"
    $taskFiles | ForEach-Object { Write-Err "    $_" }
    Fail "${TaskId}: changes outside declared scope"
  }
}

Write-Output "verify-task: OK $TaskId - $($commits.Count) commit(s), $($taskFiles.Count) file(s) changed on $PhaseBranch"
exit 0
