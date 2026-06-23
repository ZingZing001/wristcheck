#!/usr/bin/env bash
set -euo pipefail

PREVIEW="$(git --no-pager diff --stat || true)"

wristcheck request \
  --title "Continue Copilot step" \
  --summary "Copilot wants to run the next local action. Approve from your watch to continue." \
  --preview "${PREVIEW:-No git diff available.}"

echo "Approved. Continue with the guarded command here."
