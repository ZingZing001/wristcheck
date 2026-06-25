# Dual-channel approval guard

Before commands or changes that could modify files, install dependencies, start long-running services, publish packages, change git history, or affect external systems, send approval to both channels:

1. Copilot CLI's normal approval/confirmation prompt.
2. A WristCheck request from the repository root:

```bash
node ./bin/wristcheck.js request \
  --title "Approve Copilot step" \
  --summary "Briefly describe the action Copilot is about to take." \
  --preview "Paste the exact command, diff, or operation summary here." \
  --source copilot \
  --timeout-seconds 300 \
  --wait
```

Whichever channel responds first is authoritative. Continue only if the first response is approval. If the first response is denial or timeout, stop and report that the action was not approved. If one channel approves first, do not wait for the other channel.

WristCheck does not automatically intercept Copilot output. Approval cards appear in the iPhone, Apple Watch, and browser clients only when an agent or script explicitly calls `wristcheck request` or posts to the local API.
