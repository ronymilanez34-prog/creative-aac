"use strict";

/**
 * The AI net of the import door: a PICTURE of a board (a screenshot from any
 * AAC app, a photo of a printed board on the wall, a PDF) → the words on it.
 *
 * The app shows the result to the staff member, who removes mistakes BEFORE
 * anything is saved — the model proposes, a human decides.
 *
 * Privacy: the picture goes to Claude for this one call and is not stored
 * (nothing here writes anywhere). The log carries sizes and counts only.
 * A board may hold personal photos (family, staff) — the prompt forbids
 * describing people, and a photo button with no text is skipped: names
 * come from the staff, never from a face.
 */

const BOARD_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["words"],
  properties: {
    words: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "sure"],
        properties: {
          label: { type: "string" },
          // false = the text was hard to read, or the word is a guess from
          // a symbol with no text — the review screen marks it.
          sure: { type: "boolean" },
        },
      },
    },
  },
};

const SYSTEM = `אתה קורא לוחות תקשורת חלופית (תת"ח) מתוך תמונה או PDF.
התמונה היא לוח של אדם שמתקשר בעזרת כפתורים: לכל כפתור סמל או תמונה, ובדרך כלל מילה כתובה.

המשימה: להחזיר את המילים שעל הכפתורים — בדיוק כפי שהן כתובות.

כללים:
- העתק את הכתוב מילה במילה, בכתיב שבלוח (עם ניקוד אם יש). אל תתקן, אל תתרגם, אל תשלים.
- סדר: כפי שקוראים את הלוח — בלוח בעברית מימין לשמאל, שורה אחרי שורה, דף אחרי דף.
- דלג על כפתורי מערכת וניווט: חזרה, בית, תפריט, מקלדת, מחיקה, ניקוי, הקראה/דבר, חיצים, מספרי דפים, שעון, סוללה, וכל מה שהוא חלק מהמסך ולא מהלוח.
- כפתור קטגוריה ("אוכל", "רגשות") הוא מילה — כלול אותו.
- כפתור עם סמל בלי טקסט: אם ברור מה הסמל (תפוח, כוס מים) — תן מילה אחת בעברית, sure=false. אם לא ברור — דלג.
- כפתור עם צילום של אדם ובלי טקסט: דלג. לעולם אל תתאר אנשים, פנים או מראה.
- מילה שקשה לקרוא — תן את הקריאה הטובה ביותר, sure=false.
- אל תמציא כפתורים שלא רואים. אותה מילה פעמיים — פעם אחת.
- אם אין בתמונה לוח תקשורת — words ריק.`;

const MAX_PAGES = 10;
const MAX_TOTAL_B64 = 24_000_000; // ~18MB of pictures in one call

/**
 * Validates the request and builds the Claude content blocks.
 * Exported for tests. Throws Error with a Hebrew message on bad input.
 */
function buildContent(body) {
  const pages = Array.isArray(body && body.pages) ? body.pages : [];
  if (pages.length === 0) throw new Error("לא נשלחו תמונות של הלוח.");
  if (pages.length > MAX_PAGES) {
    throw new Error(`אפשר עד ${MAX_PAGES} תמונות בפעם אחת.`);
  }
  let total = 0;
  const blocks = [];
  for (const p of pages) {
    const mediaType = String((p && p.mediaType) || "").toLowerCase();
    const data = String((p && p.dataB64) || "").replace(/\s+/g, "");
    if (!data) throw new Error("אחת התמונות ריקה.");
    total += data.length;
    if (total > MAX_TOTAL_B64) throw new Error("התמונות גדולות מדי — נסו פחות דפים בכל פעם.");
    if (mediaType === "application/pdf") {
      blocks.push({ type: "document", source: { type: "base64", media_type: mediaType, data } });
    } else if (["image/jpeg", "image/png", "image/gif", "image/webp"].includes(mediaType)) {
      blocks.push({ type: "image", source: { type: "base64", media_type: mediaType, data } });
    } else {
      throw new Error("סוג קובץ לא נתמך — תמונה (JPG/PNG) או PDF.");
    }
  }
  blocks.push({
    type: "text",
    text: pages.length > 1
      ? `אלה ${pages.length} דפים של אותו לוח, לפי הסדר. החזר את כל המילים.`
      : "החזר את המילים שעל הלוח.",
  });
  return blocks;
}

/** Cleans the model's list: trims, drops empties and duplicates. */
function cleanWords(words) {
  const seen = new Set();
  const out = [];
  for (const w of Array.isArray(words) ? words : []) {
    const label = String((w && w.label) || "").trim().slice(0, 60);
    if (!label) continue;
    const key = label.replace(/[֑-ׇ]/g, "").toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ label, sure: w.sure !== false });
    if (out.length >= 300) break;
  }
  return out;
}

/**
 * One reading. [callClaude] is injected (index.js passes the real fetch;
 * tests pass a fake). Returns { words, outputTokens }.
 */
async function readBoard(body, callClaude) {
  const content = buildContent(body);
  const res = await callClaude({
    system: SYSTEM,
    messages: [{ role: "user", content }],
    schema: BOARD_SCHEMA,
  });
  if (res.stop_reason === "max_tokens") {
    throw new Error("הלוח ארוך מדי לקריאה אחת — נסו פחות דפים בכל פעם.");
  }
  const text = (res.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
  let parsed;
  try {
    parsed = JSON.parse(text.replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim());
  } catch (_) {
    throw new Error("לא הצלחתי לקרוא את תשובת ה-AI.");
  }
  return {
    words: cleanWords(parsed && parsed.words),
    outputTokens: (res.usage && res.usage.output_tokens) || 0,
  };
}

module.exports = { BOARD_SCHEMA, SYSTEM, buildContent, cleanWords, readBoard, MAX_PAGES };
