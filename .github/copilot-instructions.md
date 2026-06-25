# WristCheck approval guard

Before running commands or making changes that could modify files, install dependencies, start long-running services, publish packages, change git history, or affect external systems, create a WristCheck approval request and wait for the user's decision.

Use this pattern from the repository root:

```bash
node ./bin/wristcheck.js request \
  --title "Approve Copilot step" \
  --summary "Briefly describe the action Copilot is about to take." \
  --preview "Paste the exact command, diff, or operation summary here." \
  --source copilot \
  --timeout-seconds 300 \
  --wait
```

Continue only if the command exits successfully. The same approval request can be approved or denied from iPhone, Apple Watch, browser, or the terminal prompt shown by `wristcheck request --wait`. If it is denied or times out, stop and report that the action was not approved.

WristCheck does not automatically intercept Copilot output. Approval cards appear in the iPhone, Apple Watch, and browser clients only when an agent or script explicitly calls `wristcheck request` or posts to the local API.
