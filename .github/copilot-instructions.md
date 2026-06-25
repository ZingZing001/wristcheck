# Approval guard

For risky actions, use Copilot CLI approval first. If CLI is idle for 10 seconds, switch to WristCheck fallback and send future approvals there immediately until the user approves/denies in CLI again. Whichever response arrives first wins; continue only on approval.

WristCheck request pattern from the repository root:

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
