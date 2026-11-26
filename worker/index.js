/**
 * Apex Agent - Cloudflare Workers AI backend
 *
 * Endpoints:
 *   POST /           - Agent tool-calling loop endpoint
 *   POST /auto-reply - Universal auto-reply endpoint
 *
 * All requests require: Authorization: Bearer <token>
 * Token is validated against env.AUTH_TOKEN.
 */

const TOOL_DEFINITIONS = [
  {
    type: "function",
    function: {
      name: "read_notifications",
      description:
        "Read recent device notifications. Silent background tool; prefer this before screen UI tools when notification content is relevant.",
      parameters: {
        type: "object",
        properties: {
          limit: {
            type: "number",
            description: "Maximum number of notifications to return (default 10).",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "reply_notification",
      description:
        "Reply to a notification using its reply action. Silent background tool when a direct reply action is available.",
      parameters: {
        type: "object",
        properties: {
          notificationKey: {
            type: "string",
            description: "The notification key to reply to.",
          },
          message: {
            type: "string",
            description: "The reply message text.",
          },
        },
        required: ["notificationKey", "message"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "set_alarm",
      description:
        "Set an alarm on the device. Silent background tool.",
      parameters: {
        type: "object",
        properties: {
          hour: { type: "number", description: "Hour in 24-hour format (0-23)." },
          minute: { type: "number", description: "Minute (0-59)." },
          message: { type: "string", description: "Alarm label/message." },
        },
        required: ["hour", "minute"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "save_note",
      description:
        "Save a note locally on the device. Silent background tool.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string", description: "Note title." },
          content: { type: "string", description: "Note content/body." },
        },
        required: ["title", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "open_app",
      description:
        "Open an app by package name or app name. Use before screen UI interactions when the target app is not already in the foreground.",
      parameters: {
        type: "object",
        properties: {
          packageOrName: {
            type: "string",
            description: "Android package name or human-readable app name.",
          },
        },
        required: ["packageOrName"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "click_text",
      description:
        "Click a UI element on screen by visible text or content description. Screen UI tool; use only when silent background tools are insufficient.",
      parameters: {
        type: "object",
        properties: {
          target: {
            type: "string",
            description: "Visible text or content description of the element to click.",
          },
        },
        required: ["target"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "type_text",
      description:
        "Type text into a screen field. If targetOrFocused is provided, tries to find and focus that field first; otherwise types into the currently focused field. Screen UI tool.",
      parameters: {
        type: "object",
        properties: {
          targetOrFocused: {
            type: "string",
            description:
              "Target field text/description, or 'focused' to use the currently focused input.",
          },
          text: { type: "string", description: "Text to type." },
        },
        required: ["text"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "scroll_screen",
      description:
        "Scroll the current screen. Screen UI tool; use when needed to find elements.",
      parameters: {
        type: "object",
        properties: {
          direction: {
            type: "string",
            enum: ["up", "down", "left", "right"],
            description: "Scroll direction.",
          },
        },
        required: ["direction"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "press_global",
      description:
        "Perform a global navigation action. Screen UI tool.",
      parameters: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["BACK", "HOME", "RECENTS"],
            description: "Global action to perform.",
          },
        },
        required: ["action"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "ask_confirmation",
      description:
        "Ask the user for confirmation before taking a sensitive or irreversible action. Use when the action could have side effects the user should approve.",
      parameters: {
        type: "object",
        properties: {
          message: {
            type: "string",
            description: "Confirmation question to show the user.",
          },
        },
        required: ["message"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "done",
      description:
        "Finish the agent task and report the final outcome to the user.",
      parameters: {
        type: "object",
        properties: {
          message: {
            type: "string",
            description: "Final user-facing completion message.",
          },
        },
        required: ["message"],
      },
    },
  },
];

const SYSTEM_PROMPT = `You are Apex Agent, an autonomous Android assistant running on the user's device.

Your job is to complete the user's request safely and efficiently by calling tools.

TOOL STRATEGY:
- Prioritize silent background tools before screen UI tools whenever possible.
- Silent/background tools: read_notifications, reply_notification, set_alarm, save_note.
- Screen/UI tools: open_app, click_text, type_text, scroll_screen, press_global. Use these only when background tools cannot accomplish the task.
- Use ask_confirmation before sensitive, destructive, or externally visible actions when user intent is ambiguous.
- When the task is complete, call done with a clear final message.
- Do not hallucinate tool results. Use only information from tool results and user messages.
- If a tool fails, try a reasonable alternative or explain the failure and call done.
- Keep actions minimal and purposeful.`;

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
  });
}

function unauthorized() {
  return jsonResponse({ error: "Unauthorized" }, 401);
}

function badRequest(message) {
  return jsonResponse({ error: message }, 400);
}

function isAuthorized(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const expected = String(env.AUTH_TOKEN || "").trim();
  if (!expected) return false;
  if (!auth.startsWith("Bearer ")) return false;
  const token = auth.slice("Bearer ".length).trim();
  return token.length > 0 && timingSafeEqual(token, expected);
}

function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  if (aBytes.length !== bBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

function sanitizeMessages(messages) {
  if (!Array.isArray(messages)) return [];
  const cleaned = [];
  for (const msg of messages) {
    if (!msg || typeof msg !== "object") continue;
    const role = String(msg.role || "").trim();
    if (!["user", "assistant", "tool", "system"].includes(role)) continue;
    const entry = { role };
    if (typeof msg.content === "string") entry.content = msg.content;
    else if (msg.content == null) entry.content = "";
    else entry.content = JSON.stringify(msg.content);

    if (role === "assistant" && Array.isArray(msg.tool_calls)) {
      entry.tool_calls = msg.tool_calls
        .filter((tc) => tc && typeof tc === "object")
        .map((tc, idx) => {
          const fn = tc.function || {};
          let args = fn.arguments;
          if (args && typeof args !== "string") {
            try {
              args = JSON.stringify(args);
            } catch {
              args = "{}";
            }
          }
          return {
            id: String(tc.id || `call_${idx}`),
            type: "function",
            function: {
              name: String(fn.name || ""),
              arguments: typeof args === "string" ? args : "{}",
            },
          };
        })
        .filter((tc) => tc.function.name);
    }
    if (role === "tool") {
      if (msg.tool_call_id) entry.tool_call_id = String(msg.tool_call_id);
      if (msg.name) entry.name = String(msg.name);
    }
    cleaned.push(entry);
  }
  return cleaned;
}

function extractToolCalls(result) {
  if (!result || typeof result !== "object") return [];
  if (Array.isArray(result.tool_calls)) return result.tool_calls;
  if (result.result && Array.isArray(result.result.tool_calls)) return result.result.tool_calls;
  if (result.response && Array.isArray(result.response.tool_calls)) return result.response.tool_calls;
  // Some models embed tool calls in choices-style structures.
  if (Array.isArray(result.choices)) {
    for (const choice of result.choices) {
      const msg = choice && choice.message;
      if (msg && Array.isArray(msg.tool_calls)) return msg.tool_calls;
    }
  }
  return [];
}

function extractAssistantMessage(result) {
  if (!result || typeof result !== "object") return "";
  if (typeof result.response === "string") return result.response;
  if (typeof result.result === "string") return result.result;
  if (typeof result.text === "string") return result.text;
  if (result.result && typeof result.result.response === "string") return result.result.response;
  if (Array.isArray(result.choices)) {
    for (const choice of result.choices) {
      const msg = choice && choice.message;
      if (msg && typeof msg.content === "string" && msg.content.trim()) return msg.content;
    }
  }
  return "";
}

function normalizeToolCalls(rawToolCalls) {
  return rawToolCalls
    .filter((tc) => tc && typeof tc === "object")
    .map((tc, idx) => {
      const fn = tc.function || tc;
      const name = String(fn.name || tc.name || "").trim();
      let args = fn.arguments ?? tc.arguments ?? {};
      if (typeof args === "string") {
        try {
          args = JSON.parse(args);
        } catch {
          args = { _raw: args };
        }
      }
      if (!args || typeof args !== "object" || Array.isArray(args)) {
        args = {};
      }
      return {
        id: String(tc.id || `call_${Date.now()}_${idx}`),
        type: "function",
        function: {
          name,
          arguments: args,
        },
      };
    })
    .filter((tc) => tc.function.name);
}

async function handleAgent(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return badRequest("Invalid JSON body.");
  }

  const incomingMessages = sanitizeMessages(body.messages);
  if (incomingMessages.length === 0) {
    return badRequest("messages must be a non-empty array.");
  }

  const model = String(body.model || env.DEFAULT_MODEL || "@hf/nousresearch/hermes-2-pro-mistral-7b").trim();
  const screenState = typeof body.screenState === "string" ? body.screenState : "";
  const maxTokens = Math.min(Math.max(Number(body.max_tokens) || 1024, 256), 2048);

  const messages = [
    { role: "system", content: SYSTEM_PROMPT },
  ];
  if (screenState) {
    messages.push({
      role: "system",
      content: `Current screen state JSON (may be truncated):\n${screenState.slice(0, 12000)}`,
    });
  }
  for (const m of incomingMessages) {
    // Avoid duplicating system prompt if client sent one.
    if (m.role === "system") continue;
    messages.push(m);
  }

  let aiResult;
  try {
    aiResult = await env.AI.run(model, {
      messages,
      tools: TOOL_DEFINITIONS,
      max_tokens: maxTokens,
    });
  } catch (err) {
    const message = err && err.message ? err.message : String(err);
    return jsonResponse({ error: "AI inference failed", detail: message }, 502);
  }

  const rawToolCalls = extractToolCalls(aiResult);
  const toolCalls = normalizeToolCalls(rawToolCalls);
  const assistantMessage = extractAssistantMessage(aiResult);

  if (toolCalls.length > 0) {
    return jsonResponse({
      type: "tool_calls",
      tool_calls: toolCalls,
      assistant_message: assistantMessage || "",
      model,
    });
  }

  const finalMessage = assistantMessage && assistantMessage.trim()
    ? assistantMessage.trim()
    : "I could not determine the next action. Please try rephrasing your request.";

  return jsonResponse({
    type: "final",
    message: finalMessage,
    model,
  });
}

function buildAutoReplyPrompt(input) {
  const appName = String(input.appName || "Unknown App");
  const senderName = String(input.senderName || "Unknown Sender");
  const messageText = String(input.messageText || "");
  const isGroup = Boolean(input.isGroup);
  const globalRule = String(input.globalRule || "").trim();
  const customRule = String(input.customRule || "").trim();

  return `You generate short, natural, context-appropriate reply suggestions for mobile messaging notifications.

Return ONLY valid JSON with this exact shape:
{"reply":"...","skip":false}

Rules:
- "reply" must be a concise, polite, human-sounding message the user could send.
- Set "skip": true only when the message should not be auto-replied to (spam, OTP/code, verification, transactional alerts, empty/unclear, or when replying would be inappropriate).
- If "skip" is true, set "reply" to "".
- Do not include markdown, code fences, or extra keys.
- Never mention that you are an AI.

Context:
- App: ${appName}
- Sender: ${senderName}
- Group chat: ${isGroup ? "yes" : "no"}
- Global rule: ${globalRule || "(none)"}
- App/contact custom rule: ${customRule || "(none)"}
- Incoming message: ${messageText}`;
}

function parseAutoReplyModelOutput(text) {
  const raw = String(text || "").trim();
  if (!raw) return { reply: "", skip: true };

  // Try direct JSON parse first.
  const candidates = [raw];
  const firstBrace = raw.indexOf("{");
  const lastBrace = raw.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
    candidates.push(raw.slice(firstBrace, lastBrace + 1));
  }

  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object") {
        const skip = Boolean(parsed.skip);
        let reply = typeof parsed.reply === "string" ? parsed.reply.trim() : "";
        if (skip) reply = "";
        if (!skip && !reply) {
          return { reply: "", skip: true };
        }
        return { reply, skip };
      }
    } catch {
      // continue
    }
  }

  // Fallback heuristic: if the model returned plain text, treat it as reply unless it looks like a refusal.
  const lowered = raw.toLowerCase();
  if (
    lowered.includes("cannot reply") ||
    lowered.includes("can't reply") ||
    lowered.includes("should not reply") ||
    lowered.includes("no reply")
  ) {
    return { reply: "", skip: true };
  }
  // Strip wrapping quotes
  const cleaned = raw.replace(/^"|"$/g, "").trim();
  if (!cleaned) return { reply: "", skip: true };
  return { reply: cleaned.slice(0, 500), skip: false };
}

async function handleAutoReply(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return badRequest("Invalid JSON body.");
  }

  const appName = typeof body.appName === "string" ? body.appName : "";
  const senderName = typeof body.senderName === "string" ? body.senderName : "";
  const messageText = typeof body.messageText === "string" ? body.messageText : "";
  const isGroup = Boolean(body.isGroup);
  const globalRule = typeof body.globalRule === "string" ? body.globalRule : "";
  const customRule = typeof body.customRule === "string" ? body.customRule : "";

  if (!messageText.trim()) {
    return jsonResponse({ reply: "", skip: true, reason: "empty_message" });
  }

  const model = String(body.model || env.DEFAULT_MODEL || "@hf/nousresearch/hermes-2-pro-mistral-7b").trim();
  const prompt = buildAutoReplyPrompt({
    appName,
    senderName,
    messageText,
    isGroup,
    globalRule,
    customRule,
  });

  let aiResult;
  try {
    aiResult = await env.AI.run(model, {
      messages: [
        {
          role: "system",
          content:
            "You output only JSON. Never output markdown or commentary.",
        },
        { role: "user", content: prompt },
      ],
      max_tokens: 256,
    });
  } catch (err) {
    const message = err && err.message ? err.message : String(err);
    return jsonResponse({ error: "AI inference failed", detail: message }, 502);
  }

  const text = extractAssistantMessage(aiResult);
  const parsed = parseAutoReplyModelOutput(text);
  return jsonResponse(parsed);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return jsonResponse({ ok: true }, 200);
    }

    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    if (!isAuthorized(request, env)) {
      return unauthorized();
    }

    if (url.pathname === "/" || url.pathname === "/agent") {
      return handleAgent(request, env);
    }

    if (url.pathname === "/auto-reply") {
      return handleAutoReply(request, env);
    }

    return jsonResponse({ error: "Not found" }, 404);
  },
};
