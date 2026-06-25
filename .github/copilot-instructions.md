# Approval guard

For risky actions, use WristCheck's own approval gate instead of relying on Copilot's native approval prompt where possible. WristCheck shows a CLI prompt immediately, sends mobile/watch fallback after CLI idle, and exits when either channel responds. Continue only on approval.

Request pattern from the repository root:

```bash
node ./bin/wristcheck.js request \
  --title "Approve Copilot step" \
  --summary "Briefly describe the action Copilot is about to take." \
  --preview "Paste the exact command, diff, or operation summary here." \
  --source copilot \
  --timeout-seconds 300 \
  --wait
```

WristCheck does not automatically intercept Copilot output. Approval cards appear in the iPhone, Apple Watch, and browser clients only when an agent or script explicitly calls `wristcheck request` or posts to the local API.
