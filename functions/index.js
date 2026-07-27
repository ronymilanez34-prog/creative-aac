"use strict";

/**
 * Creative AAC — Cloud Functions.
 *
 * `companionTurn` is a callable that proxies one turn of the co-creation
 * conversation to Claude. The Anthropic API key lives ONLY here, as a secret —
 * it is never shipped in the app.
 *
 * Flow: app sends { profile, creationSoFar, userInput } → we build the
 * companion system prompt → call Claude → return the parsed JSON turn
 * ({ say, creation_update, options, confirm, safeguard, ... }).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const { buildSystemPrompt } = require("./companion_prompt");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// Fast, low-cost model — well suited to short, structured co-creation turns.
const MODEL = "claude-haiku-4-5-20251001";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

exports.companionTurn = onCall(
  {
    region: "europe-west1", // keep data in-region; adjust as needed
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

    const { profile, creationSoFar, userInput } = request.data || {};
    if (!userInput || !String(userInput).trim()) {
      throw new HttpsError("invalid-argument", "חסר קלט מהמשתמש (userInput).");
    }

    const system = buildSystemPrompt({ profile, creationSoFar });

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
          messages: [{ role: "user", content: String(userInput) }],
        }),
      });
    } catch (err) {
      throw new HttpsError("unavailable", "שגיאת רשת בפנייה ל-Claude.", String(err));
    }

    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      throw new HttpsError("internal", `Claude החזיר שגיאה (${res.status}).`, detail);
    }

    const data = await res.json();
    const text = (data.content || [])
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
