# OpenLens AI & translation relay

The OpenLens iPhone app does **not** contain a secret OpenAI API key.
This Cloudflare Worker is a small authenticated bridge for **Ask AI** and
**Translate**. It accepts the exact JSON body already sent by the iPhone app:

```json
{"mode":"ai","task":"explain","text":"photosynthesis","target_language":"en"}
```

Or:
```json
{"mode":"translate","text":"Good morning!","target_language":"hi"}
```

It returns `{"text":"..."}`, which OpenLens automatically formats into pages on the ENGO 3.

Supported `task` values for AI requests are `general`, `explain`, `summarize`, `rewrite` and `brainstorm`. Unsupported task names return HTTP 400. The in-app action menu sets this field automatically. Translation uses `mode: "translate"` and supports English, Spanish, French, Hindi, and Telugu. The app also displays the complete result and lets you copy or explicitly save it as a Quick Card.

## One-time setup

You need your own Cloudflare account and OpenAI API credentials. API usage
may be billed by the provider. This repository **does not** contain either
secret and deploying the Worker is not done automatically.

On the Mac, after updating your existing `Engo` checkout:

```bash
cd ~/Documents/Engo/cloudflare/openlens-relay
npm install
npx wrangler login
```

Create a strong **client token**, *separate* from the OpenAI API key:

```bash
openssl rand -hex 32
```

**Copy the random token somewhere private**. You will paste it into the
OpenLens iPhone app later. Do not commit the token to GitHub.

Tell Cloudflare your secrets when prompted (never paste these into a Swift file):

```bash
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put OPENLENS_CLIENT_TOKEN
npm run deploy
```

The Worker requires the `OPENAI_MODEL` name configured in `wrangler.toml`.
The default is `gpt-5.4-mini`; choose another Responses-compatible model if
that model isn't available in your API account.

Cloudflare will display a URL similar to:
`https://openlens-relay.<your-subdomain>.workers.dev`.

Use the **full endpoint path** in the iPhone app:
`https://openlens-relay.<your-subdomain>.workers.dev/openlens`.

On the iPhone: **OpenLens → Ask AI → Set up AI**. Enter that HTTPS URL and
the random **client token**. Then tap **Test AI connection**. You should see
an indication that the relay is online and reports itself configured. Then send a real question to verify your API account and model. The OpenAI API key stays only in Cloudflare secrets.

## How to verify the relay without paying for an AI call

```bash
curl -H "Authorization: Bearer YOUR_CLIENT_TOKEN" \
  https://openlens-relay.YOUR-SUBDOMAIN.workers.dev/openlens/health
```

An authenticated response looks like:
`{"status":"ok","configured":true,"service":"openlens-relay"}`.

If the app reports an HTTP 401, the client token doesn't match. If
`configured` is false, you still need to set the server's API key/model.
Use Cloudflare Worker logs for server errors—avoid logging user prompts or secrets.

## Security and privacy

- Every endpoint requires a strong bearer token (32+ characters), which the
  iPhone stores in the Keychain. The server compares SHA-256 token digests.
- Do **not** paste the OpenAI API key into OpenLens. Only paste the separate
  client token generated above.
- `store: false` is sent to the OpenAI Responses API. Prompts are transmitted
  from the iPhone to your Worker and then to the provider; they are **not**
  exclusively on-device AI.
- Add a Cloudflare Rate Limiting binding named `OPENLENS_RATE_LIMITER`, or use
  Cloudflare's dashboard rate-limit/WAF policies, before sharing the endpoint
  or client token with other people. Never publish that client token.
- This Worker does not enable a general-purpose public AI proxy.
- `GET /openlens/health` requires authorization but does not invoke the AI.
- `POST /openlens` requires an authorized request, enforces input length,
  validates translation destinations and AI action types, and returns sanitized errors.
- HTTPS is required by the iPhone application.
- Passwords, API keys, and client tokens must NOT be committed to GitHub.
  `.dev.vars` and `.env` should remain private.

## Verify tests

```bash
node --test cloudflare/openlens-relay/worker.test.js
```

When run from this folder instead:
```bash
npm test
```

Automated tests stub provider requests; **they cannot prove a live deployment
or API account is configured.**

Source: OpenAI Responses API guide:
https://developers.openai.com/api/docs/guides/text

Source: Cloudflare Workers:
https://developers.cloudflare.com/workers/
