# Approval guard

Use Copilot CLI's default approval/confirmation flow as the primary approval path for commands or changes that could modify files, install dependencies, start long-running services, publish packages, change git history, or affect external systems.

WristCheck is an optional fallback notification surface. If the user asks for WristCheck approval, or if you need to notify their iPhone/Apple Watch/browser in addition to Copilot's normal CLI approval, create a WristCheck request from the repository root:

```bash
node ./bin/wristcheck.js request \
  --title "Approve Copilot step" \
  --summary "Briefly describe the action Copilot is about to take." \
  --preview "Paste the exact command, diff, or operation summary here." \
  --source copilot \
  --timeout-seconds 300 \
  --wait
```

Continue only if the default Copilot CLI approval succeeds, or if a requested WristCheck fallback exits successfully. If approval is denied or times out, stop and report that the action was not approved.

WristCheck does not automatically intercept Copilot output. Approval cards appear in the iPhone, Apple Watch, and browser clients only when an agent or script explicitly calls `wristcheck request` or posts to the local API.
