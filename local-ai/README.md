# OpenLens Free Local AI — No OpenAI Key Required

OpenLens now defaults to **free local AI**. Your existing ENGO 3 text,
photo, OCR, walking directions and captions continue to work independently
of any language model.

There are two local ways to answer questions, summarize, explain, rewrite,
brainstorm or translate:

## 1. iPhone AI (no Mac needed)

OpenLens uses Apple's [Foundation Models](https://developer.apple.com/documentation/foundationmodels/)
on the iPhone when the framework and model are available. No API key, usage
billing, Cloudflare deployment, or network connection is needed.

**Requirements:** iOS 26 or later, an Apple Intelligence-compatible device,
Apple Intelligence enabled in iPhone Settings, and the model fully downloaded.
This excludes older iPhones, even though they can still run the rest of
OpenLens. Supported languages are determined by Apple's model; Hindi/Telugu
may be unavailable on some iOS versions.

On OpenLens choose **Ask AI → Auto** (recommended), or **iPhone** to require
on-device AI. Tap **Check iPhone AI** to see availability. If you select
iPhone and it is unavailable, OpenLens explains why instead of silently using
a cloud service.

## 2. Free Mac AI — Ollama (works with older iPhones)

Your **M1 MacBook Air** can run an open-weight model locally using
[Ollama](https://ollama.com/download/mac). This option requires no model
subscription or API key. You only download a model once; inference happens
on the Mac. Your iPhone communicates with OpenLens's small local server
over a **trusted private Wi-Fi network**. The Mac must stay powered on,
awake, running Ollama, and on the same network as your iPhone.

### Mac setup

1. Install Ollama from https://ollama.com/download/mac and open it.
2. In the Mac Terminal, download the 3B Qwen 3 instruction model once:

   ```bash
   ollama pull qwen3:4b-instruct
   ```

   This downloads model weights; after that, ordinary inference is local.
   The Qwen3 4B-instruct weights are approximately 2.5 GB. A few gigabytes of disk space and several gigabytes of available
   memory may be needed. 4B local models are smaller and usually less capable than large
   cloud models, and translations might be imperfect.

3. Start the **OpenLens Mac bridge**. Keep this Terminal window open:

   ```bash
   cd ~/Documents/Engo/local-ai
   python3 openlens_ollama_bridge.py --host 0.0.0.0
   ```

   The bridge uses only the Python standard library (Python 3.10 or newer
   recommended); it does not need `pip install` or an OpenAI account.

4. The Terminal displays a **local pairing token**. This is **not** an API
   key. Copy the token for your iPhone. OpenLens saves it separately in
   iPhone Keychain. The token also lives in
   `~/.openlens/local-ai-token` on your Mac with file permissions 0600.
   Never put it in GitHub or share screenshots that show it.

5. In another Terminal window, find your Mac Wi-Fi address:

   ```bash
   ipconfig getifaddr en0
   ```

   For example, if it prints `192.168.1.25`, the phone endpoint is:

   ```text
   http://192.168.1.25:8765/openlens
   ```

6. On the iPhone, open **OpenLens → Ask AI → Mac** (or Auto when iPhone
   AI is not supported), then tap **Pair local Mac**. Paste the endpoint
   above and the pairing token. Tap **Test local Mac**. The app should
   report that Ollama is ready.
7. Ask **"Explain photosynthesis simply."** The answer should appear on
   the phone and glasses, with Previous/Next pages where needed.

### Local connection and privacy

This early local bridge uses **unencrypted HTTP on your home network**
because setting up trusted HTTPS certificates for private LAN IP addresses
is substantially more involved. The bridge requires a long random bearer
token, but **Wi-Fi traffic and the pairing token are not encrypted in transit**.

**Use it only on a trusted private home Wi-Fi or an isolated personal hotspot.**
Never use public Wi-Fi, never port-forward port 8765, and never expose this
server to the internet. For stronger privacy when out of the house, use the
Apple on-device model if your iPhone supports it, or do not use remote AI.
If possible, use WPA2/WPA3 Wi-Fi and turn the server off when finished.

The bridge reaches Ollama only at `127.0.0.1:11434` on your Mac.
It does **not** forward text to the internet. It does not store prompts,
messages, or chat history. The iPhone talks to the Mac only after you
tap a local AI feature. Mac Firewall or iPhone Local Network permissions
may need to allow this connection.

### Troubleshooting

- **Check iPhone AI says unavailable:** iPhone or iOS may be ineligible,
  Apple Intelligence disabled, language unsupported, or model still
  downloading. Select **Mac** instead.
- **Mac connection timed out:** Both devices must be on the same trusted
  Wi-Fi; keep Ollama and the Python bridge running, check the Mac Wi-Fi IP,
  and allow OpenLens access in iOS Settings → Privacy & Security → Local Network.
- **Mac health responds but configured is false:** Run
  `ollama pull qwen3:4b-instruct`, then recheck; ensure Ollama itself is running.
- **Wrong token:** Copy the full token from the Mac Terminal. Stop the
  bridge before rotating the token file.
- **Slow responses:** Smaller models are usually quicker; try
  `ollama pull qwen3:1.7b` and start the bridge with
  `--model qwen3:1.7b` (this may reduce quality).
- **App says local connection blocked:** Only local private IPv4 addresses
  or a `.local` Mac hostname are accepted. The endpoint must end in
  `/openlens`.
- **On the go without Mac:** Use Apple AI on a supported iPhone.
  Otherwise, you can still use the app's non-AI features.

### Stop local AI

Press **Ctrl+C** in the Terminal running the bridge. Quit Ollama to
free memory if desired. Re-pairing is not required next time if the IP
address and token stay the same.

## Automated tests

Run on a Mac:

```bash
cd ~/Documents/Engo
python3 -m unittest discover -s local-ai -p 'test_*.py' -v
```

The tests use a **mock Ollama response**; they verify authentication,
health requests, AI task forwarding, translations and input validation
without downloading a model or requiring internet.

## Optional cloud choice

OpenLens retains the prior Cloudflare/OpenAI relay **only when the user
explicitly selects Cloud**. Auto never falls back to it. The existing
cloud relay is not needed to run iPhone or Mac local AI.

Official references:
- [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels/)
- [Ollama macOS](https://ollama.com/download/mac)
- [Ollama local chat API](https://docs.ollama.com/api/chat)
