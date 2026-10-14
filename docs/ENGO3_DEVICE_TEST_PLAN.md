# OpenLens for ENGO 3 — device acceptance tests

OpenLens builds on the official ActiveLook iOS demo / ActiveLookSDK v4.5.5. The original demo is preserved in **Advanced developer tools**.

## What changed
- Synced the user's local Xcode fixes: personal-team signing, bundle identifier, privacy usage descriptions, iOS 15 CocoaPods deployment targeting, Int16 text-coordinate correction, and the ENGO 3 firmware-version workaround.
- Modern entry, connection list, dashboard, clear back navigation, quick feature actions, battery display and explicit disconnect.
- Text orientation defaults to `.topLR` (instead of the old upside-down `.bottomRL`); settings let the user toggle and run an orientation test.
- Repaired the **Disable auto brightness** action, which previously disabled gestures instead of automatic brightness. Device settings can be queried again to verify response.
- New photo picker: scales images to **192×96**, composites black padding, thresholds to actual black/white for the 1-bit path, offers optional 4-bit compressed streaming, and avoids a known SDK bug in its generic 1-bit stream wrapper (uses x for y). Images are **not immediately deleted**.
- Added basic transfer-error feedback for SDK flow-control conditions. No new cloud service is required for local display.

## Physical ENGO 3 tests (required)
1. On a Mac, open `ios/example.xcworkspace` after running `pod install` in `ios`.
2. Choose an iPhone signed to your Apple Personal Team. Run with Command+R.
3. Scan, tap ENGO 3 and verify the OpenLens dashboard appears.
4. Verify a real battery percentage (device may take a moment to report it).
5. Open **Display & device settings**; tap **Show orientation test**. Verify "OPENLENS - THIS WAY UP" is readable. If upside down, select **Rotated 180°**, test again.
6. From **Send text**, display "HELLO FROM OPENLENS". Verify text is readable and not clipped.
7. Test **Display a photo** first with a high-contrast black-and-white 192×96 image or simple logo; confirm image *on the glasses*, not just in the iPhone preview.
8. Try **More detail** only after 1-bit mode passes. Watch Xcode console for flow-control overflows.
9. Turn automatic brightness off, adjust manual brightness, then **Refresh actual settings**. Confirm the device reports the new values.
10. Toggle gesture detection and refresh. Verify readback or record firmware incompatibility.
11. Test live captions after granting mic and speech permissions.
12. Check AI and translation show a configuration message until a private authenticated HTTPS relay is set up; do not embed API keys in the app.
13. Test walking directions only when stationary. The current MapKit implementation provides the **first walking step only**, not continuous navigation.
14. Test navigation back, reconnect, and disconnect. Record any device or UI failures.

## Important limitations
- We could parse Swift source and inspect the project configuration in this environment, but **could not build with Xcode or test physical ENGO 3**. Device functionality beyond the user's already-confirmed text/BLE connection remains unverified.
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
