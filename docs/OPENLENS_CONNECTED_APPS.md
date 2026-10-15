# OpenLens Connected Apps

This extends the **existing** OpenLens ENGO 3 iPhone application without replacing its working text, photo, walking map, Bluetooth or local AI features.

## Incoming message alerts (optional; Shortcuts integration)

Unlike an Android Notification Listener, OpenLens cannot automatically inspect
all iPhone apps' notifications. It has a **user-configured App Intent**
(`Forward Message Alert to OpenLens`) for Apple's **Shortcuts** app.

- Turn on **Connected Apps → Message Alerts → Allow incoming Shortcut alerts**.
  This is **off by default**. Only messages explicitly forwarded by your own
  automations are accepted. No message database is queried.
- The default optical preview contains **sender and app name only**. To allow
  message contents on the glasses, manually enable the **Show message content**
  switch. The setting also controls what gets stored locally. Previously saved
  content isn't silently rewritten when the switch is disabled; delete history.
- **Set up Messages:** Shortcuts → Automation → + → Message (received) → choose
  sender(s) and optionally message criteria → Run Immediately (if available).
  Add the OpenLens action **Forward Message Alert to OpenLens**. Map the
  automation's Sender field into `Sender`, its Message Content/Shortcut Input
  into `Message Content`, and set `Source App` to `Messages`.
- **Other app notifications:** Newer iOS Shortcuts versions may expose a
  Notification automation triggered by a selected app (such as WhatsApp).
  You can pass only the fields that Shortcuts exposes for that notification.
  Notifications from apps with concealed text might contain sender/title only.
- **Test:** From OpenLens → Message Alerts, enable alerts and press
  **Send a test notification to my glasses**. This displays a simulated
  message through the same Presenter HUD path. It does **not** prove a real
  automation can launch the app or update Bluetooth while backgrounded.
- The action can bring OpenLens to the foreground; pending alerts appear only
  when the app is active, the connection is available, and the OpenLens home
  screen becomes visible. Neither iOS nor ActiveLook guarantees a silent
  Bluetooth display update when the app is suspended or disconnected.
- Delete history in Message Alerts. Only the last 12 forwarded alerts are
  retained, with up to 600 characters each if content storage is enabled.
- Notification content stays local to your iPhone by this feature; it is not
  forwarded to the local AI or Cloudflare relay. Avoid using this for sensitive
  texts or verification codes.

**Not a true cross-app notification listener:** Apple's Accessory Notifications
framework supports forwarding in the EU only for qualifying devices/users.
ANCS is a BLE accessory protocol requiring firmware support as an ANCS client;
the existing ActiveLook SDK's Battery/Flow/Gesture notifications are not
incoming iMessage alerts. Those APIs are not silently available to our app.

Apple Shortcuts references:
- https://support.apple.com/guide/shortcuts/communication-triggers-apdd711f9dff/ios
- https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios
- https://developer.apple.com/documentation/appintents/

## What really connects

| iPhone source | Available in OpenLens | Permission / limitation |
| --- | --- | --- |
| Apple Calendar | Events for the next 7 days; tap to read full details on glasses. | iOS Calendar **full-access** permission, requested only after pressing Connect. OpenLens does not edit events. Synced Google/Outlook calendars are included if they already appear in Apple's Calendar on the iPhone. |
| Apple Reminders | Incomplete tasks sorted by due date; tap to read on glasses. | iOS Reminders **full-access** permission, requested only after pressing Connect. OpenLens does not complete or edit tasks. |
| iPhone Contacts | Choose one person, show their name and selected phone/email on ENGO 3. | Apple's single-contact picker; OpenLens never imports the entire contacts database. |
| iMessage/SMS (Messages) | Shared Clips for user-selected text; optional user-created Shortcuts message automation for incoming alerts. | **No automatic inbox access.** Shortcuts must be configured by the user; background BLE display is not guaranteed. |
| WhatsApp, Signal, Telegram | Copy text you select and paste it as a clip. | **No automatic inbox access.** Requires a user-initiated copy/paste. |
| Gmail, Apple Mail, Outlook | Copy email text and paste into Shared Clips. | This does **not** connect an email inbox; account OAuth is a separate integration that is not included. |
| Notes, Safari, websites | Copy text or a URL, paste into Shared Clips, then show it. | User-initiated import, not automatic browsing or background monitoring. |

### How to use

1. Install the latest OpenLens GitHub branch, start the iPhone app and connect ENGO 3.
2. From the home dashboard tap **Connected Apps**.
3. Tap **Calendar** or **Reminders** and then **Connect**. Grant access if you want those lists; otherwise the app leaves them disconnected. Tap a calendar event or task to open the page-by-page ENGO Presenter. Swipe down to refresh; the view also reacts to EventKit changes while open.
4. To read a message, open Messages/WhatsApp/Mail, select the text, tap **Copy**, return to **Connected Apps → Shared Clips**, and tap **Paste clipboard**. You can edit it and display **all pages** on the glasses.
5. Tapping **Save this clip** optionally keeps a copy only in the app's local device storage. No clips are saved automatically. Saved items have individual delete actions and a confirmed Delete All action. **Avoid importing passwords, bank codes, and sensitive conversations.**
6. Tap **Choose a contact** to select one contact from Apple's system picker, then **Show selected contact on glasses**.

### Security and design

- OpenLens **never reads the clipboard in the background**. It accesses pasted text only after you tap Paste; iOS may also ask for paste permission.
- No automatic notifications, call monitoring, messages scanning, iMessage history, or WhatsApp listener is claimed.
- Calendar and Reminders permissions are never requested on app launch. iOS 17+ uses the supported EventKit full-access APIs; iOS 15–16 uses the legacy APIs and matching Info.plist purpose descriptions.
- The Connected Apps screens don't feed any content automatically to the AI model or a cloud service; you choose exactly what to display.
- Saved clips are in the app's local UserDefaults store (not end-to-end encrypted); protect the phone with a passcode and delete clips you no longer need. Their storage is bounded to 30 clips, each up to 4,000 characters. The preview you paste remains longer if needed, though saving truncates to 4,000 with an explicit notice.
- Contact picker and clipboard imports don't require blanket Contacts or Messaging database access. Only selected contact details are held in memory for that screen.
- Showing a contact, event, reminder, or clip uses the **existing paged bitmap HUD**. It doesn't change the photo renderer, SDK firmware, or Bluetooth connection code.
- A true iOS Share Extension could provide a nicer Send to OpenLens option later, but it requires an additional signed app extension and possibly App Group setup. It isn't claimed to be included here.

### On-device checklist

- Calendar: Connect → permission prompt → 7-day event list → open a long event with a location → use Next and Previous in Presenter. Deny permission once and confirm the app explains how to enable access.
- Reminders: Connect → incomplete tasks sorted by due date → test an undated task and a long title → Presenter pages. Verify OpenLens does **not** mark any reminder complete.
- Contacts: choose one contact and display it; verify no other contacts become visible automatically.
- Messages: copy a long, multi-line message, paste, display pages, save and delete. Ensure original Messages data isn't changed.
- Paste permission: test denied clipboard permission or nontext clipboard. The app should report an explanation, not crash.
- Leave Connected Apps or disconnect the glasses; no background message monitoring or other unsolicited on-glasses content should occur.

### References

- Apple EventKit — https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- EventKit migration — https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels
- Apple contact picker — https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller
- App sandbox — https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
