# Approval guard

For risky actions, use Copilot CLI approval first. If the user does not respond in CLI within 10 seconds, trigger WristCheck and keep sending WristCheck reminders until CLI or WristCheck responds. Whichever response arrives first wins; continue only on approval.

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
