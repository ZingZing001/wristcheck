# WristCheck

WristCheck is a local approval bridge for AI coding tools. It lets Copilot, Claude, or another agent pause before a sensitive step, show a preview, and continue only after you approve from Apple Watch, iPhone, or the browser fallback. Everything runs on your local network.

## What is included

- `wristcheck serve`: local HTTP approval server and browser fallback.
- `wristcheck request`: CLI gate that creates an approval request and blocks until approved, denied, or timed out.
- Apple Watch SwiftUI source under `watchos/WristCheckWatchApp`.
- iPhone companion SwiftUI source under `ios/WristCheckCompanion`.
- Adapter registry under `src/adapters` for future watch types.

## Quick start

If you want an AI coding agent to do the setup for you, copy the prompt in [`AI_SETUP.md`](AI_SETUP.md).

```bash
git clone https://github.com/ZingZing001/wristcheck.git
cd wristcheck
npm run setup
npm run doctor
npm test
npm start
open WristCheck.xcodeproj
```

Open `http://127.0.0.1:8787` for the browser fallback. To pair iPhone or Apple Watch directly, the Mac server must listen on the private LAN:

```bash
npm start -- --host 0.0.0.0 --port 8787
```

Then use the LAN URL printed by `npm run doctor` or `npm start`, for example `http://192.168.1.20:8787`.

Only expose the server on trusted private networks. WristCheck is a local approval bridge, not an internet-facing service.

To start the Mac server automatically when you log in:

```bash
npm run autostart:install
```

For direct iPhone/Watch pairing on a trusted private LAN:

```bash
WRISTCHECK_HOST=0.0.0.0 npm run autostart:install
```

Remove it with:

```bash
npm run autostart:uninstall
```

In another terminal:

```bash
node ./bin/wristcheck.js request \
  --title "Run Copilot step" \
  --summary "Review the next action before it continues." \
  --preview "npm test"
```

## Using it as a Copilot guard

WristCheck does not automatically intercept Copilot output. Approval cards appear in the iPhone, Apple Watch, and browser clients only when Copilot, a script, or another agent explicitly calls `wristcheck request` or posts to the local API.

Put `wristcheck request` before any step that should require human confirmation:

```bash
git --no-pager diff --stat | wristcheck request \
  --title "Apply generated changes" \
  --summary "Approve this Copilot step from your watch."
```

The command exits `0` when approved and `2` when denied or timed out. While it waits, approve or deny from the terminal prompt first. If there is no CLI response for 10 seconds, WristCheck starts sending iPhone, Apple Watch, and browser fallback approval reminders until either channel responds.

This repo includes `.github/copilot-instructions.md` telling Copilot to use CLI approval first, trigger WristCheck after 10 idle seconds, and treat whichever response arrives first as authoritative. For other repositories, copy that instruction into the target repo or your Copilot custom instructions.

## GitHub install for another Mac

This repo can be downloaded directly from GitHub and installed with a free Apple ID, as long as the user has Xcode and a paired iPhone/Apple Watch:

```bash
git clone https://github.com/ZingZing001/wristcheck.git
cd wristcheck
npm run setup
npm run doctor
npm start
```

Then open `WristCheck.xcodeproj` in Xcode, select the user's Apple ID team under Signing & Capabilities, choose the iPhone or paired Apple Watch run destination, and press Run. Different iPhone/watchOS versions are supported by rebuilding from source with the user's installed Xcode SDKs; if a device is newer than Xcode supports, install a matching/newer Xcode first.

`wristcheck doctor` prints the pairing URL and reports running GitHub Copilot CLI or Claude Code processes on the Mac. The iPhone and Watch pair by entering the printed LAN URL in app settings.

> Note: A one-tap public iPhone/Watch install without Xcode requires TestFlight/App Store distribution and a paid Apple Developer Program account. Direct LAN pairing does not use APNs, so closed-app notification delivery is best-effort.

## Apple Watch app

The SwiftUI source in `watchos/WristCheckWatchApp` polls:

```text
GET /api/requests/next?watchType=apple-watch
POST /api/requests/:id/decision
```

Open `WristCheck.xcodeproj` in Xcode and run the `WristCheck` target on Apple Watch. In the Watch app, open the gear/settings screen and set `Server URL` to the Mac LAN URL. The app polls the local server while active and posts actionable local notifications with Approve/Deny actions for pending requests it sees.

watchOS does not allow arbitrary always-on polling for this kind of app. For the most reliable no-cost setup, run the iPhone companion and allow its notifications to mirror to Apple Watch.

## Free iPhone companion bridge

For a more reliable free setup, build and run both Xcode targets:

1. `WristCheckCompanion` on the paired iPhone.
2. `WristCheck` on the Apple Watch.

Open the iPhone app, set the Mac server URL printed by `npm run doctor`, then tap `Start bridge`. The iPhone polls the Mac every few seconds while open, keeps polling briefly after it is backgrounded, schedules best-effort Background App Refresh, and posts actionable local notifications. If your iPhone notification settings mirror WristCheck alerts to Apple Watch, those approval notifications appear on the Watch without paid APNs.

This still does not use APNs, so it is not a production push service. iOS decides when Background App Refresh runs; for instant closed-app delivery, add an APNs push relay.

The iPhone app includes Copy, Paste, and Test controls for the Mac server URL. Raw host/IP clipboard values are normalized to `http://host:8787`.

## Troubleshooting

### Device does not appear in Xcode

Install the Xcode version or beta that matches the device OS. For example, an iPhone on an iOS beta usually needs the matching Xcode beta selected with `xcode-select` or `DEVELOPER_DIR`.

### App says it cannot be verified

Free Apple ID builds must be trusted on the device: Settings → General → VPN & Device Management → trust your developer profile.

### iPhone app appears letterboxed

Rebuild the latest project. The companion target includes a launch screen declaration so it runs full-screen on modern iPhones.

### Notifications only arrive after opening an app

Local network polling works best while the iPhone companion is running. iOS and watchOS limit closed-app polling. Use APNs/TestFlight/App Store infrastructure for production-grade push delivery.

### Home Screen icon is blank on iOS beta

The companion target includes both asset-catalog icons and explicit `AppIcon60x60@2x/@3x` PNG fallbacks. If an iOS beta still shows a cached generic icon, restart the iPhone or remove/reinstall the app.

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

## License

MIT
