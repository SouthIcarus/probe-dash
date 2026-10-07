#!/usr/bin/env bash
# Enforces the CLAUDE.md hard rules on every commit in a range.
#
# Usage: check-repo-rules.sh <base-sha> <head-sha>
#   Checks every non-merge commit in base..head. An empty or all-zero base
#   checks every commit reachable from head.
#
# Per commit (skipped for commits made before changelog.md existed):
#   R1  changelog.md gains at least one new entry ("## #NNNN — ...").
#   R2  changelog.md is append-only: the old file is an exact prefix of the new.
#       It is never deleted or renamed.
#   R2b New entry IDs are unique and higher than every existing ID.
#   R3  No core file is deleted, unless a DELETE entry in the same commit
#       names its path. A move into archive/ needs a DEPRECATE entry naming
#       the old path.
set -euo pipefail

BASE="${1:-}"
HEAD="${2:?usage: check-repo-rules.sh <base-sha> <head-sha>}"
LOG=changelog.md

# Generated output that tooling rebuilds; not core files (CLAUDE.md rule 3).
EXEMPT_RE='(^|/)(node_modules|dist|build|\.cache|__pycache__|coverage|\.dart_tool)/|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Cargo\.lock|uv\.lock|pubspec\.lock|Podfile\.lock)$'

if [[ -z "$BASE" || "$BASE" =~ ^0+$ ]]; then
  commits=$(git rev-list --reverse --no-merges "$HEAD")
else
  commits=$(git rev-list --reverse --no-merges "$BASE..$HEAD")
fi

fail=0
err() { echo "::error title=Repo rules (CLAUDE.md)::$1"; fail=1; }

for c in $commits; do
  short=$(git rev-parse --short "$c")
  subject=$(git log -1 --format=%s "$c")
  parent=$(git rev-parse --verify -q "$c^" || true)

  # Rules start once changelog.md exists in the parent commit.
  if [[ -z "$parent" ]] || ! git cat-file -e "$parent:$LOG" 2>/dev/null; then
    echo "skip   $short  (before rules existed)  $subject"
    continue
  fi

  ok=1

  if ! git cat-file -e "$c:$LOG" 2>/dev/null; then
    err "$short: $LOG was deleted or renamed. It must never be removed (rule 2)."
    continue
  fi

  old=$(git show "$parent:$LOG")
  new=$(git show "$c:$LOG")
  added=$(git diff "$parent" "$c" -- "$LOG" | sed -n 's/^+\([^+]\)/\1/p; s/^+$//p')

  # R2: append-only.
  if [[ "${new:0:${#old}}" != "$old" ]]; then
    err "$short: $LOG had existing lines edited, removed, or inserted above old entries. Only append new entries at the bottom; to correct one, add an entry that supersedes it (rule 2)."
    ok=0
  fi

  # R1: a new entry in every commit.
  new_ids=$(grep -oE '^## #[0-9]{4} ' <<<"$added" | grep -oE '[0-9]{4}' || true)
  if [[ -z "$new_ids" ]]; then
    err "$short: no new $LOG entry. Every commit must add one ('## #NNNN — YYYY-MM-DD — TYPE — title') (rule 1)."
    ok=0
  fi

  # R2b: IDs unique and increasing.
  max_old=$(grep -oE '^## #[0-9]{4} ' <<<"$old" | grep -oE '[0-9]{4}' | sort -n | tail -1 || true)
  max_old=$((10#${max_old:-0}))
  prev=$max_old
  for id in $new_ids; do
    n=$((10#$id))
    if (( n <= prev )); then
      err "$short: entry #$id is not higher than the previous ID #$(printf '%04d' "$prev"). IDs must be unique and increasing."
      ok=0
    fi
    prev=$n
  done

  # R3: deletions and moves of core files.
  while IFS=$'\t' read -r status src dst; do
    [[ -z "$status" ]] && continue
    [[ "$src" =~ $EXEMPT_RE ]] && continue
    case "$status" in
      D)
        if ! grep -E '^## #[0-9]{4} .*DELETE' <<<"$added" >/dev/null || ! grep -F -- "$src" <<<"$added" >/dev/null; then
          err "$short: core file '$src' deleted without a DELETE entry naming it. Move it to archive/ with a DEPRECATE entry instead (rule 3)."
          ok=0
        fi
        ;;
      R*)
        if [[ "$dst" == archive/* ]]; then
          if ! grep -E '^## #[0-9]{4} .*DEPRECATE' <<<"$added" >/dev/null || ! grep -F -- "$src" <<<"$added" >/dev/null; then
            err "$short: '$src' moved to archive/ without a DEPRECATE entry naming it (rule 3)."
            ok=0
          fi
        fi
        ;;
    esac
  done < <(git diff --name-status -M "$parent" "$c")

  if (( ok )); then
    echo "pass   $short  (#$(tr '\n' ' ' <<<"$new_ids" | sed 's/ $//; s/ / #/g'))  $subject"
  else
    echo "FAIL   $short  $subject"
  fi
done

if (( fail )); then
  echo
  echo "Repo rules failed. See CLAUDE.md for the rules."
  exit 1
fi
echo "All commits follow the repo rules."
