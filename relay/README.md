# OpenLens private AI and translation relay

Cloudflare Worker for the iPhone app. Uses server-side OpenAI key and a separate client authentication token. The iPhone stores that client token in Keychain.

## Deploy with Wrangler

1. Install Node.js and use npx wrangler login.
2. In this relay directory, run: npx wrangler secret put OPENAI_API_KEY
3. Run: npx wrangler secret put OPENLENS_CLIENT_TOKEN
4. Run: npx wrangler deploy
5. In the iPhone OpenLens Settings, use the resulting HTTPS workers.dev URL with /openlens appended, plus your client token.
6. Choose iPhone speech input language; choose translation target in Settings, then tap Translate current transcript.

**Warning:** this is for individual development and is NOT a hardened public multi-user service. Add Cloudflare rate limits, user-based authentication, spending limits and monitoring before public release. Avoid sending sensitive speech. API usage can cost money.

Contract: POST JSON {"mode":"ai" or "translate","text":"question or phrase","target_language":"en"} with Authorization: Bearer [client token]. Returns {"text":"..."}.

Do not commit either secret. Local .dev.vars and .env files are ignored.
