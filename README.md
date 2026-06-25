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
node ./bin/wristcheck.js serve --host 0.0.0.0 --port 8787
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

## Apple Watch app

The SwiftUI source in `watchos/WristCheckWatchApp` polls:

```text
GET /api/requests/next?watchType=apple-watch
POST /api/requests/:id/decision
```

Open `WristCheck.xcodeproj` in Xcode, select the `WristCheck` target, set your Apple developer team/signing if prompted, and run it on a paired Apple Watch or watch simulator. In the Watch app, open the gear/settings screen and set `Server URL` to the Mac LAN URL. The MVP uses direct LAN HTTP so it works without a cloud relay; a production app should add pairing, authentication, TLS, and an iPhone companion/WatchConnectivity path.

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
