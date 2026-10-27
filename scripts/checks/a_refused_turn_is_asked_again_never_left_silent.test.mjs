// customer_support + sales_engineer: A REFUSED TURN IS ASKED AGAIN; NO CUSTOMER OR SUPPLIER IS LEFT SILENT (27 Oct 2026).
// Founder ruling 1339, verbatim: "the engineer and customer support never replies without llm unless the server of open
// router is down". The independent review of #1640 (head 4d5c6cfd0, which contains #1647) found that a turn where the model
// is up but every draft and the retry are refused got NO reply: the portal showed nothing and filed nothing; WhatsApp and
// the supplier thread were filed but only the 15-minute think() replay asked again, and a second refusal closed the row
// as 'applied'. The request chat's held-for-trade turn (#1646) pushed an EMPTY message and filed nothing.
//
// This check fails if any wire of the fix is undone (the behaviour is tested in supabase/functions/_shared/reask.test.ts):
//   W1 every refusing surface files its turn for the re-ask (fn_reason_hold on its re-ask surface, with request.reask and a
//      per-turn context.turn_id), and the portal and the request chat say pending;
//   W2 the re-ask surfaces are one list in TypeScript and SQL; the 15-minute replay no longer claims them; a job checks
//      every minute and has a seat; sales_engineer serves reask_turns;
//   W3 the portal and the request chat show a pending state (UI text in English and Arabic) and poll until the answer lands;
//   W4 the hand-off notice is the model's: its fixed line only behind an outage.
// On 4d5c6cfd0 this file fails (none of it exists); the known-bad controls replay the pre-fix lines.
// prevented by: this file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { answerRightAfter, pendingDue, waitingOf } from '../../src/lib/portalReply.ts';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const SQL = 'scripts/sql/a_refused_turn_is_asked_again_within_minutes_never_left_silent.sql';
const code = (src) => src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*|--)/.test(l)).join('\n');

/** The request chat (#1646) must never leave an empty bubble while the model is up: both the held-for-trade turn and the
 *  main reply file a refused turn for the re-ask, through one helper, and say pending. */
export function intakeFindings(src) {
  const out = [];
  const s = code(src);
  if (/\n\s*turns\.push\(\{ role: 'assistant', text: heldMsg, agent: ACTOR \}\);/.test(s)) out.push('the held-for-trade reply is pushed even when it is empty');
  if (!/const fileReask = async[\s\S]{0,900}p_surface: 'inquiry_intake\.unwritten_reply'/.test(s)) out.push('the request chat has no way to file a refused turn for the re-ask');
  if (!/hv\.by === 'none' \? await fileReask\(/.test(s)) out.push('a refused held-for-trade turn is not filed for the re-ask');
  if (!/replyBy === 'none'\s*\n?\s*\? await fileReask\(/.test(s)) out.push('a refused main reply (an empty bubble) is not filed for the re-ask');
  if ((s.match(/pending: reaskTid !== null/g) || []).length < 2) out.push('the request chat is not told the turn is pending');
  return out;
}
/** The portal turn must file the refused turn and say pending. */
export function portalFindings(src) {
  const out = [];
  const s = code(src);
  const a = s.indexOf("if (action === 'assist') {");
  const turn = s.slice(a, s.indexOf('// ── CONVERSATIONS', a) > 0 ? s.indexOf('// ── CONVERSATIONS', a) : undefined);
  if (!/const owed = !reply && a\.outage !== true;/.test(turn)) out.push('the portal turn does not decide that a refused turn is owed an answer');
  if (!/p_surface: 'sales_engineer\.portal_unwritten'/.test(turn)) out.push('a refused portal turn is not filed for the re-ask');
  if (!/error: 'no_answer', outage, attempts: a\.attempts, pending, held_id/.test(turn)) out.push('the portal is not told the turn is pending');
  return out;
}

test('W1: every surface that can refuse files its turn for the re-ask, with the turn as data and its own turn id', () => {
  assert.deepEqual(portalFindings(read('supabase/functions/sales_engineer/index.ts')), []);
  assert.deepEqual(intakeFindings(read('supabase/functions/inquiry_intake/index.ts')), []);
  const ms = code(read('supabase/functions/wa_inbound/model_says.ts'));
  assert.match(ms, /turn_id: 'wa:'/, 'WhatsApp: two people sending the same words must be two turns (qhash reads context)');
  assert.match(ms, /reask: \{ message: question,/, 'WhatsApp: the turn must be filed as data for the re-ask');
  assert.match(code(read('supabase/functions/wa_inbound/index.ts')), /outage: sayOutage, problems: sayProblems,/, 'WhatsApp: the refused drafts\' problems must be filed');
  const sa = code(read('supabase/functions/supplier_api/index.ts'));
  assert.match(sa, /turn_id: 'qr:'/);
  assert.match(sa, /reask: \{ message: q,[^}]*audience: 'supplier', lang: 'en'/, 'supplier thread: filed in English');
});

test('W2: one list of re-ask surfaces in TypeScript and SQL; the replay leaves them; a job every minute with a seat; the action exists', () => {
  const ts = read('supabase/functions/_shared/reask.ts');
  const tsList = [...(ts.match(/REASK_SURFACES = \[([^\]]+)\]/)[1].matchAll(/'([a-z_.]+)'/g))].map((m) => m[1]).sort();
  const sql = read(SQL);
  const sqlList = [...(sql.match(/fn_reask_surfaces\(\)[\s\S]*?select array\[([\s\S]*?)\]::text\[\]/)[1].matchAll(/'([a-z_.]+)'/g))].map((m) => m[1]).sort();
  assert.deepEqual(sqlList, tsList);
  assert.deepEqual(tsList, ['inquiry_intake.unwritten_reply', 'sales_engineer.portal_unwritten', 'supplier_api.quote_review_unwritten', 'wa_inbound.unwritten_reply']);
  assert.match(sql, /and not \(surface = any\(public\.fn_reask_surfaces\(\)\)\)/, 'the 15-minute think() replay must not claim a re-ask turn (one asker per turn)');
  assert.match(sql, /cron\.schedule\('reask_refused_turns', '\* \* \* \* \*'/);
  assert.match(sql, /\('cron_job', 'reask_refused_turns', 'customer_support'/, 'no job without a seat');
  assert.match(sql, /if h\.attempts >= 3 then[\s\S]*fn_reask_hand_off/, 'bounded: the third refusal hands the turn to its seat');
  for (const fn of ['fn_reask_surfaces()', 'fn_reask_due(integer)', 'fn_reask_record(bigint, jsonb)', 'fn_reask_hand_off(bigint)', 'fn_reask_reviewed_reply(bigint, text, text)', 'fn_reask_kick()']) {
    assert.ok(sql.includes('revoke execute on function public.' + fn + ' from public, anon, authenticated;'), 'no revoke for ' + fn);
  }
  assert.ok(existsSync(new URL('../../scripts/sql/pending/a_refused_turn_is_asked_again_within_minutes_never_left_silent.txt', import.meta.url)), 'a pending file needs its note');
  assert.match(code(read('supabase/functions/sales_engineer/index.ts')), /if \(action === 'reask_turns'\) \{/);
  assert.match(ts, /otherFamilyFirst: true, effort: 'high'/, 'the re-ask must ask differently, not repeat the refused call');
  assert.match(ts, /const safe = await customerSafe\(/, 'customerSafe must run again on the portal re-ask');
});

test('W3: the portal and the request chat show a pending state and poll until the answer lands', () => {
  const ps = code(read('src/components/me/PortalShell.tsx'));
  assert.match(ps, /pendingDue\(j\) \? \[\.\.\.m, \{ role: 'pending', q, content: t\('asst_working'\) \}\]/);
  assert.match(ps, /if \(!reply && pendingDue\(j\)\) watch\(q\);/);
  assert.match(ps, /answerRightAfter\(j && j\.turns, question\)/);
  assert.match(ps, /m\.role === 'user' \|\| m\.role === 'assistant'/, 'a pending marker is UI state: never sent back as history');
  const nr = code(read('src/components/me/NewRequest.tsx'));
  assert.match(nr, /const pending = r\.pending && r\.reask_turn_id && !r\.assistant_message \? r\.reask_turn_id : null;/);
  assert.match(nr, /if \(pending\) watchTurn\(/);
  assert.match(nr, /poll_turn_id: tid/);
  const txt = read('src/components/me/portalText.ts');
  for (const k of ['asst_working', 'asst_with_team', 'nr_working', 'nr_with_team']) assert.equal((txt.match(new RegExp(k + ':', 'g')) || []).length, 2, k + ' in English and Arabic');
  assert.match(code(read('supabase/functions/inquiry_intake/index.ts')), /const pollId = turnIdOf\(b\?\.poll_turn_id\);/);
});

test('W4: the hand-off notice is the model\'s; its fixed line only behind an outage', () => {
  const rd = code(read('supabase/functions/_shared/reasoned_delivery.ts'));
  assert.match(rd, /const text = w\.reply\.trim\(\) \|\| \(w\.outage \? HOLDING_NOTICE\[lang\] : ''\);/);
  assert.ok(!/Your question is now with our team and a person is handling it; we will reply here\.'\s*;?\s*\n\s*return await whatsapp/.test(rd), 'the fixed line is sent unconditionally again');
});

test('the portal helpers: pending only when filed; the answer is the one directly under the question', () => {
  assert.equal(pendingDue({ reply: '', streamed: true, done: { error: 'no_answer', outage: false, pending: true }, failed: null }), true);
  assert.equal(pendingDue({ reply: '', streamed: true, done: { error: 'no_answer', outage: false }, failed: null }), false);
  assert.equal(pendingDue({ reply: 'x', streamed: true, done: { pending: true }, failed: null }), false);
  const turns = [{ role: 'user', content: 'shelf?' }, { role: 'user', content: 'doors?' }, { role: 'assistant', content: 'Sliding.' }];
  assert.equal(answerRightAfter(turns, 'shelf?'), '', 'a later turn\'s reply is never taken for the pending one');
  assert.equal(answerRightAfter(turns, 'doors?'), 'Sliding.');
  assert.deepEqual(waitingOf({ waiting: [{ id: 1, message: 'shelf?', state: 'with_team' }, { message: '' }] }).map((w) => w.state), ['with_team']);
  assert.deepEqual(waitingOf(null), []);
});

// KNOWN-BAD CONTROLS: the lines 4d5c6cfd0 / #1646 carried. Each must be caught.
test('known-bad: the pre-fix lines are caught', () => {
  const intakeBefore = "        const heldMsg = hv.text;\n        turns.push({ role: 'assistant', text: heldMsg, agent: ACTOR });\n";
  assert.equal(intakeFindings(intakeBefore).length, 5);
  const portalBefore = "    if (action === 'assist') {\n      const outage = a.outage === true;\n      return J({ ok: false, seat: 'sales_engineer', answered: false, error: 'no_answer', outage, attempts: a.attempts, task_id: r.task_id ?? null }, 503);\n    // ── CONVERSATIONS\n";
  assert.equal(portalFindings(portalBefore).length, 3);
});
