// sales_engineer + customer_support: no reply path may send a code-written sentence to a customer or supplier unless the
// OpenRouter call failed. Founder ruling, 27 Oct 2026 ~14:15Z (founder_instruction 1339), verbatim:
//   "the engineer and customer support never replies without llm unless the server of open router is down"
//
// WHAT WAS MEASURED (the audit behind this check, 27 Oct 2026, read from main at 2f204b792): every fallback in the reply
// paths fired on "the model's reply is ''", and aiReply returns '' both when no model answered AND when a model answered
// and every draft was refused. So five code-written texts went out while a model was up: wa_inbound's HELD_NOTICE
// (main reply, menu, file, price change, spec-offer turns), the supplier quote-review QR_HELD_NOTICE (and twice with no
// model asked at all: a failed and a killed review), inquiry_intake's HELD_FOR_SPECS, its replyFromState / interview /
// four-question / drawing / CAD / held-for-trade sentences, and the WhatsApp case confirmation and accepted-offer
// confirmation sent as-is. _shared/openrouter_down.ts now decides "down"; AiReply.outage carries it.
//
// HOW THIS GUARDS FUTURE CODE. It reads the reply-path source (comments stripped, so prose describing a pattern never
// trips it) and fails on:
//   R1  `<x>.reply || <code text>` / `text || <CONSTANT>` — a code fallback after a model reply with no outage gate. The
//       sanctioned door is modelOrOutage(r, codeText) or an explicit `outage` test on the same line.
//   R2  a registered code-written reply (HELD_NOTICE, QR_HELD_NOTICE, caseConfirm(…), the accepted-offer template) used
//       with no outage gate within three lines either side (the draft may be built just before its gated send).
//   R3  inquiry_intake (the request chat) has its own check, landed with the intake turn clock on PR #1646:
//       scripts/checks/the_intake_reply_is_the_models_unless_openrouter_is_down.test.mjs. Its files are not scanned here.
//   R4  the fixed notices themselves are gated at their source: holdUnwritten sends only `io.outage ? …`, the quote
//       review adds QR_HELD_NOTICE only when `outage`, and every holdUnwritten call passes `outage:`.
// Each rule has a KNOWN-BAD CONTROL below: the exact line main carried before this fix must fail it.
// prevented by: this file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FN = (p) => path.join(REPO, 'supabase', 'functions', p);

/** The reply paths of the two seats (customer- and supplier-facing words). Test files are not reply paths. */
export const REPLY_PATHS = [
  '_shared/ai_reply.ts', '_shared/support_reply.ts', '_shared/brief_answer.ts', '_shared/reasoned_delivery.ts', '_shared/clearer_copy.ts',
  'wa_inbound/index.ts', 'wa_inbound/model_says.ts', 'wa_inbound/menu_flow.ts',
  'sales_engineer/index.ts', 'site_assistant/index.ts', 'site_assistant/visitor_scope.ts', 'email_triage/index.ts',
  'supplier_api/index.ts', 'supplier_api/quote_review_flow.ts',
];

const GATE = /outage|Outage|llmDown|modelOrOutage/;
const stripComments = (src) => src.split('\n').map((l) => (/^\s*(\/\/|\*|\/\*)/.test(l) ? '' : l.replace(/\s\/\/\s.*$/, '')));

/** R1 + R2 over one file's source. Returns findings "file:line: rule: text". */
export function replyFindings(file, src) {
  const lines = stripComments(src);
  const out = [];
  // the gate may sit just before the use or on the send right after a draft is built (const confirm = caseConfirm(...))
  const near = (i) => lines.slice(Math.max(0, i - 3), i + 4).join('\n');
  lines.forEach((l, i) => {
    if (!l.trim() || /^\s*(import|export (const|function|type|interface)|export async function)\b/.test(l)) return;
    // R1: a model reply with a code-written fallback after `||`
    if (/(?:\b\w+\.reply|(?<![.\w])(?:reply|text|said|line))\s*\|\|\s*(?:['"`][^'"`\n]{12,}|[A-Z][A-Z0-9_]{3,}\b|(?:caseConfirm|replyFromState|clearerCopyAsk|capReply)\()/.test(l) && !GATE.test(l)) {
      out.push(`${file}:${i + 1}: R1 code fallback after a model reply, no outage gate: ${l.trim().slice(0, 140)}`);
    }
    // R2: a registered code-written reply used outside its definition, with no gate nearby
    const uses = /\b(?:QR_HELD_NOTICE|HELD_NOTICE\[|caseConfirm\(|capReply\()/.test(l) || (file === 'wa_inbound/index.ts' && /\btext\s*=\s*msg\.body\b/.test(l));
    const compares = /(?:===|!==)\s*\w*HELD_NOTICE|HELD_NOTICE\S*\s*(?:===|!==)|\.includes\(/.test(l);
    // a draft held in a local (`const confirm = caseConfirm(…)`) must meet its gate before the block ends (8 lines)
    const draftLocal = /^\s*const \w+ = /.test(l) && GATE.test(lines.slice(i, i + 9).join('\n'));
    if (uses && !compares && !draftLocal && !GATE.test(near(i))) {
      out.push(`${file}:${i + 1}: R2 a code-written reply is sent with no outage gate: ${l.trim().slice(0, 140)}`);
    }
  });
  return out;
}

/** R4: the fixed notices are gated where they are made. */
export function noticeFindings(files) {
  const out = [];
  const ms = stripComments(files['wa_inbound/model_says.ts'] || '').join('\n');
  if (!/const notice = io\.outage \? HELD_NOTICE\[lang\] : ''/.test(ms)) out.push('wa_inbound/model_says.ts: R4 holdUnwritten sends HELD_NOTICE without io.outage');
  const qr = stripComments(files['supplier_api/quote_review_flow.ts'] || '').join('\n');
  if (!/outage \? await repo\.addMessage\(\{[^}]*body: QR_HELD_NOTICE/.test(qr)) out.push('supplier_api/quote_review_flow.ts: R4 QR_HELD_NOTICE is added without outage');
  if (/await held\(repo, deps, [^;]*\)\.catch/.test(qr)) out.push('supplier_api/quote_review_flow.ts: R4 a failed/killed review adds the held notice without asking the model first');
  const wa = stripComments(files['wa_inbound/index.ts'] || '').join('\n');
  for (const m of wa.matchAll(/holdUnwritten\(\{([^}]*)/g)) if (!/outage:/.test(m[1])) out.push('wa_inbound/index.ts: R4 holdUnwritten called without outage');
  return out;
}

const read = (p) => fs.readFileSync(FN(p), 'utf8');

test('1339: no reply path sends a code-written sentence unless OpenRouter is down (R1, R2)', () => {
  const found = REPLY_PATHS.flatMap((p) => replyFindings(p, read(p)));
  assert.deepEqual(found, []);
});
test('1339: the fixed notices are gated on the outage where they are made (R4)', () => {
  const files = Object.fromEntries(REPLY_PATHS.map((p) => [p, read(p)]));
  assert.deepEqual(noticeFindings(files), []);
});
test('1339: every reply-path file this check names exists (a renamed file is re-registered, never silently dropped)', () => {
  for (const p of REPLY_PATHS) assert.ok(fs.existsSync(FN(p)), p);
});

// KNOWN-BAD CONTROLS: the lines main carried before this fix (2f204b792). Each must be caught.
test('known-bad: the old fallbacks are caught', () => {
  // the shape main's inquiry_intake heldReply had (HELD_FOR_SPECS whenever aiReply gave '', model up or not)
  assert.equal(replyFindings('x.ts', '  return r.reply || HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en;\n').length, 1);
  // wa_inbound/index.ts, main: the accepted-offer template sent as-is
  assert.equal(replyFindings('wa_inbound/index.ts', "            } else if (so.state === 'accepted') { text = msg.body; notice = true; }\n").length, 1);
  // wa_inbound/menu_flow.ts, main: the case confirmation sent as-is
  assert.equal(replyFindings('wa_inbound/menu_flow.ts', "    await reply(d, inp, lang, 'menu_case', caseConfirm(lang, c), null, { case_ref: c.ref });\n").length, 1);
  // supplier_api/quote_review_flow.ts, main: the held notice added whatever the cause
  assert.equal(replyFindings('supplier_api/quote_review_flow.ts', "  const r = await repo.addMessage({ review_id: reviewId, role: SEAT, kind: 'notice', body: QR_HELD_NOTICE, body_ar: null });\n").length, 1);
  // a new canned fallback in any form
  assert.equal(replyFindings('x.ts', "  const text = a.reply || 'Thank you, we will get back to you shortly.';\n").length, 1);
  // ...and the sanctioned forms pass
  assert.equal(replyFindings('x.ts', '  return modelOrOutage(r, HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en);\n').length, 0);
  assert.equal(replyFindings('x.ts', '  if (!text && sayOutage) { text = msg.body; notice = true; }\n').length, 0);
  assert.equal(replyFindings('x.ts', '  // return r.reply || HELD_FOR_SPECS[lang]; was the bug\n').length, 0, 'a comment never trips it');
});
test('known-bad (R2): the homepage visitor-cap reply sent as code text (PR #1434 before 1339) is caught', () => {
  assert.equal(replyFindings('site_assistant/index.ts', '      const reply = capReply(audience, visitorLang);\n').length, 1);
  assert.equal(replyFindings('site_assistant/index.ts', '      const reply = modelOrOutage(capped, capReply(audience, visitorLang));\n').length, 0);
  // review of #1658: a model-first fallback with no outage gate, sitting within three lines of the log call that names
  // `capped.outage`, passed R2's proximity test; R1 knows capReply( now and catches it on its own line.
  const src = [
    '      const capped = await capReplyByModel(deps, { audience, lang: visitorLang, message });',
    '      const reply = capped.reply || capReply(audience, visitorLang);',
    "      await logWithAttempts(admin, 'assistant_logs', { reply }, { attempts: [...(capped.outage ? ['outage'] : [])] });",
  ].join('\n') + '\n';
  assert.ok(replyFindings('site_assistant/index.ts', src).some((f) => f.includes('R1')), 'capped.reply || capReply(...) is a code fallback with no outage gate');
});
test('known-bad: an ungated notice at its source is caught', () => {
  const ms = "export async function holdUnwritten(io) {\n  const notice = HELD_NOTICE[lang];\n}\n";
  assert.ok(noticeFindings({ 'wa_inbound/model_says.ts': ms }).some((f) => f.includes('R4 holdUnwritten')));
  const qr = "  const r = await repo.addMessage({ review_id: reviewId, role: SEAT, kind: 'notice', body: QR_HELD_NOTICE });\n    await held(repo, deps, r.id, 'x', null).catch(() => {});\n";
  const f = noticeFindings({ 'supplier_api/quote_review_flow.ts': qr });
  assert.ok(f.some((x) => x.includes('without outage')) && f.some((x) => x.includes('without asking the model')));
});
