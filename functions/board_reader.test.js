"use strict";
// Run: node functions/board_reader.test.js  (no dependencies)
const assert = require("node:assert/strict");
const { buildContent, cleanWords, readBoard, MAX_PAGES } = require("./board_reader");

(async () => {
  // Request validation
  assert.throws(() => buildContent({}), /לא נשלחו/);
  assert.throws(() => buildContent({ pages: [{ mediaType: "image/bmp", dataB64: "AA" }] }), /סוג קובץ/);
  assert.throws(() => buildContent({ pages: Array(MAX_PAGES + 1).fill({ mediaType: "image/png", dataB64: "AA" }) }), /אפשר עד/);
  const blocks = buildContent({ pages: [
    { mediaType: "image/jpeg", dataB64: "AA\nBB" },
    { mediaType: "application/pdf", dataB64: "CC" },
  ] });
  assert.equal(blocks[0].type, "image");
  assert.equal(blocks[0].source.data, "AABB");
  assert.equal(blocks[1].type, "document");
  assert.equal(blocks.at(-1).type, "text");

  // Cleaning: trims, dedupes across nikud, keeps the uncertain flag
  assert.deepEqual(cleanWords([
    { label: " אמא ", sure: true }, { label: "", sure: true },
    { label: "מֶלון", sure: false }, { label: "מלון", sure: true },
  ]), [{ label: "אמא", sure: true }, { label: "מֶלון", sure: false }]);

  // Full path with a fake Claude
  let seen;
  const fake = async (req) => {
    seen = req;
    return { content: [{ type: "text", text: JSON.stringify({ words: [{ label: "כלב", sure: true }, { label: "תפוח", sure: false }] }) }], usage: { output_tokens: 42 } };
  };
  const r = await readBoard({ pages: [{ mediaType: "image/png", dataB64: "AA" }] }, fake);
  assert.deepEqual(r, { words: [{ label: "כלב", sure: true }, { label: "תפוח", sure: false }], outputTokens: 42 });
  assert.ok(seen.schema && seen.system.includes("תת\"ח"));

  // Cut-off and garbage answers fail with a clear message
  await assert.rejects(readBoard({ pages: [{ mediaType: "image/png", dataB64: "AA" }] }, async () => ({ stop_reason: "max_tokens", content: [] })), /ארוך מדי/);
  await assert.rejects(readBoard({ pages: [{ mediaType: "image/png", dataB64: "AA" }] }, async () => ({ content: [{ type: "text", text: "sure! here" }] })), /לא הצלחתי/);
  console.log("board_reader: all tests passed");
})().catch((e) => { console.error(e); process.exit(1); });
