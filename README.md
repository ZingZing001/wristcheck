# WristCheck

WristCheck is a local approval bridge for AI coding tools. It lets Copilot or another agent pause before a sensitive step, show a preview, and continue only after you approve from Apple Watch. The server is adapter-based so other watch types can be added later.

## What is included

- `wristcheck serve`: local HTTP approval server and browser fallback.
- `wristcheck request`: CLI gate that creates an approval request and blocks until approved, denied, or timed out.
- Apple Watch SwiftUI source under `watchos/WristCheckWatchApp`.
- Adapter registry under `src/adapters` for future watch types.

## Quick start

```bash
git clone https://github.com/ZingZing001/wristcheck.git
cd wristcheck
npm run setup
npm run doctor
npm test
npm start -- --host 0.0.0.0 --port 8787
open WristCheck.xcodeproj
```

Open `http://127.0.0.1:8787` for the browser fallback. For Apple Watch, use the LAN URL printed by the server, for example `http://192.168.1.20:8787`.

In another terminal:

```bash
node ./bin/wristcheck.js request \
  --title "Run Copilot step" \
  --summary "Review the next action before it continues." \
  --preview "npm test"
```

## Using it as a Copilot guard

Put `wristcheck request` before any step that should require human confirmation:

```bash
git --no-pager diff --stat | wristcheck request \
  --title "Apply generated changes" \
  --summary "Approve this Copilot step from your watch."
```

The command exits `0` when approved and `2` when denied or timed out.

## GitHub install for another Mac

This repo can be downloaded directly from GitHub and installed with a free Apple ID, as long as the user has Xcode and a paired iPhone/Apple Watch:

```bash
git clone https://github.com/ZingZing001/wristcheck.git
cd wristcheck
npm run setup
npm run doctor
npm start -- --host 0.0.0.0 --port 8787
```

Then open `WristCheck.xcodeproj` in Xcode, select the user's Apple ID team under Signing & Capabilities, choose the paired Apple Watch as the run destination, and press Run. Different iPhone/watchOS versions are supported by rebuilding from source with the user's installed Xcode SDKs; if a Watch is newer than Xcode supports, install a matching/newer Xcode first.

`wristcheck doctor` prints the Watch pairing URL and reports running GitHub Copilot CLI or Claude Code processes on the Mac. The Watch pairs by entering the printed LAN URL in the Watch app settings.

> Note: A one-tap public Watch install without Xcode requires TestFlight/App Store distribution and a paid Apple Developer Program account. Direct LAN pairing does not use APNs, so notification delivery is best-effort while the Watch app is running or recently backgrounded.

## Apple Watch app

The SwiftUI source in `watchos/WristCheckWatchApp` polls:

```text
GET /api/requests/next?watchType=apple-watch
POST /api/requests/:id/decision
```

Open `WristCheck.xcodeproj` in Xcode. In the Watch app, open the gear/settings screen and set `Server URL` to the Mac LAN URL. The app polls the local server and posts actionable local notifications with Approve/Deny actions for pending requests it sees while running or recently backgrounded.

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/requests` | Create a step approval request. |
| `GET` | `/api/requests/next?watchType=apple-watch` | Fetch the next pending request for a watch. |
| `POST` | `/api/requests/:id/decision` | Approve or deny with `{ "decision": "approved" }` or `{ "decision": "denied" }`. |
| `GET` | `/api/requests` | List requests for the browser fallback. |

## Adding another watch type

Add an adapter in `src/adapters`, then register it:

```js
registerWatchAdapter({
  type: 'garmin',
  displayName: 'Garmin',
  shapeRequest(request) {
    return request;
  }
});
```

Adapters can trim previews, rename fields, or add watch-specific metadata without changing the core approval flow.
