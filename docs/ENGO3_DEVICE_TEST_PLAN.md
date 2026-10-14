# OpenLens for ENGO 3 — device acceptance tests

OpenLens builds on the official ActiveLook iOS demo / ActiveLookSDK v4.5.5. The original demo is preserved in **Advanced developer tools**.

## What changed
- Synced the user's local Xcode fixes: personal-team signing, bundle identifier, privacy usage descriptions, iOS 15 CocoaPods deployment targeting, Int16 text-coordinate correction, and the ENGO 3 firmware-version workaround.
- Modern entry, connection list, dashboard, clear back navigation, quick feature actions, battery display and explicit disconnect.
- Text uses a smaller 24px font, 12-character lines, safe optical margins, mirrored rotation anchors, and adjustable horizontal/vertical text positioning. The full-width divider was removed. Text orientation defaults to `.topLR` and can be toggled.
- Repaired the **Disable auto brightness** action, which previously disabled gestures instead of automatic brightness. Device settings can be queried again to verify response.
- Photo sizes are **Small 160×96**, **Medium 208×144**, **Large 240×192 (default)** and **Full 304×240**. The preview simulates actual screen coverage. Fit/fill, invert, 180-degree rotation, 1-bit high contrast/dither or 4-bit compressed grayscale remain available. Images are not deleted immediately.
- Added basic transfer-error feedback for SDK flow-control conditions. No new cloud service is required for local display.

## Physical ENGO 3 tests (required)
1. On a Mac, open `ios/example.xcworkspace` after running `pod install` in `ios`.
2. Choose an iPhone signed to your Apple Personal Team. Run with Command+R.
3. Scan, tap ENGO 3 and verify the OpenLens dashboard appears.
4. Verify a real battery percentage (device may take a moment to report it).
5. Open **Glasses settings** and tap **Show orientation test**. Confirm the four short rows are readable and not clipped. If upside down, select **Rotated 180°**, test again. Use text-position sliders to move within the visible field. If settings report an existing hardware X/Y shift, the app offers a separate, confirmed hardware shift reset.
6. From **Send text**, display "HELLO FROM OPENLENS". Verify text is readable and not clipped.
7. Open **Display a photo**, choose **Use built-in test pattern**, set High contrast and **Large (240×192)**, then show it. Confirm the image on the *glasses*, not only the phone. Repeat with Small, Medium and Full, checking clipping and transmission delays.
8. Try dither and grayscale only after High contrast succeeds. Watch Xcode console for flow-control overflows. Larger sizes contain more data and may take longer. Full size may be optically clipped.
9. Turn automatic brightness off, adjust manual brightness, then **Refresh actual settings**. Confirm the device reports the new values.
10. Toggle gesture detection and refresh. Verify readback or record firmware incompatibility.
11. Test live captions after granting mic and speech permissions.
12. Check AI and translation show a configuration message until a private authenticated HTTPS relay is set up; do not embed API keys in the app.
13. Test walking routes only while stationary. The app provides **multiple preview steps** with manual Previous/Next, not live location-tracked turn-by-turn navigation.
14. Test navigation back, reconnect, and disconnect. Record any device or UI failures.

## Important limitations
- GitHub Actions performs an unsigned macOS iOS-simulator build and Swift core unit tests. Physical ENGO 3 tests remain necessary; the original text/BLE connection is the only confirmed optical behavior.
- Sending BLE commands or receiving SDK callbacks does not prove a frame appeared on the display. Report visual confirmation separately.
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
