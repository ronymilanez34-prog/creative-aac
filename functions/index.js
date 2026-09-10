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
 *   { profile, creationSoFar, userInput, inputSource, lowEnergy, paceHint }
 *  • inputSource: "user" (default) | "partner" — a partner's modelling tap is
 *    marked so the model never treats it as the user's own choice.
 *  • lowEnergy: true → the prompt switches to the low-energy variant
 *    (2 simple options, minimal text).
 *  • paceHint: "flowing" | "hesitant" (optional) — live pace signal computed
 *    by the app from recent selection latencies; steers how much the model
 *    contributes (shorten/lay out vs. slow down and calm).
 * Response: the parsed JSON turn
 *  ({ say, creation_update, options, confirm, partner_tip, questions, safeguard }).
 */

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const { buildSystemPrompt } = require("./companion_prompt");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
// Shared secret the app sends as `x-app-key` to companionTurnHttp.
const APP_KEY = defineSecret("APP_KEY");

// Fast, low-cost model — well suited to short, structured co-creation turns.
// Pinned on purpose: a model swap changes how the companion "sounds" and is a
// clinical change, not an infra detail — re-run the Hebrew behaviour checks
// before bumping this.
const MODEL = "claude-haiku-4-5-20251001";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const REGION = "europe-west1"; // keep data in-region; adjust as needed

/** Core: one companion turn. Throws HttpsError on failure. */
async function runCompanionTurn(data) {
  const { profile, creationSoFar, userInput, inputSource, lowEnergy, paceHint } =
    data || {};
  if (!userInput || !String(userInput).trim()) {
    throw new HttpsError("invalid-argument", "חסר קלט מהמשתמש (userInput).");
  }

  const system = buildSystemPrompt({
    profile,
    creationSoFar,
    lowEnergy: lowEnergy === true,
    paceHint: typeof paceHint === "string" ? paceHint : undefined,
  });

  // A partner's modelling tap is labelled so the model treats it as a
  // demonstration, never as the user's own expression (authorship rule).
  const message =
    inputSource === "partner"
      ? `[הדגמה של השותף/מלווה — לא בחירה של המשתמש]: ${String(userInput)}`
      : String(userInput);

  let res;
  try {
    res = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY.value(),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1024,
        temperature: 0.7,
        system,
        messages: [{ role: "user", content: message }],
      }),
    });
  } catch (err) {
    throw new HttpsError("unavailable", "שגיאת רשת בפנייה ל-Claude.", String(err));
  }

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new HttpsError("internal", `Claude החזיר שגיאה (${res.status}).`, detail);
  }

  const payload = await res.json();
  const text = (payload.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();

  const turn = parseTurn(text);
  if (!turn) {
    throw new HttpsError("internal", "לא הצלחתי לפענח תשובת JSON מ-Claude.", text);
  }
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
    try {
      const turn = await runCompanionTurn(req.body);
      res.status(200).json(turn);
    } catch (err) {
      const status = err instanceof HttpsError && err.code === "invalid-argument" ? 400 : 500;
      res.status(status).json({ error: err.message || String(err) });
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
const IMAGEN_MODEL = "imagen-3.0-fast-generate-001";
const IMAGEN_URL =
  `https://us-central1-aiplatform.googleapis.com/v1/projects/` +
  `${process.env.GCLOUD_PROJECT}/locations/us-central1/publishers/google/` +
  `models/${IMAGEN_MODEL}:predict`;

async function serviceAccessToken() {
  const res = await fetch(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { headers: { "Metadata-Flavor": "Google" } }
  );
  if (!res.ok) throw new Error(`metadata token: ${res.status}`);
  return (await res.json()).access_token;
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
    try {
      const token = await serviceAccessToken();
      const r = await fetch(IMAGEN_URL, {
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
      if (!r.ok) {
        const detail = await r.text().catch(() => "");
        res.status(500).json({
          error: `מחולל התמונות החזיר שגיאה (${r.status}).`,
          detail: detail.slice(0, 500),
        });
        return;
      }
      const payload = await r.json();
      const b64 = payload?.predictions?.[0]?.bytesBase64Encoded;
      if (!b64) {
        res.status(500).json({ error: "לא התקבלה תמונה מהמחולל." });
        return;
      }
      res.status(200).json({ imageB64: b64 });
    } catch (err) {
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
