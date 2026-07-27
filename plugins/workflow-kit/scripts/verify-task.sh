#!/usr/bin/env bash
# verify-task.sh — deterministic "is this task really done?" check.
#
# Usage:
#   verify-task.sh <FEATURE_BRANCH> <PHASE_BRANCH> <TASK_ID> [SCOPE_GLOB ...]
#
# Exit 0  — the task commit exists on PHASE_BRANCH, its diff vs FEATURE_BRANCH is
#           non-empty, and (when scope globs are given) at least one changed file
#           matches the task SCOPE.
# Exit 1  — verification failed (reason on stderr).
# Exit 2  — bad usage / not a git repository.
#
# Idempotent: read-only, no refs are created or moved.

set -uo pipefail

die() { echo "verify-task: $*" >&2; exit 2; }
fail() { echo "verify-task: FAIL: $*" >&2; exit 1; }

[ $# -ge 3 ] || die "usage: verify-task.sh <FEATURE_BRANCH> <PHASE_BRANCH> <TASK_ID> [SCOPE_GLOB ...]"

FEATURE_BRANCH="$1"; shift
PHASE_BRANCH="$1"; shift
TASK_ID="$1"; shift
SCOPE_GLOBS=("$@")

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
git rev-parse --verify --quiet "$FEATURE_BRANCH" >/dev/null || die "unknown branch: $FEATURE_BRANCH"
git rev-parse --verify --quiet "$PHASE_BRANCH" >/dev/null || die "unknown branch: $PHASE_BRANCH"

# --- 1. commit present on PHASE_BRANCH -------------------------------------
COMMITS=$(git log "${FEATURE_BRANCH}..${PHASE_BRANCH}" --oneline -E --grep="\\(${TASK_ID}\\)" 2>/dev/null || true)
if [ -z "$COMMITS" ]; then
  echo "verify-task: no commit matching 'feat(${TASK_ID})' on ${PHASE_BRANCH} (range ${FEATURE_BRANCH}..${PHASE_BRANCH})" >&2
  fail "${TASK_ID}: commit missing"
fi

# --- 2. diff non-empty ------------------------------------------------------
CHANGED=$(git diff --name-only "${FEATURE_BRANCH}...${PHASE_BRANCH}" 2>/dev/null || true)
if [ -z "$CHANGED" ]; then
  echo "verify-task: diff ${FEATURE_BRANCH}...${PHASE_BRANCH} is EMPTY — the commit(s) changed nothing" >&2
  echo "$COMMITS" >&2
  fail "${TASK_ID}: empty diff"
fi

# Per-task diff: files touched by this task's own commits only.
TASK_SHAS=$(git log "${FEATURE_BRANCH}..${PHASE_BRANCH}" --format=%H -E --grep="\\(${TASK_ID}\\)" 2>/dev/null || true)
TASK_FILES=""
for sha in $TASK_SHAS; do
  f=$(git show --pretty=format: --name-only "$sha" 2>/dev/null || true)
  TASK_FILES=$(printf '%s\n%s' "$TASK_FILES" "$f")
done
TASK_FILES=$(printf '%s\n' "$TASK_FILES" | sed '/^$/d' | sort -u)

if [ -z "$TASK_FILES" ]; then
  echo "verify-task: commit(s) for ${TASK_ID} touch no files (empty commit)" >&2
  echo "$COMMITS" >&2
  fail "${TASK_ID}: empty commit"
fi

# --- 3. scope check ---------------------------------------------------------
if [ ${#SCOPE_GLOBS[@]} -eq 0 ]; then
  echo "verify-task: WARNING: no SCOPE globs given for ${TASK_ID} — scope check skipped" >&2
else
  matched=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    for glob in "${SCOPE_GLOBS[@]}"; do
      # normalise '**/' to '*' so simple bash globbing can match nested paths
      pat=${glob//\*\*\//*}
      # shellcheck disable=SC2053
      if [[ "$file" == $pat || "$file" == $pat* || "$file" == *$pat ]]; then
        matched="$file"
        break
      fi
    done
    [ -n "$matched" ] && break
  done <<< "$TASK_FILES"

  if [ -z "$matched" ]; then
    echo "verify-task: none of the files changed by ${TASK_ID} match its SCOPE." >&2
    echo "  scope : ${SCOPE_GLOBS[*]}" >&2
    echo "  files :" >&2
    printf '    %s\n' $TASK_FILES >&2
    fail "${TASK_ID}: changes outside declared scope"
  fi
fi

N_FILES=$(printf '%s\n' "$TASK_FILES" | wc -l | tr -d ' ')
echo "verify-task: OK ${TASK_ID} — $(printf '%s\n' "$COMMITS" | wc -l | tr -d ' ') commit(s), ${N_FILES} file(s) changed on ${PHASE_BRANCH}"
exit 0
