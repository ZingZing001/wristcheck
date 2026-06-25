# Approval guard

For risky actions, ask for approval with Copilot CLI's normal approval prompt first. If the user has not responded in CLI after 10 seconds and the agent can still run commands, send a WristCheck fallback request. After WristCheck fallback is triggered, send future approvals to WristCheck immediately until the user approves/denies in CLI again. Whichever response arrives first wins; continue only on approval. Treat WristCheck approve/deny responses as high-importance and authoritative when they arrive first; a deny from any channel is terminal and must not be overridden by a later approve.

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
