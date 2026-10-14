# OpenLens ENGO 3 — upgraded features and validation

This branch extends the user's previously working ActiveLook iOS demo instead of replacing it. The original Advanced Tools and local Xcode fixes are preserved.

## The new companion app

- **Connection and dashboard:** automatic initial Bluetooth scan, manual rescan, ENGO 3 connection and battery status, clear disconnect and grouped two-column feature tiles.
- **Text and live captions:** typed text to display, speech recognition via the iPhone microphone, language choices including English, French, Spanish, Hindi and Telugu where supported, readable Latin transliteration for the legacy hardware font, consistent rotation setting, long-text pagination, and handoff to Presenter.
- **Photo display:** photo picker, 192×96 preview, letterbox or fill crop, 1-bit high contrast, 1-bit Floyd–Steinberg dithering, grayscale using the SDK's compressed 4-bit stream, invert and 180-degree rotation. The 1-bit path avoids the SDK's generic x/y coordinate bug. No immediate image deletion.
- **Quick cards:** four starter cards, custom saved cards on the iPhone, edit and delete, tap to open on glasses.
- **Presenter:** paste a talk or notes; page through long text with Previous/Next; optional 10-second auto-advance while this screen is open.
- **Focus and clock:** 5/15/25-minute timer, pause, resume, reset, periodic text updates, manual phone clock display. This is *not* a background alarm.
- **Walking routes:** MapKit walking search, multi-step route preview, manual Next/Previous while stationary. This is *not* automatic or safety-critical navigation.
- **Device settings:** luminance, automatic brightness, gesture detection and readback; orientation calibration, alignment test.
- **Diagnostics:** battery, firmware, serial, actual reported settings, copy diagnostic output, clear display.
- **AI and translation:** existing private HTTPS relay architecture, no embedded API secret; requires user-controlled relay to work.
- **Original demo commands:** kept under Advanced Tools. Commands unsupported by ENGO 3 firmware may not work.

Firmware update authorization is intentionally NOT automatic in this experimental app. Use the official ActiveLook app for firmware updates.

## Verification

- Nine SwiftPM unit tests pass locally via: swift test --disable-sandbox.
- GitHub Actions runs the unsigned iOS simulator build on macOS, plus a new Ubuntu Swift core-tests job.
- An early simulator build caught two UIKit property collisions with the word 'next'; they were fixed and later simulator builds passed.
- Unit tests cover line wrapping, long words, pagination, unsupported-character handling, Hindi and Telugu romanization, countdown formatting, black-and-white dithering and JSON card serialization.

**Hardware-dependent tests are still required.** Sending a BLE command or queuing an image is not proof it appeared in the optics. ENGO 3 firmware-specific settings, actual transfer completion, photo orientation, ASR language availability and the appearance of all HUD elements cannot be verified without the physical device. Begin photo testing with a simple high-contrast image.

## Install on the existing Mac project

Run these commands in Terminal, one line at a time:

    cd ~/Documents/Engo
    git status
    git stash push -u -m "Preserve working OpenLens before feature upgrade"
    git fetch origin
    git switch feature/openlens-engo3-experience
    cd ios
    pod install
    open example.xcworkspace

Use the same Apple Personal Team in Xcode and run on your iPhone. Keep your earlier working checkout and its stash intact. See ENGO3_DEVICE_TEST_PLAN.md for the real-glasses checklist.

## Sources

Official SDK (Apache 2.0): https://github.com/ActiveLook/ios-sdk
ActiveLook API: https://github.com/ActiveLook/Activelook-API-Documentation
OpenLens review: https://github.com/SriBYJU/Engo/pull/2
