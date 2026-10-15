// Cloudflare Workers companion for OpenLens (no API key in the iPhone app).
// A strong bearer token is required on every request, even the health endpoint.
// Store OPENAI_API_KEY and OPENLENS_CLIENT_TOKEN via "wrangler secret put".
// OPENAI_MODEL is set in wrangler.toml. No conversations are logged by this Worker.

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};
function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}
async function equalToken(value, expected) {
  if (!value || !expected || expected.length < 32) return false;
  const encoder = new TextEncoder();
  const digests = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(value)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const x = new Uint8Array(digests[0]);
  const y = new Uint8Array(digests[1]);
  let difference = 0;
  for (let i = 0; i < x.length; i++) difference |= x[i] ^ y[i];
  return difference === 0;
}
export function extractResponseText(response) {
  if (!Array.isArray(response?.output)) return "";
  return response.output
    .filter((item) => item?.type === "message" && Array.isArray(item.content))
    .flatMap((item) => item.content)
    .filter((part) => part?.type === "output_text" && typeof part.text === "string")
    .map((part) => part.text)
    .join("\n")
    .trim();
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/openlens" && url.pathname !== "/openlens/health") {
      return json({ error: "Not found" }, 404);
    }
    const authorization = request.headers.get("Authorization") || "";
    const supplied = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!(await equalToken(supplied, env.OPENLENS_CLIENT_TOKEN))) {
      return json({ error: "Invalid relay token" }, 401);
    }
    const configured = Boolean(env.OPENAI_API_KEY && env.OPENAI_MODEL);
    if (request.method === "GET") {
      return json({ status: "ok", configured, service: "openlens-relay" });
    }
    if (request.method !== "POST" || url.pathname !== "/openlens") {
      return json({ error: "Method not allowed" }, 405);
    }
    if (!configured) return json({ error: "Server missing AI credentials or model" }, 503);

    const claimedLength = Number(request.headers.get("Content-Length") || "0");
    if (claimedLength > 8192) return json({ error: "Request too large" }, 413);
    let payload;
    try {
      const raw = await request.text();
      if (raw.length > 8192) return json({ error: "Request too large" }, 413);
      payload = JSON.parse(raw);
    } catch {
      return json({ error: "Invalid JSON" }, 400);
    }

    const mode = payload?.mode;
    const prompt = typeof payload?.text === "string" ? payload.text.trim() : "";
    const target = payload?.target_language;
    const task = payload?.task ?? "general";
    const allowedTasks = ["general", "explain", "summarize", "rewrite", "brainstorm"];
    if (mode === "ai" && !allowedTasks.includes(task)) {
      return json({ error: "Invalid AI task" }, 400);
    }
    if (!["ai", "translate"].includes(mode) || !prompt || prompt.length > 3000) {
      return json({ error: "Send mode=ai or translate and 1-3000 characters" }, 400);
    }
    if (mode === "translate" && !["en", "es", "fr", "hi", "te"].includes(target)) {
      return json({ error: "Unsupported translation language" }, 400);
    }
    // Enable a Cloudflare Worker Rate Limiting binding called OPENLENS_RATE_LIMITER
    // before allowing others to use your endpoint.
    if (env.OPENLENS_RATE_LIMITER) {
      const key = request.headers.get("CF-Connecting-IP") || "anonymous";
      const outcome = await env.OPENLENS_RATE_LIMITER.limit({ key });
      if (!outcome.success) return json({ error: "Too many requests; try later" }, 429);
    }

    const names = { en: "English", es: "Spanish", fr: "French", hi: "Hindi", te: "Telugu" };
    const base = "You are OpenLens, a compact smart-glasses assistant. " +
      "Answer clearly in plain text without tables. Prefer 120 words or fewer " +
      "unless an accurate answer requires more. Be careful with numbers, " +
      "names and factual claims. Never pretend to see the user's surroundings, " +
      "read their camera, know their current location or browse live data.";
    const taskInstructions = {
      general: "Answer the person's question directly, with useful next steps where relevant.",
      explain: "Explain the concept in simple, accurate language with one relatable example.",
      summarize: "Summarize the supplied text, preserving named entities, key facts, figures and caveats. Do not invent facts.",
      rewrite: "Rewrite the supplied text for clarity and natural tone. Keep the meaning and any important constraints.",
      brainstorm: "Suggest 4 practical, distinct ideas, each one sentence long. Avoid unsupported claims.",
    };
    const instructions = mode === "translate"
      ? "Translate the user's text faithfully into " + names[target] +
        ". Return only the translation; preserve street names, numbers, and proper nouns."
      : base + " " + taskInstructions[task];
    let upstream;
    try {
      upstream = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer " + env.OPENAI_API_KEY,
        },
        body: JSON.stringify({
          model: env.OPENAI_MODEL,
          store: false,
          max_output_tokens: 600,
          instructions,
          input: prompt,
        }),
        signal: AbortSignal.timeout(29000),
      });
    } catch {
      return json({ error: "The AI service did not respond in time" }, 504);
    }
    if (!upstream.ok) {
      // Never return the raw upstream error: it may contain sensitive metadata.
      const message = upstream.status === 429
        ? "AI quota or rate limit reached"
        : upstream.status === 401 || upstream.status === 403
          ? "The server's AI credentials were rejected"
          : "The AI provider returned an error";
      return json({ error: message, status: upstream.status }, upstream.status === 429 ? 429 : 502);
    }
    let result;
    try { result = await upstream.json(); }
    catch { return json({ error: "Unexpected AI response format" }, 502); }
    const text = extractResponseText(result);
    if (!text) return json({ error: "AI returned no displayable text" }, 502);
    return json({ text: text.slice(0, 4000) });
  },
};
