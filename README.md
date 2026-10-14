# OpenLens for ENGO 3

Real iOS app based on the official ActiveLook demo-app, preserving **all 37 original iOS demo files** and the upstream Xcode project and keeping vendor SDK scanning/Bluetooth/graphics tools. OpenLens HUD is an additional top-level screen.

## Working code added (unverified on device)

- Polished native iOS dark companion HUD with mode switcher and preview.
- Typed text rendered via official ActiveLook SDK drawing commands, from the same connected Glasses object as the demo.
- iPhone microphone speech recognition captions with English, Spanish, French source-language options; starts and stops explicitly.
- AI question workflow that POSTs to a user-configured private HTTPS relay, expects JSON { "text": "short answer" }; no API keys in code.
- Explicit translation request for current text/transcript, with selectable English, Spanish, French, Hindi or Telugu target language, using the same user-configured relay.
- First walking direction from iPhone Location Services, MapKit search and MKDirections (NOT live navigation).

## Pending / limitations

**Not yet compiled in Xcode or tested on ENGO 3.** Legacy SDK from vendor demo uses v4.5.5 and may not expose ENGO 3 color features. Text orientation and font measurements need real-glasses testing. Speech recognition produces source-language captions. An explicit **Translate current transcript** command now sends typed/transcribed text to your own configured HTTPS relay and displays the returned translation. The relay server itself is not included. There is no automatic iMessage access, live translation, AI backend server, phone control, or continuously refreshed navigation. Avoid relying on this first-turn display while driving or cycling.

## Run

1. Clone repository and checkout feature/openlens-ios-foundation.
2. On a Mac install Xcode and CocoaPods.
3. Run: cd ios && pod install
4. Open ios/example.xcworkspace (NOT example.xcodeproj).
5. Configure Apple signing in Xcode; run on real iPhone, grant Bluetooth.
6. Scan, connect the ENGO 3, open **OpenLens HUD** first in the vendor commands menu.
7. Enter a message and tap Show on glasses. Verify the display font/positioning before adding more.

## AI relay protocol

Configure Settings -> Set HTTPS AI relay. POST application/json:
{ "mode": "ai", "text": "What is a parsec?", "target_language": "en" }
Translation example: { "mode": "translate", "text": "Hola, buenos dias", "target_language": "en" }
Response (HTTP 200): { "text": "An astronomical distance unit." }
A sample private Cloudflare Worker relay is now included in the relay/ directory. Deploy it with its two required secrets and enter its URL and client token in Settings. Keep OpenAI secrets on an authenticated, rate-limited server—not in this public repo or phone app. Only send user-consented text.

## Attribution and public references

- Base project copied from https://github.com/ActiveLook/demo-app/tree/main/ios (Apache-2.0; upstream copyright and ios/LICENSE retained).
- ActiveLook SDK dependency: https://github.com/ActiveLook/ios-sdk (Apache-2.0).
- Protocol details: https://github.com/ActiveLook/Activelook-API-Documentation
- Visual reference assets: https://github.com/ActiveLook/Activelook-Visual-Assets (no assets copied without checking their licenses).

## Next milestones

1. Verify real ENGO 3 Bluetooth, HUD rendering, firmware/color compatibility.
2. Improve font/layout caching and drawing stability.
3. Add real iPhone speech-to-translation-to-HUD with user-selected language pair.
4. Add authenticated AI relay; then privacy-filtered supported notifications.
5. Add continuous walking guidance and approved App Intents/Shortcuts actions.

## Deployment and checks

The relay implementation and security/deployment notes live in relay/README.md. Build validation is configured in GitHub Actions on macOS. A passing CI build verifies compilation only, **not** display compatibility or physical-device behavior. Do not put API keys or client tokens in GitHub.
