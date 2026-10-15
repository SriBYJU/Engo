# OpenLens for ENGO 3 — device acceptance tests

OpenLens builds on the official ActiveLook iOS demo / ActiveLookSDK v4.5.5. The original demo is preserved in **Advanced developer tools**.

## What changed
- Synced the user's local Xcode fixes: personal-team signing, bundle identifier, privacy usage descriptions, iOS 15 CocoaPods deployment targeting, Int16 text-coordinate correction, and the ENGO 3 firmware-version workaround.
- Modern entry, connection list, dashboard, clear back navigation, quick feature actions, battery display and explicit disconnect.
- **Main fix:** OpenLens now paints words into a centered 304×240 high-contrast monochrome image and uses the same `imgStream1bpp` API as the functioning Photos screen. Native `txt()` is no longer used for regular OpenLens messages. The redundant OPENLENS header is removed. Sizes are Small 30px, Medium 42px (default), Large 56px bitmap lettering; pagination preserves all words. Consecutive text frames are rate-limited/coalesced to avoid BLE streams colliding. Image functionality is unchanged.
- Repaired the **Disable auto brightness** action, which previously disabled gestures instead of automatic brightness. Device settings can be queried again to verify response.
- Photo sizes are **Small 160×96**, **Medium 208×144**, **Large 240×192 (default)** and **Full 304×240**. The preview simulates actual screen coverage. Fit/fill, invert, 180-degree rotation, 1-bit high contrast/dither or 4-bit compressed grayscale remain available. Images are not deleted immediately.
- Added basic transfer-error feedback for SDK flow-control conditions. No new cloud service is required for local display.

## Crash regression: RGB image assertion
On 2026-10-14 a physical iPhone debug session stopped in the vendor
`ActiveLookSDK/UIImage+ActiveLook.swift` method `getPixels()` at
`assert(cgImage.colorSpace?.model == .rgb)` when sending text as a
monochrome bitmap. OpenLens now calls `OpenLensRGBImage.normalize`
before `imgStream1bpp`, constructing an explicit 8-bit RGBA DeviceRGB
CGImage and verifying its color model, bits-per-pixel, component depth,
and data provider before sending. It sends nothing if that check fails.

The SDK also packs the image into many BLE commands, so OpenLens now
leaves at least eight seconds between full-size text-frame transfers.
This is a precaution rather than proof that every BLE packet arrives.

**On-device regression:** with ENGO 3 powered on and the updated app
running under Xcode, tap Text > Show on Glasses with `HELLO` first.
Verify there is **no debugger stop or app crash** and the glasses stay
connected. Then test `Hey my name is Shree`, followed by page changes.
If the app still breaks, copy the exact topmost Xcode error and report
whether the *physical glasses* actually powered off or only disconnected.
Stop the debug session (square button) before retrying. Do not modify
or flash firmware from this test app.

## Physical ENGO 3 tests (required)
1. On a Mac, open `ios/example.xcworkspace` after running `pod install` in `ios`.
2. Choose an iPhone signed to your Apple Personal Team. Run with Command+R.
3. Scan, tap ENGO 3 and verify the OpenLens dashboard appears.
4. Verify a real battery percentage (device may take a moment to report it).
5. Open **Glasses settings** and tap **Show orientation test**. It should display just one large centered 'HELLO'—no OPENLENS header, divider or scattered letters. Bitmap text follows the photo orientation by default; use 'Rotated 180°' only if HELLO is inverted. If you still only see a sliver, open Diagnostics and check saved device X/Y shift before using the confirmed hardware shift reset.
6. Open **Text**, choose **Large (56px)**, and type the exact previously broken phrase: 'Hey my name is Shree'. Tap Show on glasses. All words should be readable in correct order on one page. Compare the phone's exact bitmap preview against the image on the glasses. Repeat at Medium (42px). Then type 200+ characters and use Next/Previous to view every page. Allow about 8 seconds between full-screen frames.
7. Open **Display a photo**, choose **Use built-in test pattern**, set High contrast and **Large (240×192)**, then show it. Confirm the image on the *glasses*, not only the phone. Repeat with Small, Medium and Full, checking clipping and transmission delays.
8. Try dither and grayscale only after High contrast succeeds. Watch Xcode console for flow-control overflows. Larger sizes contain more data and may take longer. Full size may be optically clipped.
9. Turn automatic brightness off, adjust manual brightness, then **Refresh actual settings**. Confirm the device reports the new values.
10. Toggle gesture detection and refresh. Verify readback or record firmware incompatibility.
11. Test live captions after granting microphone and speech permissions. Try Start/Stop, copy, clear, switch language, and permission denial. Confirm the app does not leave an active mic after leaving the screen or a failed audio session.
12. Open **Ask AI** with **Auto**. Confirm it reports on-device Apple AI availability. If unavailable, pair the local Mac running Ollama (see `local-ai/README.md`), test health, then ask each task action (Answer, Explain, Summarize, Rewrite, Brainstorm). Validate a complete answer, Previous/Next pages, Copy, Save as Quick Card, and Translate. Verify AI works with internet disconnected but Wi-Fi still connected for Mac mode. Cloud must be explicitly selected; no automatic cloud requests. Deploy the private Cloudflare Worker using `cloudflare/openlens-relay/README.md`. Enter its HTTPS `/openlens` endpoint plus the separate client token using **Set up AI**, and tap **Test AI connection**. Only after it reports `configured: true`, ask a simple question and confirm a complete paginated answer. Test translation and expected errors (unauthorized token, unreachable server, rate limit). Never put the provider API key in the app.
13. Test walking while stationary: search an unambiguous destination (for example a complete street address), choose **Directions text**, and ensure the street name appears in full. The app auto-fits short turns; for longer ones tap **Next page**, not **Next turn**. Switch to **Street map** and verify an actual MapKit route with highlighted path, current-position dot and North marker appears in both the phone preview and ENGO 3. Compare **Next turn** with **Whole route** scopes. The optional location-follow switch updates the map dot about every 20 seconds while the screen is open. Verify Apple Maps handoff for actual live navigation. This is *not* spatially anchored AR or automatic turn recognition. Do not operate the phone while moving or crossing streets.
14. Test **Read Text**: select a clear photo with a paragraph and street names. Verify Apple's Vision recognizes the text locally. Correct a word in the editor and tap **Show all text on glasses**. Check every page in Presenter. Test Copy and Save as Quick Card, then test Camera permissions and an empty/no-text image.
15. Test **Focus and clock**: start a 5-minute timer, confirm the iPhone counts every second while ENGO 3 updates roughly every ten seconds, pause/resume, reset. Enable the live clock and wait a full minute for a single new frame; verify updates stop when leaving the screen.
16. Test navigation back, reconnect, and disconnect. Record any device or UI failures.

## Free local AI setup (recommended)

Run OpenLens with **AI → Auto**. It uses Apple's Foundation Models on an eligible iPhone
with iOS 26+ and downloaded Apple Intelligence models, free and offline.
If Apple AI is unavailable, run Ollama on the user's M1 MacBook Air using the
steps in `local-ai/README.md`: download model once, start the local Python
bridge, select Mac in OpenLens, pair with the local URL and Mac-generated token,
and tap Test local Mac. The Mac must stay awake on the same trusted network.
The Mac bridge communicates over unencrypted HTTP with a bearer token: do
not expose it to public Wi-Fi or the internet. No OpenAI credentials needed.

**Test both routes where available:** iPhone AI health, local Mac health,
simple answer, summarize, translation, long HUD paging, saving results.
Auto must never make a Cloud call. Apple AI hardware support and language
availability must be verified on the real iPhone.

## Optional cloud AI setup

The AI Worker is **source code only until you deploy it**. Read `cloudflare/openlens-relay/README.md`, deploy it with a separate strong client bearer token, set OPENAI_API_KEY using Cloudflare secrets (not in Xcode), and provide the HTTPS endpoint ending in `/openlens` to OpenLens. After deployment, the **Test AI connection** button checks server configuration without paying for a model request. The Node automated tests stub upstream responses and cannot verify your production credentials or quota.

## Important limitations
- GitHub Actions performs an unsigned macOS iOS-simulator build, Swift HUD unit tests and Node Cloudflare-relay tests. The user has confirmed text and photo display after earlier fixes. Physical ENGO 3 testing is still necessary for the new MapKit mini-map and navigation controls.
- Sending BLE commands or receiving SDK callbacks does not prove a frame appeared on the display. Report visual confirmation separately. MapKit snapshots also require connectivity to Apple map-tile services.
- The legacy SDK's 4-bit compressed image chunks can be sensitive to BLE flow-control; the new 1-bit path is recommended first.
- The vendor sample contains commands that may not be supported by ENGO 3 firmware. Advanced tools remain exploratory.
- The old firmware-version comparison falsely rejected an updated ENGO 3. It is logged but not used to block an already-connected device. **Use the official ActiveLook app for firmware updates**; do not flash firmware from an experimental build.
- Preserve the original working Mac checkout until the new branch passes hardware tests.

## Sync this branch to an existing Mac checkout

Do **not** delete your working `~/Documents/Engo` folder. In Terminal:

```bash
cd ~/Documents/Engo
git status
git stash push -u -m "Backup working Xcode changes before OpenLens update"
git fetch origin
git switch feature/openlens-engo3-experience
cd ios
pod install
open example.xcworkspace
```

In Xcode, choose the physical iPhone and Personal Team if prompted, then build/run (Command+R).

This branch contains the saved Xcode changes from the uploaded ZIP, so stashing them does not remove those fixes from the updated version. You can restore the original workspace with `git switch feature/openlens-ios-foundation` and `git stash pop` **after** checking its working tree is appropriate.
