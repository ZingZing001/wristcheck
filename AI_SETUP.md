# AI setup prompt

Use this prompt with Copilot, Claude Code, or another coding agent to set up WristCheck on a Mac with Xcode, iPhone, and Apple Watch.

```text
Set up WristCheck from https://github.com/ZingZing001/wristcheck on this Mac so I can approve AI coding steps from my iPhone, Apple Watch, or browser.

Do the setup end-to-end:
1. Check that Node.js 20+ and Xcode are installed. If Xcode cannot build my iPhone/watchOS version, tell me which newer Xcode or Xcode beta I need.
2. Clone the repo if it is not already present, then run:
   git clone https://github.com/ZingZing001/wristcheck.git
   cd wristcheck
   npm run setup
   npm run doctor
   npm test
3. Start the local browser-only server first with:
   npm start
4. If I want iPhone or Apple Watch direct pairing, restart the server on my trusted private LAN with:
   npm start -- --host 0.0.0.0 --port 8787
   Then give me the LAN URL from `npm run doctor`, such as `http://192.168.1.20:8787`.
5. Open `WristCheck.xcodeproj` in Xcode. Help me select my Apple ID team under Signing & Capabilities, then run:
   - `WristCheckCompanion` on my iPhone.
   - `WristCheck` on my Apple Watch.
6. In the iPhone and Watch apps, set Server URL to the Mac LAN URL and test the connection.
7. Send a real test approval request and wait for my decision:
   node ./bin/wristcheck.js request \
     --title "WristCheck setup test" \
     --summary "Approve this to confirm the iPhone/Watch approval flow works." \
     --preview "Setup validation request from my AI agent." \
     --source setup-agent \
     --timeout-seconds 300 \
     --wait
8. Add WristCheck approval instructions to the repository where I use my AI coding agent. Use this rule: before file changes, dependency installs, long-running services, publishing, git history changes, or external side effects, call `wristcheck request --wait` and continue only if it is approved.

Important constraints:
- Do not assume WristCheck automatically intercepts Copilot or Claude output. It only shows requests when an agent or script explicitly calls `wristcheck request` or the local API.
- Only bind the server to `0.0.0.0` on a trusted private network. Do not expose it to the internet.
- iOS/watchOS local polling is best-effort in the background. For instant closed-app delivery, explain that APNs/TestFlight/App Store infrastructure is required.
- If the Apple Watch does not receive requests while closed, use the iPhone companion bridge and enable iPhone notification mirroring to Apple Watch.
```

## Repository instruction for AI agents

For this repository, `.github/copilot-instructions.md` already tells Copilot to call WristCheck before sensitive actions. For another repository, copy that file into the target repo or paste the same rule into the agent's custom instructions.
