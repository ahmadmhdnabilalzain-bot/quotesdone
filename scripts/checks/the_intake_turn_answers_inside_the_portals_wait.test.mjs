// THE INTAKE TURN ANSWERS INSIDE THE PORTAL'S WAIT, AND EVERY SAFEGUARD STAYS ON IT (27 Oct 2026, sales_engineer).
//
// MEASURED (production, read-only): agent_runs fn:inquiry_intake 24-27 Oct, 53 turns, p50 11.5 s, p95 98.5 s, max
// 130 s; PR #1370's mystery-shopper saw ~72 s and two runs past 90 s. The portal waits 30 s. ai_cost_log put the time in
// think()'s exact-spec reading (a 20-34 s plan, then one or two 38-47 s answer passes) after a 5-7 s interview call,
// with nothing bounding the turn. The fix is one clock per turn (inquiry_intake/turn_clock.ts) and the two intake
// decisions without a planner (_shared/reasoned_decisions.ts). The unit tests prove the behaviour with a mocked model
// (inquiry_intake/turn_clock.test.ts, _shared/think_deadline.test.ts); this reads the source so the wiring cannot
// quietly come undone, and so no safeguard is dropped to win the time back:
//   - exact specs or held: a required spec left blank sends the request back to needs_info, never ready;
//   - the held-spec questions: the hold still asks the open spec; with a model reading only a TAPPED option of it is read by
//     code (tappedHeldAnswer, 15 Nov 2026: a reply about something else was stored as the held spec's answer), and the code
//     reader for a turn with no model reading still lets no deferral fill it;
//   - the reply guards (licence number, "AI"), now on the interview's own reply as well as the held reply;
//   - think()'s cross-family check: the verify step still goes to a model of another family (counterpartModel).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { functionSource } from '../lib/function_sources.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readCustomerPortal, readSource } from '../lib/portal_sources.mjs';
import { sharedModuleSource } from '../lib/function_sources.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(REPO, p), 'utf8');
const num = (src, name) => { const m = new RegExp(`\\b${name}\\s*=\\s*([\\d_]+)`).exec(src); assert.ok(m, `${name} is not a number literal`); return Number(m[1].replace(/_/g, '')); };

const INDEX = functionSource('inquiry_intake');
const CLOCK = read('supabase/functions/inquiry_intake/turn_clock.ts');
const DECISIONS = read('supabase/functions/_shared/reasoned_decisions.ts');
const THINK = sharedModuleSource('think');
const SLOTS = read('supabase/functions/inquiry_intake/slots.ts');
const GUARD = read('supabase/functions/_shared/support_reply_guard.ts');
const PORTAL = readCustomerPortal();
const NEW_REQUEST = readSource('src/components/me/NewRequest.tsx');
const TEXT = read('src/components/me/portalText.ts');

test('the turn budget fits inside the portal wait, with room for the edge and the network', () => {
  const wait = num(PORTAL, 'CALL_TIMEOUT_MS');
  const budget = num(CLOCK, 'TURN_BUDGET_MS');
  assert.ok(budget < 25_000, `TURN_BUDGET_MS ${budget} is not under the 25 s p95 target`);
  assert.ok(budget + 5_000 <= wait, `TURN_BUDGET_MS ${budget} leaves under 5 s of the portal's ${wait} ms`);
});

test('every model step of the turn runs on the one clock', () => {
  assert.match(INDEX, /const clock = new TurnClock\(\)/, 'the turn has no clock');
  assert.match(INDEX, /await llm\(\[[^\n]*llmFail, clock\.modelDeadline\(\)\)/, 'the interview call is not on its MODEL_WAIT_MS deadline');
  assert.match(INDEX, /signal: AbortSignal\.timeout\(waitMs\)/, 'the gateway fetch has no timeout');
  assert.match(INDEX, /client_timeout_ms: waitMs/, 'the gateway is not told how long the turn waits');
  assert.match(INDEX, /await tradeOf\(defaultDeps\(admin, 'inquiry_intake'\), \{[\s\S]{0,400}?deadline: clock\.deadline\(\)/, 'the trade reasoning is not on the clock');
  assert.match(INDEX, /statedSpecs\(defaultDeps\(admin, 'inquiry_intake'\), \{[\s\S]{0,400}?deadline: clock\.deadline\(\)/, 'the exact-spec reading is not on the clock');
  const started = INDEX.indexOf('const specRead = category && toRead.length && allText.trim() && clock.canStart()');
  assert.ok(started > 0 && started < INDEX.indexOf('const raw = await llm('), 'the exact-spec reading is not started alongside the interview call');
  assert.match(INDEX, /: clock\.canStart\(\) \? startReading\(category, blank\) : null/, 'a reading after the interview call starts without checking the clock');
  assert.match(INDEX, /await heldReply\([^;]*?clock\.replyDeadline\(\)[,)]/, 'the held reply has its own clock instead of the turn\'s reply deadline');
  assert.doesNotMatch(INDEX, /Date\.now\(\) \+ \d{2}_?\d{3}\)/, 'a model step was given its own fixed allowance again');
});

// The founder, 27 Oct 2026: "the engineer and customer support never replies without llm unless the server of open
// router is down". The clock may skip a step that writes no reply; it never turns a reply into code text.
test('the model writes every reply: the clock never cuts a reply-writing call short', () => {
  const wait = num(PORTAL, 'CALL_TIMEOUT_MS');
  // MODEL_WAIT_MS is the turn's one end, REPLY_END_MS (second review, 12 Nov 2026): 25 s, as the gateway answers a cut call
  // about 2 s after its timeout (15 s steps ended at 16.7-17.1 s), so the response leaves by about 27 s
  assert.match(CLOCK, /export const MODEL_WAIT_MS = REPLY_END_MS;/, 'the interview call ends somewhere other than the turn');
  const modelWait = num(CLOCK, 'REPLY_END_MS');
  assert.ok(modelWait + 2_000 + 2_000 <= wait - 1_000, `REPLY_END_MS ${modelWait} plus the gateway's 2 s and the save leave under 1 s of the portal's ${wait} ms`);
  const replyMin = num(CLOCK, 'REPLY_MIN_MS');
  assert.ok(modelWait > num(CLOCK, 'TURN_BUDGET_MS') && modelWait <= wait - 2_000, `MODEL_WAIT_MS ${modelWait} must exceed the turn budget and sit inside the portal's ${wait} ms`);
  assert.ok(replyMin >= 10_000, `REPLY_MIN_MS ${replyMin} is too short for a real model attempt`);
  // corrected 12 Nov 2026 (founder ledger 1642; review of the effort fix, finding 4): the minimum holds below the turn's one
  // end, REPLY_END_MS (MODEL_WAIT_MS is the same line), so reply steps in series can no longer pass the portal's wait (turns of 26-29 s measured)
  assert.match(CLOCK, /replyDeadline\(minMs = REPLY_MIN_MS\): number \{ return Math\.min\(this\.t0 \+ REPLY_END_MS, Math\.max\(this\.deadline\(\), this\.now\(\) \+ minMs\)\); \}/, 'a reply deadline can be shorter than REPLY_MIN_MS, or run past the turn');
  assert.match(CLOCK, /export const REPLY_END_MS = 25_000;/, 'the turn\'s one end moved');
  // Every code-composed reply (and a guard refusal) is written by the model on the reply deadline (slots.ts intakeVoice);
  // the state's code text only when OpenRouter is down (founder_instruction 1339; the full rule is
  // scripts/checks/the_intake_reply_is_the_models_unless_openrouter_is_down.test.mjs).
  assert.match(INDEX, /const v = await intakeVoice\(defaultDeps\(admin, 'inquiry_intake'\), \{[\s\S]{0,400}?deadline: clock\.replyDeadline\(\)/, 'a code-composed reply is not sent to the model on the reply deadline');
  assert.match(INDEX, /out\.assistant_message = await voice\(replyFromState\(/, 'a refused reply is replaced by code text without asking the model');
  assert.doesNotMatch(INDEX, /rewrite\?\.reply \|\| replyFromState\(/, 'the old fallback (code text whenever the model call gave nothing) is back');
});

test('the two intake decisions have nothing to plan or look up', () => {
  const trade = /export async function tradeOf[\s\S]*?\n}\n/.exec(DECISIONS)?.[0] ?? '';
  const stated = /export async function statedSpecs[\s\S]*?\n}\n/.exec(DECISIONS)?.[0] ?? '';
  assert.match(trade, /plan: \{ steps: \[\] \}/, 'tradeOf plans again');
  assert.match(stated, /readerOfTheirOwnText\(/, 'statedSpecs is not a reader of the customer\'s own words');
  assert.match(stated, /queueWhenHeld: false/, 'an unfinished reading is filed for a paid replay nothing consumes');
  for (const [name, body] of [['tradeOf', trade], ['statedSpecs', stated]]) {
    assert.match(body, /withDeadline\(deps, o\.deadline\)/, `${name} ignores the caller's deadline`);
    assert.doesNotMatch(body, /stakes: 'high'/, `${name} changed its stakes`);
  }
  assert.match(THINK, /export function withDeadline\(/);
});

test('exact specs or held: a required spec left blank sends the request back to needs_info', () => {
  assert.match(INDEX, /const absent = required\.filter\(isAbsent\);\s*if \(absent\.length\) \{\s*status = 'needs_info';/, 'the canonical gate no longer holds a request with a blank required spec');
  assert.match(INDEX, /if \(v\.value && blank\.some\(/, 'a reasoned spec is filled without a value');
  assert.match(THINK, /export function valueInEvidence\(/, 'the verbatim-evidence guard is gone');
  assert.match(THINK, /export function keepProvenFields\(/, 'a reader no longer drops an unproven field');
});

test('the held-spec questions stay: a tapped answer is read by code, the model reads the rest, and a deferral fills nothing', () => {
  // 15 Nov 2026 (journey A; rulings 1663/1664/1666): with the model's reading on the turn, code reads only a tap of the held spec
  assert.match(INDEX, /tappedHeldAnswer\(checklist, heldKey, text\)/, 'the held spec\'s tapped answer is not read');
  assert.doesNotMatch(INDEX, /readHeldAnswer\(checklist, heldKey, text\)/, 'code reads the customer\'s words for the held spec over the model again');
  // since 10 Nov 2026 (ledger 1572) the open specs asked again are the exhausted ones the customer did not say they do not
  // know: a "does not know" is never asked again, not even by the hold
  assert.match(INDEX, /const askAgain = slotExhausted\.filter\(\(k\) => !slotUnknown\.has\(k\)\);\s+heldNext = heldAsk\(checklist, askAgain, slotLang\)/, 'a held turn no longer asks the open spec');
  assert.match(SLOTS, /const DEFERRAL = new RegExp\(/, 'the deferral list is gone');
  assert.match(SLOTS, /isDeferral\(text\)\) return null/, 'a deferral can fill a held spec again');
});

test('the reply guards run on every reply this turn sends', () => {
  assert.match(GUARD, /const LICENCE = /, 'the licence guard is gone');
  assert.match(GUARD, /const AI_EN = /, 'the AI-word guard is gone');
  assert.match(INDEX, /guardSupportReply\(String\(out\.assistant_message \|\| ''\), slotLang\)/, 'the interview reply is sent unguarded');
  assert.match(SLOTS, /const r = await aiReply\(/, 'the held reply no longer goes through aiReply and its guard');
});

test('the cross-family check in think() is untouched', () => {
  assert.match(THINK, /deps\.llm\('verify'[\s\S]{0,400}counterpartModel: model/, 'the verify step no longer names the author for a reviewer of another family');
});

test('the portal shows a progress state and a retry, never an error, for a turn it stopped waiting for', () => {
  assert.match(NEW_REQUEST, /turn_id: tid/, 'the intake call carries no turn id, so a retry would record the message twice');
  assert.match(NEW_REQUEST, /if \(turnNotReached\(r\)\) \{[^\n]*retry: \{ message, turnId: tid \}/, 'a timed-out turn is not offered a retry');
  const late = NEW_REQUEST.indexOf('if (turnNotReached(r))');
  const err = NEW_REQUEST.indexOf("errText(r, lang, 'nr_err_generic')");
  assert.ok(late > 0 && err > late, 'the generic error is shown before the timeout is recognised');
  assert.match(NEW_REQUEST, /r\.error === 'qd_timeout'/);
  assert.match(NEW_REQUEST, /setTimeout\(\(\) => setSlow\(true\), SLOW_TURN_MS\)/, 'a slow turn shows no progress state');
  assert.match(NEW_REQUEST, /runIntake\(m\.retry\.message, null, m\.retry\.turnId\)/, 'the retry does not resend the same turn');
  for (const k of ['nr_slow', 'nr_late', 'nr_retry']) assert.equal((TEXT.match(new RegExp(`\\b${k}:`, 'g')) || []).length, 2, `${k} is not in both languages`);
  assert.match(INDEX, /placeUserTurn\(turns, text, turnIdOf\(b\.turn_id\)\)/, 'the server adds a retried message again');
  assert.match(INDEX, /if \(placed === 'landed'\) \{[\s\S]{0,300}storedReply\(draft\)/, 'a retry of a turn that landed is answered again instead of from the row');
});
