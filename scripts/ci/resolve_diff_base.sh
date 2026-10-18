#!/usr/bin/env bash
# Prints the commit that deploy_functions.mjs --changed should diff HEAD against, and logs on
# stderr which base was chosen and why.
#
# Usage: resolve_diff_base.sh <before-sha> <base-branch> <is-main:true|false>
#
# WHY (5 Oct 2026): the workflow passed github.event.before straight through. After a rebase or
# force-push that commit is no longer in the branch's history (often not in the clone at all), and
# `git diff before...HEAD` died with "Invalid symmetric difference expression" before checking
# anything -- #1158, #1173, #1179, #1183, #1186, #1193.
#
# Rules:
#   1. `before` is used only if it exists, is not all zeros, and is an ancestor of HEAD.
#      This is the normal push, and on main it is exactly the pre-merge behaviour.
#   2. Otherwise, on main: HEAD~1 (main is never rebased by the release train; this only covers a
#      first push or a forced one).
#   3. Otherwise, on a branch: merge-base of origin/<base-branch> and HEAD -- everything the branch
#      changes, which is a superset of the last push, so no real check is skipped.
#   4. If even that fails: HEAD~1, and say so.
set -euo pipefail
before="${1:-}"
base_branch="${2:-main}"
is_main="${3:-false}"

log() { echo "diff base: $*" >&2; }

if [ -n "$before" ] && ! [[ "$before" =~ ^0+$ ]] \
   && git cat-file -e "${before}^{commit}" 2>/dev/null \
   && git merge-base --is-ancestor "$before" HEAD 2>/dev/null; then
  log "$before (github.event.before, an ancestor of HEAD)"
  echo "$before"; exit 0
fi
log "github.event.before '${before}' is unusable (empty, all zeros, missing, or not an ancestor -- a rebase or force-push)"

if [ "$is_main" != "true" ]; then
  git rev-parse --verify -q "origin/${base_branch}" >/dev/null \
    || git fetch --no-tags -q origin "${base_branch}:refs/remotes/origin/${base_branch}" 2>/dev/null || true
  if mb=$(git merge-base "origin/${base_branch}" HEAD 2>/dev/null); then
    log "$mb (merge-base of origin/${base_branch} and HEAD)"
    echo "$mb"; exit 0
  fi
fi

parent=$(git rev-parse HEAD~1)
log "$parent (HEAD~1)"
echo "$parent"
