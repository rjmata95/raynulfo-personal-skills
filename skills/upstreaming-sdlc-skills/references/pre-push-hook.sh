#!/usr/bin/env bash
# pre-push hook for an SDLC-skills clone.
#
# Install (per clone; .git/hooks never ships):
#   cp ~/.claude/skills/upstreaming-sdlc-skills/references/pre-push-hook.sh .git/hooks/pre-push
#   chmod +x .git/hooks/pre-push
#
# Refuses any push to main (the mirror is written only by the company laptop), runs
# check-upstream-clean.py on every feat/* port branch, and lets everything else through.

set -uo pipefail

GATE="${UPSTREAM_GATE:-$HOME/.claude/skills/upstreaming-sdlc-skills/check-upstream-clean.py}"
MIRROR="${UPSTREAM_MIRROR:-main}"
status=0

while read -r local_ref local_sha remote_ref _remote_sha; do
  # Deleting a ref: nothing to inspect.
  [ "$local_sha" = "0000000000000000000000000000000000000000" ] && continue

  case "$remote_ref" in
    refs/heads/main)
      echo "pre-push: refusing to push $local_ref to main." >&2
      echo "  main mirrors the enterprise repo and is written only by the company laptop." >&2
      status=1
      continue
      ;;
  esac

  case "$local_ref" in
    refs/heads/feat/*)
      if [ ! -f "$GATE" ]; then
        echo "pre-push: gate not found at $GATE" >&2
        echo "  link raynulfo-personal-skills, or set UPSTREAM_GATE." >&2
        status=1
        continue
      fi
      echo "pre-push: gating ${local_ref#refs/heads/} against $MIRROR"
      if ! python3 "$GATE" --mirror "$MIRROR" --branch "$local_sha"; then
        status=1
      fi
      ;;
  esac
done

if [ "$status" -ne 0 ]; then
  echo "" >&2
  echo "pre-push: blocked. Fix the findings, or bypass deliberately with --no-verify." >&2
fi

exit "$status"
