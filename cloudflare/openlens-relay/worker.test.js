import test from "node:test";
import assert from "node:assert/strict";
import worker, { extractResponseText } from "./worker.js";

const token = "this-is-a-demo-only-token-with-more-than-32-characters";
const env = { OPENLENS_CLIENT_TOKEN: token, OPENAI_API_KEY: "test-api-key", OPENAI_MODEL: "test-model" };
const auth = { Authorization: "Bearer " + token, "Content-Type": "application/json" };
function post(payload, headers = auth) {
  return new Request("https://openlens.example/openlens", { method: "POST", headers, body: JSON.stringify(payload) });
}
async function body(response) { return response.json(); }

test("requires a client token for health and AI", async () => {
  assert.equal((await worker.fetch(new Request("https://openlens.example/openlens/health"), env)).status, 401);
  assert.equal((await worker.fetch(post({ mode: "ai", text: "Hello" }, {}), env)).status, 401);
  const ok = await worker.fetch(new Request("https://openlens.example/openlens/health", { headers: auth }), env);
  assert.equal(ok.status, 200);
  assert.deepEqual(await body(ok), { status: "ok", configured: true, service: "openlens-relay" });
});

test("rejects invalid methods and malformed requests", async () => {
  assert.equal((await worker.fetch(post({ mode: "ai", text: "" }), env)).status, 400);
  assert.equal((await worker.fetch(post({ mode: "translate", text: "Hi", target_language: "zz" }), env)).status, 400);
  assert.equal((await worker.fetch(post({ mode: "ai", text: "x".repeat(3001) }), env)).status, 400);
  assert.equal((await worker.fetch(post({ mode: "ai", text: "Hello", task: "private-secret-mode" }), env)).status, 400);
  assert.equal((await worker.fetch(new Request("https://openlens.example/other", { headers: auth }), env)).status, 404);
  assert.equal((await worker.fetch(new Request("https://openlens.example/openlens", { method: "PUT", headers: auth }), env)).status, 405);
});

test("health reports missing upstream configuration without leaking secrets", async () => {
  const response = await worker.fetch(new Request("https://openlens.example/openlens/health", { headers: auth }),
    { OPENLENS_CLIENT_TOKEN: token });
  assert.deepEqual(await body(response), { status: "ok", configured: false, service: "openlens-relay" });
});

test("extracts text across Responses API output items", () => {
  assert.equal(extractResponseText({ output: [
    { type: "reasoning", content: [] },
    { type: "message", content: [ { type: "output_text", text: "First" } ] },
    { type: "message", content: [ { type: "output_text", text: "Second" } ] }
  ] }), "First\nSecond");
});

test("sends guarded AI request with stateless mode", async () => {
  const realFetch = globalThis.fetch;
  let sent;
  globalThis.fetch = async (_url, request) => {
    sent = JSON.parse(request.body);
    assert.equal(request.headers.Authorization, "Bearer test-api-key");
    return new Response(JSON.stringify({ output: [
      { type: "message", content: [{ type: "output_text", text: "Clear answer." }] }
    ]}), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  try {
    const result = await worker.fetch(post({ mode: "ai", text: "What is 1+1?" }), env);
    assert.equal(result.status, 200);
    assert.deepEqual(await body(result), { text: "Clear answer." });
    assert.equal(sent.model, "test-model");
    assert.equal(sent.store, false);
    assert.equal(sent.input, "What is 1+1?");
  } finally { globalThis.fetch = realFetch; }
});

test("translation specifies the requested language and protects street names", async () => {
  const realFetch = globalThis.fetch;
  let sent;
  globalThis.fetch = async (_url, request) => {
    sent = JSON.parse(request.body);
    return new Response(JSON.stringify({ output: [
      { type: "message", content: [{ type: "output_text", text: "Hola" }] }
    ]}), { status: 200 });
  };
  try {
    const response = await worker.fetch(post({ mode: "translate", text: "Hello", target_language: "es" }), env);
    assert.equal(response.status, 200);
    assert.match(sent.instructions, /Spanish/);
    assert.match(sent.instructions, /street names/);
  } finally { globalThis.fetch = realFetch; }
});


test("AI task modes produce specific instructions without changing secret handling", async () => {
  const originalFetch = globalThis.fetch;
  const instructions = new Map();
  globalThis.fetch = async (_url, options) => {
    const json = JSON.parse(options.body);
    instructions.set(json.input, json.instructions);
    return new Response(JSON.stringify({
      output: [{ type: "message", content: [{ type: "output_text", text: "Completed." }] }]
    }), { status: 200 });
  };
  try {
    for (const task of ["general", "explain", "summarize", "rewrite", "brainstorm"]) {
      const response = await worker.fetch(post({ mode: "ai", text: task, task }), env);
      assert.equal(response.status, 200);
    }
    assert.match(instructions.get("general"), /Answer/);
    assert.match(instructions.get("explain"), /Explain/);
    assert.match(instructions.get("summarize"), /key facts/);
    assert.match(instructions.get("rewrite"), /Rewrite/);
    assert.match(instructions.get("brainstorm"), /4 practical/);
    for (const instructionsText of instructions.values()) {
      assert.doesNotMatch(instructionsText, /test-api-key|this-is-a-demo-only-token/);
      assert.match(instructionsText, /smart-glasses/);
    }
  } finally { globalThis.fetch = originalFetch; }
});
