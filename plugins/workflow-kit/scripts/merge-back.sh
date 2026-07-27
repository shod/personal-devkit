#!/usr/bin/env bash
# merge-back.sh — merge one task branch back into the phase branch (--no-ff, single writer).
#
# Usage:
#   merge-back.sh <PHASE_BRANCH> <BRANCH> <TASK_ID>
#
# Exit 0  — merged, or nothing to merge (already up to date) — both are success.
# Exit 1  — merge conflict; conflicting files listed on stderr, merge aborted.
# Exit 2  — bad usage / unknown branch / dirty tree / not a git repository.
#
# Idempotent: re-running after a successful merge reports "already merged" and exits 0.
# NEVER merges into the feature branch or development — PHASE_BRANCH only.
# NEVER uses --squash.

set -uo pipefail

die()  { echo "merge-back: $*" >&2; exit 2; }
fail() { echo "merge-back: FAIL: $*" >&2; exit 1; }

[ $# -eq 3 ] || die "usage: merge-back.sh <PHASE_BRANCH> <BRANCH> <TASK_ID>"

PHASE_BRANCH="$1"
BRANCH="$2"
TASK_ID="$3"

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
git rev-parse --verify --quiet "$PHASE_BRANCH" >/dev/null || die "unknown phase branch: $PHASE_BRANCH"
git rev-parse --verify --quiet "$BRANCH" >/dev/null || die "unknown task branch: $BRANCH"

case "$PHASE_BRANCH" in
  development|master|main) die "refusing to merge into '$PHASE_BRANCH' — PHASE_BRANCH only" ;;
esac

if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  die "working tree is dirty — commit or stash before merging back"
fi

if ! git checkout "$PHASE_BRANCH" >/dev/null 2>&1; then
  die "cannot checkout $PHASE_BRANCH"
fi

AHEAD=$(git log "${PHASE_BRANCH}..${BRANCH}" --oneline 2>/dev/null || true)
if [ -z "$AHEAD" ]; then
  echo "merge-back: nothing to merge — ${BRANCH} has no commits beyond ${PHASE_BRANCH} (already merged?)"
  exit 0
fi

if git merge --no-ff "$BRANCH" -m "feat(${TASK_ID}): merge into ${PHASE_BRANCH}" >/dev/null 2>&1; then
  echo "merge-back: OK ${TASK_ID} — ${BRANCH} → ${PHASE_BRANCH} (--no-ff)"
  exit 0
fi

CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
if [ -n "$CONFLICTS" ]; then
  echo "merge-back: MERGE CONFLICT merging ${BRANCH} into ${PHASE_BRANCH} (${TASK_ID})" >&2
  echo "  conflicting files:" >&2
  printf '    %s\n' $CONFLICTS >&2
  git merge --abort >/dev/null 2>&1 || true
  echo "  merge aborted — ${PHASE_BRANCH} left untouched; resolve manually" >&2
  fail "${TASK_ID}: merge conflict"
fi

fail "${TASK_ID}: merge failed (no conflicts reported — see git output above)"
