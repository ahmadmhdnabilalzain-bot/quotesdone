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
//   R5  a reply sentence written inline as a literal (`const text = <cond> ? 'Thank you…' : …`, ARABIC as well) with no
//       outage gate within the statement or three lines either side. Ledger 1348 extended 1339 to every message a person
//       reads as a reply; the WhatsApp "needs a person" contact notice (_shared/reasoned_delivery.ts, surface
//       wa_inbound.needs_a_person) was such a literal, sent whatever the model's state. The file was already scanned, yet
//       R1/R2 never saw it: no `||` and no registered constant. R5 sees it, and R4 pins its gate at the source.
//   R6  a delivery that returns via 'unwritten' must not strand its row: fn_reason_held_resolve has already set it to
//       'reasoned', which neither fn_reason_held_due (claims 'held') nor fn_reason_held_escalate ('failed' / 'held')
//       ever reads. The SQL file defining fn_reason_held_delivered (scripts/sql/an_unwritten_person_notice_goes_back_to_
//       the_replay.sql; review of #1669, read from the live definition) must send 'unwritten' back to 'held', and to
//       'failed' at the last try. Its probe proves the replay and the escalation then pick the row up.
// Each rule has a KNOWN-BAD CONTROL below: the exact line main carried before this fix must fail it.
// prevented by: this file, _shared/reasoned_delivery.test.ts (the 1339 person-contact test).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionFiles } from '../lib/function_sources.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FN = (p) => path.join(REPO, 'supabase', 'functions', p);

// wa_inbound/index.ts was split on 9 Nov 2026 into index.ts and the modules it calls: every one of them is a reply path. The sibling
// modules listed apart (menu_flow.ts, model_says.ts) and the ones that never held reply text (menu, coverage, founder_*, directive_gate, wa_row) are not repeated.
const WA_SIBLINGS = new Set(['coverage.ts', 'directive_gate.ts', 'founder_directive.ts', 'founder_queries.ts', 'menu.ts', 'menu_flow.ts', 'model_says.ts', 'wa_row.ts']);
export const WA_HANDLER = functionFiles('wa_inbound').map((f) => f.replace('supabase/functions/', '')).filter((f) => !WA_SIBLINGS.has(f.split('/').pop()));

/** The reply paths of the two seats (customer- and supplier-facing words). Test files are not reply paths. */
export const REPLY_PATHS = [
  '_shared/ai_reply.ts', '_shared/support_reply.ts', '_shared/brief_answer.ts', '_shared/reasoned_delivery.ts', '_shared/clearer_copy.ts',
  ...WA_HANDLER, 'wa_inbound/model_says.ts', 'wa_inbound/menu_flow.ts',
  'site_assistant/index.ts', 'site_assistant/visitor_scope.ts', 'email_triage/index.ts',
  'supplier_api/quote_review_flow.ts',
  // quote_review_flow.ts is a barrel since 9 Nov 2026; the conversation lives in supplier_api/quote_review_flow/: every file is read.
  ...functionFiles('supplier_api').map((f) => f.replace('supabase/functions/', '')).filter((f) => f.startsWith('supplier_api/quote_review_flow/')),
  // supplier_api/index.ts was split on 9 Nov 2026 into index.ts, context.ts, lib/ and actions/: every one of them is read.
  // sales_engineer/index.ts was split on 9 Nov 2026 the same way (index.ts, context.ts, lib/, actions/): every one of them is read.
  ...functionFiles('sales_engineer').map((f) => f.replace('supabase/functions/', '')).filter((f) => /^sales_engineer\/(index|context)\.ts$|^sales_engineer\/(lib|actions)\//.test(f)),
  ...functionFiles('supplier_api').map((f) => f.replace('supabase/functions/', '')).filter((f) => /^supplier_api\/(index|context)\.ts$|^supplier_api\/(lib|actions)\//.test(f)),
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
    // a barrel's re-export names a constant, it does not use it (quote_review_flow.ts since 9 Nov 2026)
    if (/^\s*export (?:type )?\{[^}]*\} from '[^']+';\s*$/.test(l)) return;
    // R1: a model reply with a code-written fallback after `||`
    if (/(?:\b\w+\.reply|(?<![.\w])(?:reply|text|said|line))\s*\|\|\s*(?:['"`][^'"`\n]{12,}|[A-Z][A-Z0-9_]{3,}\b|(?:caseConfirm|replyFromState|clearerCopyAsk|capReply)\()/.test(l) && !GATE.test(l)) {
      out.push(`${file}:${i + 1}: R1 code fallback after a model reply, no outage gate: ${l.trim().slice(0, 140)}`);
    }
    // R2: a registered code-written reply used outside its definition, with no gate nearby
    const uses = /\b(?:QR_HELD_NOTICE|HELD_NOTICE\[|caseConfirm\(|capReply\(|personContactNotice\()/.test(l) || (file === 'wa_inbound/spec_offer.ts' && /\btext\s*=\s*msg\.body\b/.test(l));
    const compares = /(?:===|!==)\s*\w*HELD_NOTICE|HELD_NOTICE\S*\s*(?:===|!==)|\.includes\(/.test(l);
    // a draft held in a local (`const confirm = caseConfirm(…)`) must meet its gate before the block ends (8 lines)
    const draftLocal = /^\s*const \w+ = /.test(l) && GATE.test(lines.slice(i, i + 9).join('\n'));
    if (uses && !compares && !draftLocal && !GATE.test(near(i))) {
      out.push(`${file}:${i + 1}: R2 a code-written reply is sent with no outage gate: ${l.trim().slice(0, 140)}`);
    }
    // R5: a reply sentence written inline as a literal, English or Arabic, with no outage gate in the statement or near it
    const stmt = /^\s*(?:const|let)\s+(?:text|reply|notice|body|msg|message|answer)\s*=/.test(l) ? lines.slice(i, i + 4).join(' ').split(';')[0] : '';
    if (stmt && /=\s*(?:[^;=]*\?\s*)?['"`](?:[A-Z]|[\u0600-\u06FF])[^'"`]{30,}/.test(stmt) && !GATE.test(stmt) && !GATE.test(near(i))) {
      out.push(`${file}:${i + 1}: R5 a reply sentence written in code, no outage gate: ${stmt.trim().replace(/\s+/g, ' ').slice(0, 140)}`);
    }
  });
  return out;
}

/** R4: the fixed notices are gated where they are made. */
export function noticeFindings(files) {
  const out = [];
  const ms = stripComments(files['wa_inbound/model_says.ts'] || '').join('\n');
  if (!/const notice = io\.outage \? HELD_NOTICE\[lang\] : ''/.test(ms)) out.push('wa_inbound/model_says.ts: R4 holdUnwritten sends HELD_NOTICE without io.outage');
  const qr = Object.entries(files).filter(([k]) => k === 'supplier_api/quote_review_flow.ts' || k.startsWith('supplier_api/quote_review_flow/'))
    .map(([, src]) => stripComments(src || '').join('\n')).join('\n');
  if (!/outage \? await repo\.addMessage\(\{[^}]*body: QR_HELD_NOTICE/.test(qr)) out.push('supplier_api/quote_review_flow.ts: R4 QR_HELD_NOTICE is added without outage');
  if (/await held\(repo, deps, [^;]*\)\.catch/.test(qr)) out.push('supplier_api/quote_review_flow.ts: R4 a failed/killed review adds the held notice without asking the model first');
  const wa = stripComments(WA_HANDLER.map((p) => files[p] || '').join('\n')).join('\n');
  for (const m of wa.matchAll(/holdUnwritten\(\{([^}]*)/g)) if (!/outage:/.test(m[1])) out.push('wa_inbound: R4 holdUnwritten called without outage');
  // the WhatsApp "needs a person" contact notice (ledger 1348): the model writes it, code's words only on the outage
  const rd = stripComments(files['_shared/reasoned_delivery.ts'] || '').join('\n');
  const at = rd.indexOf("if (row.surface === 'wa_inbound.needs_a_person') {");
  const branch = at < 0 ? '' : rd.slice(at, rd.indexOf('\n  }\n', at));
  if (at < 0) out.push('_shared/reasoned_delivery.ts: R4 the wa_inbound.needs_a_person branch moved; re-anchor this check');
  else {
    if (!/await io\.writeNotice\(/.test(branch)) out.push('_shared/reasoned_delivery.ts: R4 the person-contact notice is not written by the model (writeNotice)');
    if (!/const text = personNoticeDraft\(w\.reply, lang\) \|\| \(w\.outage \? personContactNotice\(lang, contact\) : ''\);/.test(branch)) out.push('_shared/reasoned_delivery.ts: R4 the person-contact notice in code words is not gated on the outage, or the model draft skips its language and brand check');
  }
  return out;
}

const read = (p) => fs.readFileSync(FN(p), 'utf8');

/** R6: every 'unwritten' delivery has a fn_reason_held_delivered that returns it to the replay. `sqlFiles`: {name: text}. */
export function unwrittenFindings(deliverySrc, sqlFiles) {
  if (!/via: 'unwritten'/.test(stripComments(deliverySrc).join('\n'))) return [];
  const defs = Object.entries(sqlFiles).filter(([, t]) => /create or replace function public\.fn_reason_held_delivered\s*\(/i.test(t));
  const ok = defs.some(([, t]) => /when p_delivery->>'via' = 'unwritten' then case when attempts >= 3 then 'failed' else 'held' end/.test(t));
  return ok ? [] : ["_shared/reasoned_delivery.ts: R6 a delivery returns via 'unwritten' but no fn_reason_held_delivered sends that row back to 'held' (it stays 'reasoned', never replayed, never escalated)"];
}
const SQL_DIR = path.join(REPO, 'scripts', 'sql');
const sqlFiles = () => Object.fromEntries(fs.readdirSync(SQL_DIR).filter((f) => f.endsWith('.sql')).map((f) => [f, fs.readFileSync(path.join(SQL_DIR, f), 'utf8')]));

test('1339: no reply path sends a code-written sentence unless OpenRouter is down (R1, R2, R5)', () => {
  const found = REPLY_PATHS.flatMap((p) => replyFindings(p, read(p)));
  assert.deepEqual(found, []);
});
test('1339: the fixed notices are gated on the outage where they are made (R4)', () => {
  const files = Object.fromEntries(REPLY_PATHS.map((p) => [p, read(p)]));
  assert.deepEqual(noticeFindings(files), []);
});
test('1339 / ledger 1348: an unwritten delivery goes back to the replay (R6)', () => {
  assert.deepEqual(unwrittenFindings(read('_shared/reasoned_delivery.ts'), sqlFiles()), []);
});
test('1339: every reply-path file this check names exists (a renamed file is re-registered, never silently dropped)', () => {
  for (const p of REPLY_PATHS) assert.ok(fs.existsSync(FN(p)), p);
});

// KNOWN-BAD CONTROLS: the lines main carried before this fix (2f204b792). Each must be caught.
test('known-bad: the old fallbacks are caught', () => {
  // the shape main's inquiry_intake heldReply had (HELD_FOR_SPECS whenever aiReply gave '', model up or not)
  assert.equal(replyFindings('x.ts', '  return r.reply || HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en;\n').length, 1);
  // wa_inbound/spec_offer.ts (index.ts before the split), main: the accepted-offer template sent as-is
  assert.equal(replyFindings('wa_inbound/spec_offer.ts', "            } else if (so.state === 'accepted') { text = msg.body; notice = true; }\n").length, 1);
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

// ledger 1348: the WhatsApp "needs a person" contact notice, exactly as main carried it before this fix (0b9e2425e).
const PERSON_NOTICE_BEFORE = [
  "  if (row.surface === 'wa_inbound.needs_a_person') {",
  "    if (choice !== 'needs_a_person') return { delivered: false, via: 'none', detail: 'reasoned: no person is needed; the reply already went' };",
  "    const contact = (await io.founderContact()) ?? '';",
  '    const text = isAr(question)',
  '      ? `شكرًا لصبركم. إن كنتم تفضّلون التحدث مع شخص مباشرةً، يمكنكم الاتصال أو المراسلة على ${contact}، ويجيب عليه مالك الشركة.`',
  '      : `Thank you for your patience. If you would rather speak to someone directly, call or message ${contact}, which is answered by the owner.`;',
  '    return await whatsapp(io, phone, question, text);',
  '  }',
].join('\n') + '\n';
test('known-bad (R5, ledger 1348): the needs-a-person contact notice written in code is caught', () => {
  const f = replyFindings('_shared/reasoned_delivery.ts', PERSON_NOTICE_BEFORE);
  assert.equal(f.filter((x) => x.includes('R5')).length, 1, f.join('\n'));
  const r4 = noticeFindings({ '_shared/reasoned_delivery.ts': PERSON_NOTICE_BEFORE });
  assert.ok(r4.some((x) => x.includes('not written by the model')) && r4.some((x) => x.includes('not gated on the outage')), r4.join('\n'));
  // an Arabic-only literal is caught as well (the register: it is still code's words)
  assert.equal(replyFindings('x.ts', "    const reply = 'شكرًا لكم، سيتواصل معكم أحد أعضاء فريقنا على هذا الرقم قريبًا جدًا';\n").filter((x) => x.includes('R5')).length, 1);
  // ...and the sanctioned forms pass
  assert.equal(replyFindings('x.ts', "    const text = personNoticeDraft(w.reply, lang) || (w.outage ? personContactNotice(lang, contact) : '');\n").length, 0);
  assert.equal(replyFindings('x.ts', "    const text = said || (outage ? 'Thank you for your patience, a person will follow up.' : '');\n").length, 0);
  assert.equal(replyFindings('x.ts', "    const reply = personContactNotice(lang, contact);\n").filter((x) => x.includes('R2')).length, 1, 'the fixed notice used with no gate');
});
test('known-bad (R6, review of #1669): an unwritten delivery with the live fn_reason_held_delivered is caught', () => {
  const delivery = "    if (!text) return { delivered: false, via: 'unwritten', detail: 'x' };\n";
  // the live definition (27 Oct 2026): anything not delivered and not 'none' keeps its status, so 'reasoned' stays 'reasoned'
  const live = "CREATE OR REPLACE FUNCTION public.fn_reason_held_delivered(p_id bigint, p_delivery jsonb)\n  status = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then 'applied' else status end,\n";
  assert.equal(unwrittenFindings(delivery, { 'a.sql': live }).length, 1);
  const fixed = live.replace("then 'applied' else status end", "then 'applied'\n when p_delivery->>'via' = 'unwritten' then case when attempts >= 3 then 'failed' else 'held' end\n else status end");
  assert.equal(unwrittenFindings(delivery, { 'a.sql': fixed }).length, 0);
  // #1669's first head: the model's draft sent with no language or brand check is caught by the R4 pin
  const first = "  if (row.surface === 'wa_inbound.needs_a_person') {\n    const w = await io.writeNotice(said, lang, {});\n    const text = w.reply.trim() || (w.outage ? personContactNotice(lang, contact) : '');\n  }\n";
  assert.ok(noticeFindings({ '_shared/reasoned_delivery.ts': first }).some((x) => x.includes('language and brand check')));
});

// R7 THE HOLDING LINE (founder ruling 1636, it_engineer, 11 Nov 2026). "When a reply is taking long, the agent first sends a short
// professional holding message ... Then the full reply follows." It is the one fixed sentence sent while the model is UP, and
// it is allowed because it is a status notice and not a reply: it answers nothing, it goes only while the model's reply is still
// being written, and the reply always follows (_shared/holding_notice.ts says why, at length). What keeps it from becoming a
// back door for code-written replies: its words live in ONE place (holding_notice.ts HOLDING_LINE), the one sender is
// wa_inbound/holding.ts sendHoldingLine (which sends `holdingLine(...)` and nothing else), and no other function names it.
test('R7 (1636): the holding line has one home and one sender, and nothing else sends it', () => {
  const home = read('_shared/holding_notice.ts');
  assert.match(home, /export const HOLDING_LINE = \{/);
  const users = functionFilesAll().filter((f) => !/\.test\.ts$/.test(f) && /\bHOLDING_LINE\b|\bholdingLine\(/.test(stripComments(read(f)).join('\n')));
  assert.deepEqual(users.sort(), ['_shared/holding_notice.ts', 'wa_inbound/holding.ts'], 'the holding line is used outside its home and its one sender');
  const sender = stripComments(read('wa_inbound/holding.ts')).join('\n');
  assert.deepEqual([...sender.matchAll(/d\.send\(([^)]*)\)/g)].map((m) => m[1]), ['o.to, text'], 'holding.ts sends one thing');
  // 12 Nov 2026 (final audit W2): the reviewed wordings are several, and the sender hands over the ones this person was given
  // recently so the next is a different one; the words still live only in HOLDING_LINE
  assert.match(sender, /const text = holdingLine\(o\.lang, o\.audience, went\.map\(/);
});
function functionFilesAll() {
  const out = [];
  const walk = (dir) => { for (const e of fs.readdirSync(FN(dir), { withFileTypes: true })) {
    const rel = dir ? dir + '/' + e.name : e.name;
    if (e.isDirectory()) { if (!['node_modules', 'vendor'].includes(e.name)) walk(rel); } else if (e.name.endsWith('.ts')) out.push(rel);
  } };
  walk('');
  return out;
}
