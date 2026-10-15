# OpenLens ENGO 3 — upgraded features and validation

This branch extends the user's previously working ActiveLook iOS demo instead of replacing it. The original Advanced Tools and local Xcode fixes are preserved.

## The new companion app

- **Connection and dashboard:** automatic initial Bluetooth scan, manual rescan, ENGO 3 connection and battery status, clear disconnect and grouped two-column feature tiles.
- **Text and live captions:** typed text to display, speech recognition via the iPhone microphone, language choices including English, French, Spanish, Hindi and Telugu where supported, readable Latin transliteration, reliable black-and-white bitmap text using the *same* image-streaming API as Photos (avoids broken native text rotation), 304×240 frame, Small 30px/Medium 42px/Large 56px bitmap font sizes, automatic per-size wrapping and spacing, multiline editor, exact bitmap preview, direct Previous/Next pages, rotated image control, X/Y bitmap-text positioning and Presenter handoff.
- **Photo display:** photo picker with Small 160×96, Medium 208×144, Large 240×192 (default) and Full 304×240 size choices, full-screen coverage preview, built-in test pattern, letterbox or fill crop, 1-bit high contrast, 1-bit Floyd–Steinberg dithering, grayscale using the SDK's compressed 4-bit stream, invert and 180-degree rotation. The 1-bit path avoids the SDK's generic x/y coordinate bug. No immediate image deletion.
- **Quick cards:** four starter cards, custom saved cards on the iPhone, edit and delete, tap to open on glasses. AI answers and recognized text can be saved intentionally; nothing is auto-saved.
- **Presenter:** paste a talk or notes; page through long text with Previous/Next; change text size and repaginate the complete script; optional 10-second auto-advance while this screen is open.
- **Focus and clock:** 5/15/25-minute focus timer, pause/resume/reset, ten-second HUD refresh cadence to reduce BLE traffic, manual clock or optional live clock that refreshes when the minute changes while this screen remains open. Not a background alarm.
- **Walking routes:** switch between complete walking instructions and a genuine high-contrast MapKit **Street map** sent as a 304×240 1-bit HUD image. Route-line overlays, start/destination and position markers, North indication, Apple map attribution, next-turn vs whole-route views, interactive color map on iPhone, optional periodic GPS-dot updates, manual Next/Previous turns, and separate Next/Previous **text pages**. Automatically chooses a smaller bitmap font if that makes the complete street name visible on the first frame; never silently truncates instructions. Apple Maps handoff for actual live navigation. Not spatially anchored AR, background navigation, or a safety-critical guide.
- **Device settings:** luminance, automatic brightness, gesture detection and readback; orientation calibration, horizontal/vertical text placement sliders, hardware screen-shift diagnostics/reset with confirmation, alignment test.
- **Diagnostics:** battery, firmware, serial, actual reported settings, copy diagnostic output, clear display.
- **Free local AI (default):** The AI selector offers **Auto / iPhone / Mac / Cloud**. Auto uses Apple Foundation Models directly on eligible iOS 26+ Apple Intelligence iPhones; otherwise it uses a paired, free Ollama model on the user's own Mac. It **never selects cloud automatically**. The Mac runs an authenticated Python bridge over trusted home Wi-Fi; no third-party API key is required. In-app AI actions are **Answer, Explain, Summarize, Rewrite, Brainstorm**, plus **Translate**, with full phone answer, Copy, Save as Quick Card, and all HUD pages. Separate Keychain tokens protect local Mac and optional cloud access. The existing Cloudflare/OpenAI relay remains opt-in only. On-device Apple AI requires compatible iPhone hardware, Apple Intelligence enabled, and available OS models. See `local-ai/README.md` for setup and LAN security limitations.
- **Connected Apps:** Calendar and Reminders lists from accounts synced into iOS, opt-in EventKit permissions, upcoming events and incomplete tasks, single-contact system picker, and a manual **Shared Clips** inbox for messages/text copied from Messages, WhatsApp, Gmail, Mail, Notes or Safari. Users must explicitly copy/paste messages; iOS doesn't provide general cross-app inbox access. Saved clips are optional, locally bounded and deletable. Calendar/reminder/message details use the complete paged HUD. See `docs/OPENLENS_CONNECTED_APPS.md`.
- **Read Text (offline OCR):** capture a photo with the iPhone camera or choose an existing photo, recognize printed text locally using Apple's Vision framework, review/edit errors, and send every page through Presenter. Copy text or explicitly save as a local Quick Card. Camera access is permission-gated; photos and recognized text are not sent to the AI relay.
- **Captions:** start/stop live speech recognition, English/French/Spanish/Hindi/Telugu recognition choices as supported by iOS, clear/copy transcript controls, final-session handling, and robust microphone cleanup when audio setup fails.
- **Original demo commands:** kept under Advanced Tools. Commands unsupported by ENGO 3 firmware may not work.

Firmware update authorization is intentionally NOT automatic in this experimental app. Use the official ActiveLook app for firmware updates.

## Verification

- Twenty-nine SwiftPM unit tests, including the user's exact clipped sentence, full-screen bitmap geometry, font-size presets, content preservation, walking street names, per-turn auto-fit, long-word endings and image-size geometry, are covered by `swift test --disable-sandbox`.
- GitHub Actions runs the unsigned iOS simulator build on macOS, 20 Swift core tests on Ubuntu, seven Node tests for the optional Cloudflare relay, and eight Python tests for the local Ollama bridge. Static compilation and these unit tests do **not** prove optical map visibility, physical BLE acknowledgement, camera OCR accuracy, live microphone availability, or a deployed AI server.
- An early simulator build caught two UIKit property collisions with the word 'next'; they were fixed and later simulator builds passed.
- Unit tests cover line wrapping, long words, pagination, unsupported-character handling, Hindi and Telugu romanization, countdown formatting, black-and-white dithering and JSON card serialization.

**Hardware-dependent tests are still required.** The user confirmed text and photos before these additions. The new Connected Apps permissions and integrations, map, OCR, microphone changes, Apple AI availability, local Mac pairing, and optional cloud relay have not been physically/end-to-end tested.  The shared text renderer now queues and coalesces 1-bit bitmap frames to avoid overlapping incomplete BLE transfers, but real transport confirmation requires ENGO 3.  Sending a BLE command or queuing an image is not proof it appeared in the optics. ENGO 3 firmware-specific settings, actual transfer completion, photo orientation, ASR language availability and the appearance of all HUD elements cannot be verified without the physical device. Begin photo testing with the built-in high-contrast test pattern at Large, then compare each selectable size. The Full preset fills nearly the whole microdisplay but may be clipped by the optical field of view.

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
