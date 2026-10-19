"use strict";

/**
 * Creative AAC — Cloud Functions.
 *
 * One turn of the co-creation conversation is proxied to Claude. The Anthropic
 * API key lives ONLY here, as a secret — it is never shipped in the app.
 *
 * Two entry points share the same core:
 *  • `companionTurn`     — Firebase callable (for when the app adopts the
 *                          Firebase SDK; requires an authenticated caller).
 *  • `companionTurnHttp` — plain HTTPS endpoint the Flutter app can call with
 *                          the `http` package, guarded by the APP_KEY secret
 *                          (sent as the `x-app-key` header). Good enough for a
 *                          closed pilot; revisit auth before any open release.
 *
 * Request data:
 *   { profile, creationSoFar, creationSummary, history, userInput,
 *     inputSource, lowEnergy, paceHint }
 *  • history: recent conversation as [{role: "user"|"assistant", text}] —
 *    the model is stateless, so this is its only memory of the dialogue.
 *  • declinedOptions: labels that were on screen when the user chose
 *    "משהו אחר" this session — rendered as a do-not-reoffer block.
 *  • creationSummary: rolling summary of a long creation — when present,
 *    creationSoFar carries only the newest pieces and the summary carries
 *    the rest (the app decides when to switch; see creation_context.dart).
 *  • inputSource: "user" (default) | "partner" — a partner's modelling tap is
 *    marked so the model never treats it as the user's own choice.
 *  • lowEnergy: true → the prompt switches to the low-energy variant
 *    (2 simple options, minimal text).
 *  • paceHint: "flowing" | "hesitant" (optional) — live pace signal computed
 *    by the app from recent selection latencies; steers how much the model
 *    contributes (shorten/lay out vs. slow down and calm).
 * Response: the parsed JSON turn
 *  ({ say, creation_update, options, confirm, word_offer, partner_tip,
 *     questions, safeguard }).
 */

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const { buildSystemPrompt } = require("./companion_prompt");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
// Shared secret the app sends as `x-app-key` to companionTurnHttp.
const APP_KEY = defineSecret("APP_KEY");

// Pinned on purpose: a model swap changes how the companion "sounds" and is a
// clinical change, not an infra detail — re-run the Hebrew behaviour checks
// before bumping this.
// 22.9, from live testing: Haiku 4.5 could not hold a real conversation —
// repeated its own offers, ignored "משהו אחר", no thread. Sonnet is the
// conversation-quality lever; turns are short (1K max tokens) so the cost
// per turn stays small. Roll back by restoring claude-haiku-4-5-20251001.
// (claude-sonnet-5 was rejected with a 400 on this account's API key —
// the Claude 5 family isn't open to every org; Sonnet 4.5 is GA.)
const MODEL = "claude-sonnet-4-5-20250929";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const REGION = "europe-west1"; // keep data in-region; adjust as needed

/**
 * The turn contract, enforced by the API (structured outputs). With this
 * schema attached, the model can only answer in the exact shape the app
 * parses — a malformed turn can no longer reach a user mid-session.
 * parseTurn() stays as a second net (and as the path when the schema is
 * ever rejected — see the 400 fallback in runCompanionTurn).
 *
 * Structured-outputs rules: every object carries additionalProperties:false
 * and lists all properties as required; optional fields are nullable
 * instead of absent. Mirrors CompanionTurn.fromJson (lib/models/companion.dart).
 */
const TURN_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "say",
    "say_symbols",
    "creation_update",
    "scene_update",
    "creation_summary",
    "page_story",
    "scene_change",
    "needs_confirmation",
    "confirm",
    "options",
    "word_offer",
    "partner_tip",
    "questions",
    "safeguard",
  ],
  properties: {
    say: { type: "string" },
    say_symbols: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["emoji", "word"],
        properties: {
          emoji: { type: "string" },
          word: { type: "string" },
        },
      },
    },
    creation_update: { type: ["string", "null"] },
    scene_update: { type: ["string", "null"] },
    creation_summary: { type: ["string", "null"] },
    // The companion's telling of the current page — the second layer over
    // the creator's own words (see the prompt: "שני רבדים").
    page_story: { type: ["string", "null"] },
    // The latest choice moved the story to a new place or time — a scene
    // that deserves its own page. The app asks the creator; they decide.
    scene_change: { type: "boolean" },
    needs_confirmation: { type: "boolean" },
    confirm: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          required: ["question", "options"],
          properties: {
            question: { type: "string" },
            options: { type: "array", items: { type: "string" } },
          },
        },
      ],
    },
    options: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["emoji", "label"],
        properties: {
          emoji: { type: "string" },
          label: { type: "string" },
        },
      },
    },
    // An invented word offered to the shared language — adoption stays
    // with the creator (the app asks; the model only invites).
    word_offer: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          required: ["word", "emoji", "meaning"],
          properties: {
            word: { type: "string" },
            emoji: { type: "string" },
            meaning: { type: "string" },
          },
        },
      ],
    },
    partner_tip: { type: ["string", "null"] },
    questions: { type: "array", items: { type: "string" } },
    safeguard: { type: "boolean" },
  },
};

/**
 * Untrusted client history → a valid Messages array. Caps size, coerces
 * strings, forces roles to user/assistant, and merges consecutive same-role
 * entries (the API requires alternation and a user-role opener).
 */
function sanitizeHistory(history) {
  if (!Array.isArray(history)) return [];
  const merged = [];
  for (const m of history.slice(-20)) {
    const text = String((m && m.text) || "").trim().slice(0, 2000);
    if (!text) continue;
    const role = m && m.role === "assistant" ? "assistant" : "user";
    const last = merged[merged.length - 1];
    if (last && last.role === role) {
      last.content += `\n${text}`;
    } else {
      merged.push({ role, content: text });
    }
  }
  // The API requires the first message to be from the user; the companion's
  // scripted opener adds nothing the model can't infer — drop it.
  while (merged.length && merged[0].role === "assistant") merged.shift();
  return merged;
}

/** Core: one companion turn. Throws HttpsError on failure. */
async function runCompanionTurn(data) {
  const {
    profile,
    creationSoFar,
    creationSummary,
    sceneSoFar,
    history,
    declinedOptions,
    userInput,
    inputSource,
    lowEnergy,
    paceHint,
  } = data || {};
  if (!userInput || !String(userInput).trim()) {
    throw new HttpsError("invalid-argument", "חסר קלט מהמשתמש (userInput).");
  }

  // The session's walked-past list: options that were on screen when the
  // user chose "משהו אחר". Untrusted client input — coerce and cap.
  const declined = Array.isArray(declinedOptions)
    ? declinedOptions
        .map((d) => String(d || "").trim().slice(0, 80))
        .filter(Boolean)
        .slice(-40)
    : [];

  const system = buildSystemPrompt({
    profile,
    creationSoFar,
    creationSummary: typeof creationSummary === "string" ? creationSummary : undefined,
    sceneSoFar: typeof sceneSoFar === "string" ? sceneSoFar : undefined,
    declinedOptions: declined,
    lowEnergy: lowEnergy === true,
    paceHint: typeof paceHint === "string" ? paceHint : undefined,
  });

  // A partner's modelling tap is labelled so the model treats it as a
  // demonstration, never as the user's own expression (authorship rule).
  const message =
    inputSource === "partner"
      ? `[הדגמה של השותף/מלווה — לא בחירה של המשתמש]: ${String(userInput)}`
      : String(userInput);

  // The recent dialogue rides in as real conversation turns, so the model
  // remembers what is being built and never restarts mid-creation.
  const messages = sanitizeHistory(history);
  const last = messages[messages.length - 1];
  if (last && last.role === "user") {
    last.content += `\n${message}`;
  } else {
    messages.push({ role: "user", content: message });
  }

  const callClaude = (withSchema) =>
    fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY.value(),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        // 18.10: with the page story (and nikud) a turn runs past 1024 —
        // the JSON was cut mid-string and the turn died ("לא הצלחתי לפענח").
        // The schema already bounds the shape; this only bounds length.
        max_tokens: 4096,
        temperature: 0.7,
        system,
        messages,
        ...(withSchema
          ? { output_config: { format: { type: "json_schema", schema: TURN_SCHEMA } } }
          : {}),
      }),
    });

  let res;
  try {
    res = await callClaude(true);
  } catch (err) {
    throw new HttpsError("unavailable", "שגיאת רשת בפנייה ל-Claude.", String(err));
  }

  // A 400 that names output_config means the platform rejected the schema
  // itself (not our request content) — fall back to the un-constrained call
  // so a pilot session never dies on a contract upgrade. parseTurn still
  // guards the shape on that path.
  if (res.status === 400) {
    const detail = await res.text().catch(() => "");
    if (!/output_config/i.test(detail)) {
      throw new HttpsError("internal", "Claude החזיר שגיאה (400).", detail);
    }
    try {
      res = await callClaude(false);
    } catch (err) {
      throw new HttpsError("unavailable", "שגיאת רשת בפנייה ל-Claude.", String(err));
    }
  }

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new HttpsError("internal", `Claude החזיר שגיאה (${res.status}).`, detail);
  }

  const payload = await res.json();
  // A turn cut off by the token limit is not a parse problem — say so, so
  // the screen (and the log) name the real cause.
  if (payload.stop_reason === "max_tokens") {
    throw new HttpsError("internal", "התשובה של Claude נחתכה (ארוכה מדי).", "stop_reason=max_tokens");
  }
  const text = (payload.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();

  const turn = parseTurn(text);
  if (!turn) {
    throw new HttpsError("internal", "לא הצלחתי לפענח תשובת JSON מ-Claude.", text);
  }
  // Output size rides to the log line (not to the app): the one number
  // that explains a slow turn.
  Object.defineProperty(turn, "__usage_output", {
    value: payload.usage && payload.usage.output_tokens ? payload.usage.output_tokens : 0,
    enumerable: false,
  });
  return turn;
}

exports.companionTurn = onCall(
  {
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    // TODO before real use: enforce Firebase App Check + a real auth model.
    enforceAppCheck: false,
  },
  async (request) => {
    // Require an authenticated caller (Anonymous Auth is enough for testing)
    // so the endpoint can't be freely abused to spend API credit.
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "יש להתחבר (אפשר גם התחברות אנונימית) כדי להשתמש בשירות."
      );
    }
    return runCompanionTurn(request.data);
  }
);

exports.companionTurnHttp = onRequest(
  {
    region: REGION,
    secrets: [ANTHROPIC_API_KEY, APP_KEY],
    cors: true,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST בלבד." });
      return;
    }
    if (!req.get("x-app-key") || req.get("x-app-key") !== APP_KEY.value()) {
      res.status(401).json({ error: "מפתח אפליקציה חסר או שגוי (x-app-key)." });
      return;
    }
    const t0 = Date.now();
    try {
      const turn = await runCompanionTurn(req.body);
      // Shape and timing only — never the words (the creation is the
      // creator's). Enough to answer "did the model send words/a scene,
      // and how long did it take?" without guessing (field 18.10).
      logger.info("companion turn", {
        ms: Date.now() - t0,
        outputTokens: turn.__usage_output || 0,
        inputChars: String((req.body || {}).userInput || "").length,
        historyTurns: Array.isArray((req.body || {}).history) ? req.body.history.length : 0,
        hasScene: !!(req.body || {}).sceneSoFar,
        creationUpdate: typeof turn.creation_update === "string" && turn.creation_update.trim() !== "",
        sceneUpdateChars: typeof turn.scene_update === "string" ? turn.scene_update.length : 0,
        needsConfirmation: turn.needs_confirmation === true,
        options: Array.isArray(turn.options) ? turn.options.length : 0,
      });
      res.status(200).json(turn);
    } catch (err) {
      logger.warn("companion turn failed", { ms: Date.now() - t0, error: err.message || String(err) });
      const status = err instanceof HttpsError && err.code === "invalid-argument" ? 400 : 500;
      // The upstream detail travels to the screen (truncated): remote
      // debugging with non-technical testers depends on the error SAYING
      // what happened — "Claude החזיר שגיאה (400)" alone forced guessing.
      const detail =
        err instanceof HttpsError && err.details
          ? String(typeof err.details === "string" ? err.details : JSON.stringify(err.details)).slice(0, 400)
          : "";
      res.status(status).json({
        error: err.message || String(err),
        ...(detail ? { detail } : {}),
      });
    }
  }
);

/**
 * Real picture generation for the "build a picture" mode: the user's scene
 * (their own names for things included) becomes an Imagen prompt. Runs on
 * the same GCP project/billing; the function authenticates with its own
 * service identity via the metadata server — no extra key to manage.
 * Guarded by the same APP_KEY header as the companion.
 */
// Newest first; older entries are fallbacks for projects where the newer
// generation isn't yet available. A 404 means "this model doesn't exist for
// this project" — try the next one.
const IMAGEN_MODELS = [
  "imagen-4.0-fast-generate-001",
  "imagen-3.0-fast-generate-001",
];
// 19.10, measured: both Imagen models 404 on this project (also from a
// user credential), and the two tries cost ~2s on EVERY fresh paint
// (trace: 7.4s total vs 5.4s in the Gemini call). Off until the project
// actually has Imagen — flip to true and the path below is unchanged.
const TRY_IMAGEN = false;
const imagenUrl = (model) =>
  `https://us-central1-aiplatform.googleapis.com/v1/projects/` +
  `${process.env.GCLOUD_PROJECT}/locations/us-central1/publishers/google/` +
  `models/${model}:predict`;

async function serviceAccessToken() {
  const res = await fetch(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { headers: { "Metadata-Flavor": "Google" } }
  );
  if (!res.ok) throw new Error(`metadata token: ${res.status}`);
  return (await res.json()).access_token;
}

// Fallback path: the Gemini image model on the global endpoint. Field-tested
// on this project — every Imagen predict model 404s here, so this is in
// practice the door that's open.
// The image model lives behind the global endpoint and behind regional
// ones, each with its own shared capacity. 18.10: the project's own quotas
// sat at 0.01% while the global endpoint answered 429 RESOURCE_EXHAUSTED on
// the third paint in a minute — that is shared capacity, not our quota. So
// a busy endpoint is left for the next one before anyone waits.
const GEMINI_IMAGE_MODEL = "gemini-2.5-flash-image";
const GEMINI_IMAGE_LOCATIONS = ["global", "europe-west1", "us-central1"];
const geminiImageUrl = (location) =>
  (location === "global"
    ? "https://aiplatform.googleapis.com/v1/projects/"
    : `https://${location}-aiplatform.googleapis.com/v1/projects/`) +
  `${process.env.GCLOUD_PROJECT}/locations/${location}/publishers/google/` +
  `models/${GEMINI_IMAGE_MODEL}:generateContent`;

function geminiImage(token, prompt, withRatio, baseImageB64, location = "global") {
  const generationConfig = { responseModalities: ["TEXT", "IMAGE"] };
  if (withRatio) generationConfig.imageConfig = { aspectRatio: "4:3" };
  const parts = [];
  // With a base image the model EDITS it per the prompt instead of
  // painting from scratch — the creation keeps growing.
  if (baseImageB64) {
    parts.push({ inlineData: { mimeType: "image/png", data: baseImageB64 } });
  }
  parts.push({ text: prompt });
  return fetch(geminiImageUrl(location), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      contents: [{ role: "user", parts }],
      generationConfig,
    }),
  });
}

// A burst of quick choices meets "busy" (429 RESOURCE_EXHAUSTED / 503) —
// field rounds 2.10 and 18.10. Order of escape: the next endpoint first
// (its capacity is separate), and only when every endpoint is busy, wait
// it out: Retry-After when the server sends one, otherwise 4s/8s/16s —
// well inside the 120s function and 90s client timeouts. An endpoint
// that does not serve the model (404) is simply skipped.
const BUSY_STATUSES = new Set([429, 503]);
const BUSY_BACKOFF_MS = [4000, 8000, 16000];
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// `trace` (optional array) collects one "location:status:ms" entry per
// call made, so a slow paint can be read from the log: which endpoint
// answered, after how many tries, and how long each took (19.10: the
// pilot's 20-30s paints were invisible behind a single total).
async function geminiImageWaitingOutBusy(token, prompt, baseImageB64, trace) {
  let g = null;
  const call = async (withRatio, location) => {
    const t = Date.now();
    const r = await geminiImage(token, prompt, withRatio, baseImageB64, location);
    if (trace) trace.push(`${location}:${r.status}:${Date.now() - t}`);
    return r;
  };
  for (let attempt = 0; ; attempt++) {
    for (const location of GEMINI_IMAGE_LOCATIONS) {
      g = await call(true, location);
      // If the aspect-ratio config is what's rejected, retry bare.
      if (g.status === 400) {
        g = await call(false, location);
      }
      if (g.status === 404 || BUSY_STATUSES.has(g.status)) continue;
      return g;
    }
    // Every endpoint busy (or missing): the last answer is what we hold.
    if (!BUSY_STATUSES.has(g.status) || attempt >= BUSY_BACKOFF_MS.length) {
      return g;
    }
    const retryAfter = Number(g.headers.get("retry-after"));
    const waitMs =
      retryAfter > 0 && retryAfter <= 30
        ? retryAfter * 1000
        : BUSY_BACKOFF_MS[attempt];
    await sleep(waitMs);
  }
}

exports.imagineHttp = onRequest(
  { region: REGION, secrets: [APP_KEY], cors: true, timeoutSeconds: 120 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST בלבד." });
      return;
    }
    if (!req.get("x-app-key") || req.get("x-app-key") !== APP_KEY.value()) {
      res.status(401).json({ error: "מפתח אפליקציה חסר או שגוי (x-app-key)." });
      return;
    }
    const prompt = String((req.body || {}).prompt || "").trim().slice(0, 800);
    if (!prompt) {
      res.status(400).json({ error: "חסר תיאור לתמונה (prompt)." });
      return;
    }
    // Optional picture to EDIT (base64, ~8MB decoded cap) — editing is a
    // Gemini capability, so its presence skips the Imagen attempt.
    let baseImageB64 = String((req.body || {}).baseImageB64 || "").trim();
    if (baseImageB64.length > 11_000_000) baseImageB64 = "";
    // A client that says `accept: image/png` gets the picture as raw bytes
    // (content-type image/png) instead of base64 inside JSON — a third
    // less to download and no decode step on a tablet. Older clients keep
    // the JSON shape.
    const wantsRaw = /image\/png/i.test(req.get("accept") || "");
    const t0 = Date.now();
    const trace = [];
    // Timing and sizes only — never the scene itself. `trace` lists every
    // call to the image model (location:status:ms); `attempts` counts them.
    const done = (how) =>
      logger.info("imagine", {
        ms: Date.now() - t0,
        how,
        promptChars: prompt.length,
        baseImageChars: baseImageB64.length,
        attempts: trace.length,
        trace: trace.join(" "),
        raw: wantsRaw,
      });
    const sendImage = (b64) => {
      if (wantsRaw) {
        const bytes = Buffer.from(b64, "base64");
        res.status(200).set("content-type", "image/png").send(bytes);
      } else {
        res.status(200).json({ imageB64: b64 });
      }
    };
    try {
      const token = await serviceAccessToken();
      if (TRY_IMAGEN && !baseImageB64) {
        let r = null;
        for (const model of IMAGEN_MODELS) {
          r = await fetch(imagenUrl(model), {
            method: "POST",
            headers: {
              Authorization: `Bearer ${token}`,
              "content-type": "application/json",
            },
            body: JSON.stringify({
              instances: [{ prompt }],
              parameters: { sampleCount: 1, aspectRatio: "4:3" },
            }),
          });
          // Anything but "model not found" is this model's real answer.
          if (r.status !== 404) break;
        }
        if (r.ok) {
          const payload = await r.json();
          const b64 = payload?.predictions?.[0]?.bytesBase64Encoded;
          if (!b64) {
            res.status(500).json({ error: "לא התקבלה תמונה מהמחולל." });
            return;
          }
          done("imagen");
          sendImage(b64);
          return;
        }
      }
      // Imagen is closed to this project (and can't edit) — go through the
      // Gemini image model. The model occasionally answers with TEXT ONLY
      // ("sure, here's a picture..." and no picture) — insist once more
      // before giving up.
      let g = null;
      let payload = null;
      let part = null;
      let attemptPrompt = prompt;
      for (let attempt = 0; attempt < 2 && !part; attempt++) {
        g = await geminiImageWaitingOutBusy(token, attemptPrompt, baseImageB64, trace);
        if (!g.ok) break;
        payload = await g.json();
        part = (payload?.candidates?.[0]?.content?.parts || []).find(
          (p) => p.inlineData && p.inlineData.data
        );
        attemptPrompt =
          `${prompt}\n\nחשוב: אל תענה בטקסט. צור והחזר את התמונה עצמה עכשיו.`;
      }
      if (!g.ok) {
        const detail = await g.text().catch(() => "");
        done(`gemini-error-${g.status}`);
        // Still busy after the backoff: say so in the creator's terms and
        // pass the status through, so the app can give it one more quiet
        // try instead of reporting a failure.
        if (BUSY_STATUSES.has(g.status)) {
          res.status(429).json({
            error: "מחולל התמונות עמוס כרגע — ננסה שוב בעוד רגע.",
            detail: detail.slice(0, 500),
          });
          return;
        }
        res.status(500).json({
          error: `מחולל התמונות החזיר שגיאה (${g.status}).`,
          detail: detail.slice(0, 500),
        });
        return;
      }
      if (!part) {
        done("gemini-no-image");
        res.status(500).json({
          error: "לא התקבלה תמונה מהמחולל.",
          detail: JSON.stringify(payload).slice(0, 300),
        });
        return;
      }
      done("gemini");
      sendImage(part.inlineData.data);
    } catch (err) {
      done("exception");
      res.status(500).json({ error: `שגיאה ביצירת התמונה: ${String(err)}` });
    }
  }
);

/**
 * Claude is asked for JSON only, but be defensive: strip ```json fences and
 * grab the outermost object if any stray text slips in.
 */
function parseTurn(text) {
  if (!text) return null;
  let t = text.trim();
  t = t.replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim();
  try {
    return JSON.parse(t);
  } catch (_) {
    const start = t.indexOf("{");
    const end = t.lastIndexOf("}");
    if (start !== -1 && end > start) {
      try {
        return JSON.parse(t.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
