/**
 * Velour Dental Studio — Cloudflare Worker
 *
 * Exposes an authenticated AI chat endpoint backed by Workers AI.
 *
 * Bindings (see wrangler.toml):
 *   AI         Workers AI binding  ([ai] binding = "AI")
 *   AUTH_TOKEN secret             bearer token required on /api/*
 *
 * Routes:
 *   GET  /health     -> public liveness/readiness probe
 *   POST /api/chat   -> { messages: [{role, content}] } or { prompt: "..." }
 *   OPTIONS *        -> CORS preflight
 */

const MODEL = "@cf/meta/llama-4-scout-17b-16e-instruct";

const SYSTEM_PROMPT = [
  "You are the front-desk assistant for Velour Dental Studio, a dental practice.",
  "Help visitors with questions about services, opening hours, booking an appointment,",
  "and general dental-care guidance. Keep answers short, warm and practical.",
  "Never diagnose a condition, never recommend prescription medication, and always",
  "advise seeing a dentist for anything urgent such as severe pain, swelling, bleeding",
  "that will not stop, or dental trauma. If you do not know a practice-specific detail",
  "such as an exact price or address, say so and suggest contacting the studio directly.",
].join(" ");

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...CORS_HEADERS },
  });

/** Constant-time-ish bearer token check. */
async function isAuthorized(request, env) {
  if (!env.AUTH_TOKEN) return false;

  const header = request.headers.get("authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) return false;

  const encoder = new TextEncoder();
  const [given, expected] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(match[1].trim())),
    crypto.subtle.digest("SHA-256", encoder.encode(env.AUTH_TOKEN)),
  ]);
  const a = new Uint8Array(given);
  const b = new Uint8Array(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Workers AI responses vary by model family; pull the text out safely. */
function extractReply(result) {
  if (typeof result === "string") return result;
  if (!result) return "";

  if (typeof result.response === "string") return result.response;
  if (typeof result.result?.response === "string") return result.result.response;

  const choice = result.choices?.[0]?.message?.content;
  if (typeof choice === "string") return choice;

  if (Array.isArray(result.output)) {
    return result.output
      .flatMap((item) => (Array.isArray(item?.content) ? item.content : []))
      .map((part) => (typeof part?.text === "string" ? part.text : ""))
      .join("");
  }

  return "";
}

/** Normalise the request body into a Workers AI messages array. */
function buildMessages(body) {
  if (Array.isArray(body?.messages)) {
    const messages = body.messages
      .filter((m) => m && typeof m.content === "string" && m.content.trim())
      .map((m) => ({
        role: ["system", "assistant", "user"].includes(m.role) ? m.role : "user",
        content: m.content.slice(0, 4000),
      }))
      .slice(-20);

    if (messages.length === 0) return null;
    return [{ role: "system", content: SYSTEM_PROMPT }, ...messages];
  }

  if (typeof body?.prompt === "string" && body.prompt.trim()) {
    return [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: body.prompt.slice(0, 4000) },
    ];
  }

  return null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/")) {
      return json({
        ok: true,
        service: "velour-dental-studio",
        model: MODEL,
        aiBinding: Boolean(env.AI),
      });
    }

    if (url.pathname !== "/api/chat") {
      return json({ error: "Not found" }, 404);
    }

    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    if (!(await isAuthorized(request, env))) {
      return json({ error: "Unauthorized" }, 401);
    }

    if (!env.AI) {
      return json({ error: "AI binding is not configured" }, 503);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    const messages = buildMessages(body);
    if (!messages) {
      return json({ error: "Send { messages: [...] } or { prompt: \"...\" }" }, 400);
    }

    const maxTokens = Math.min(Math.max(Number(body?.max_tokens) || 512, 32), 1024);

    try {
      const result = await env.AI.run(MODEL, { messages, max_tokens: maxTokens });
      const reply = extractReply(result);

      if (!reply) {
        return json({ error: "Empty AI response", raw: result }, 502);
      }

      return json({ model: MODEL, reply });
    } catch (error) {
      return json({ error: "AI request failed", detail: String(error?.message ?? error) }, 502);
    }
  },
};
