#!/bin/bash
# Pre-push safety hook: blocks pushing a non-main branch directly to origin/main.
#
# Root cause: `git worktree add ... -b <name> origin/main` sets the new branch's
# upstream to origin/main. Combined with `push.default=upstream`, any subsequent
# `git push origin <name>` silently pushes to main, bypassing PR review.
#
# This hook intercepts that and tells you how to fix the tracking reference.

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  if [[ "$remote_ref" == "refs/heads/main" ]] && [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo ""
    echo "🚫 BLOCKED: attempted to push '$CURRENT_BRANCH' → 'main'"
    echo ""
    echo "   Your branch tracks origin/main. With push.default=upstream, git"
    echo "   silently routes the push to main instead of your feature branch."
    echo ""
    echo "   Fix the upstream tracking and retry:"
    echo ""
    echo "     git branch --unset-upstream"
    echo "     git push origin HEAD:$CURRENT_BRANCH"
    echo "     git branch -u origin/$CURRENT_BRANCH"
    echo ""
    echo "   Then open a PR with: gh pr create"
    echo ""
    exit 1
  fi
done

exit 0
