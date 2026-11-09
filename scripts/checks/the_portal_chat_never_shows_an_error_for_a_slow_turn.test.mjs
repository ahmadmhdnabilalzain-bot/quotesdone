// THE PORTAL CHAT NEVER SHOWS AN ERROR FOR A SLOW TURN (customer_support owns the conversation, it_engineer the latency;
// 27 Oct 2026, found while verifying ledger 1248; founder ledger 1200: "zero tolerance for mistakes").
//
// MEASURED (production, ZZ DEMO wardrobe replay 27 Oct 07:41-08:13Z): every portal assistant turn took 58-150 s and turn 7
// hit the edge's 150 s idle wall; the 504 page is not JSON, PortalShell's r.json() threw, and the customer read
// "Something went wrong" in the middle of the conversation. Cause: the sales_engineer `assist` turn ran supportReply ->
// think(): 3-5 SERIAL model calls (plan, answer, check, corrective rewrite, plain-language rewrite) with no turn clock.
//
// This file fails if any part of the fix is undone:
//   1. the client reads every outcome without throwing, and shows only approved text (src/lib/portalReply.ts);
//   2. the panel never prints an error line for a turn; it looks for the stored answer, then says the question is saved;
//   3. the turn is one streamed model call on the conversation route, inside PORTAL_TURN_MS, and streams to the portal;
//   4. no think() chain (supportReply, quoteQuestion) is back on the turn's path.
// The model-side behaviour is tested by supabase/functions/_shared/brief_answer.test.ts and sales_engineer/portal_turn.test.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';
import { answerAfter, noVerdict, readReply, savedLineDue } from '../../src/lib/portalReply.ts';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const ndjson = (lines, { cut = false } = {}) => new Response(new ReadableStream({ start(c) {
  for (const l of lines) c.enqueue(new TextEncoder().encode(JSON.stringify(l) + '\n'));
  if (cut) c.error(new Error('network dropped')); else c.close();
} }), { headers: { 'content-type': 'application/x-ndjson; charset=utf-8' } });

test('a 504 page (not JSON) reads as "no reply yet", never a throw', async () => {
  const r = new Response('<html><body>504 Gateway Time-out</body></html>', { status: 504, headers: { 'content-type': 'text/html' } });
  const out = await readReply(r);
  assert.equal(out.reply, '');
  assert.match(out.failed, /HTTP 504, not JSON/);
});

test('a streamed answer shows its sentences as they come and ends on the approved text', async () => {
  const seen = []; const status = [];
  const out = await readReply(ndjson([{ t: 'status', text: 'Writing your answer…' }, { t: 'delta', text: 'MDF is fine. ' }, { t: 'delta', text: 'Plywood holds screws better.' },
    { t: 'done', reply: 'MDF is fine. Plywood holds screws better.', ok: true }]), { text: (x) => seen.push(x), status: (x) => status.push(x) });
  assert.equal(out.reply, 'MDF is fine. Plywood holds screws better.');
  assert.deepEqual(seen, ['MDF is fine. ', 'MDF is fine. Plywood holds screws better.']);
  assert.equal(status[0], 'Writing your answer…');
});

test('a reset drops what was shown; a done without a reply clears it; a cut stream clears it', async () => {
  let shown = 'x';
  const reset = await readReply(ndjson([{ t: 'delta', text: 'Wrong figure. ' }, { t: 'reset' }, { t: 'delta', text: 'Right.' }, { t: 'done', reply: 'Right.' }]), { text: (x) => { shown = x; } });
  assert.equal(reset.reply, 'Right.'); assert.equal(shown, 'Right.');
  const empty = await readReply(ndjson([{ t: 'delta', text: 'Half an ' }, { t: 'done', error: 'no_answer' }]), { text: (x) => { shown = x; } });
  assert.equal(empty.reply, ''); assert.equal(shown, '', 'an unfinished answer must not stay on screen');
  shown = 'x';
  const cut = await readReply(ndjson([{ t: 'delta', text: 'Half an ' }], { cut: true }), { text: (x) => { shown = x; } });
  assert.equal(cut.reply, ''); assert.equal(shown, ''); assert.match(cut.failed, /stream cut/);
});

test('the stored answer is found after the question that asked it, not an older one', () => {
  const turns = [{ role: 'user', content: 'width?' }, { role: 'assistant', content: 'old' }, { role: 'user', content: 'doors?' }, { role: 'assistant', content: 'Sliding.' }];
  assert.equal(answerAfter(turns, 'doors?'), 'Sliding.');
  assert.equal(answerAfter([...turns, { role: 'user', content: 'handles?' }], 'handles?'), '');
  assert.equal(answerAfter(null, 'x'), '');
});

// founder_instruction 1339 (27 Oct 2026): "the engineer and customer support never replies without llm unless the server of
// open router is down". The saved line is the panel's own text: only for a transport failure or done.outage === true.
test('1339: the saved line only when the answer never arrived or OpenRouter was down; never while the model is up', async () => {
  const cut = await readReply(ndjson([{ t: 'delta', text: 'Half ' }], { cut: true }));
  assert.equal(savedLineDue(cut), true, 'a cut stream is a transport failure');
  const page = await readReply(new Response('<html>504</html>', { status: 504, headers: { 'content-type': 'text/html' } }));
  assert.equal(savedLineDue(page), true, 'a 504 page is a transport failure');
  const down = await readReply(ndjson([{ t: 'done', ok: false, error: 'no_answer', outage: true }]));
  assert.equal([noVerdict(down), savedLineDue(down)].join(), 'false,true', 'OpenRouter down: the saved line');
  const up = await readReply(ndjson([{ t: 'delta', text: 'Refused words. ' }, { t: 'done', ok: false, error: 'no_answer', outage: false }]));
  assert.equal([noVerdict(up), savedLineDue(up)].join(), 'false,false', 'the model was up: no code-written line');
  const unsaid = await readReply(new Response(JSON.stringify({ ok: false, error: 'no_answer' }), { status: 503, headers: { 'content-type': 'application/json' } }));
  assert.equal(savedLineDue(unsaid), false, 'no outage field is not an outage');
  assert.equal(savedLineDue(cut, 'The stored answer.'), false, 'a stored answer found later is shown instead');
  const s = read('src/components/me/PortalShell.tsx');
  assert.match(s, /if \(!reply && token && noVerdict\(j\)\)/, 'only an answer that never arrived is looked for');
  assert.match(s, /savedLineDue\(j, reply\) \? \[\.\.\.m, \{ role: 'notice', content: t\(stored \? 'asst_saved' : 'asst_not_sent'\) \}\] : m/, 'the saved line must be gated by savedLineDue');
  const se = functionSource('sales_engineer');
  assert.match(se, /error: 'no_answer', outage, attempts: a\.attempts/, 'the assist 503 must carry outage');
  assert.match(se, /const outage = a\.outage === true;/);
  assert.match(se, /error: 'no_model_credential', outage: true \}/, 'no credential is an outage (openrouter_down.ts)');
});

test('the panel never prints an error line for a turn; it streams, looks for the stored answer, then says it is saved', () => {
  const s = read('src/components/me/PortalShell.tsx');
  assert.ok(!s.includes("t('asst_err')"), 'the error line is back in the portal assistant');
  assert.match(s, /Accept: 'application\/x-ndjson, application\/json'/, 'the portal no longer asks for the stream');
  assert.match(s, /readReply\(r, on\)/);
  assert.match(s, /storedAnswer\(token, q\)/);
  assert.match(s, /'asst_saved'/);
  const txt = read('src/components/me/portalText.ts');
  assert.ok(!/asst_err:/.test(txt), 'asst_err copy came back');
  assert.equal((txt.match(/asst_saved:/g) || []).length, 2, 'the saved notice must exist in English and Arabic');
});

test('the turn is one streamed call on the conversation route, inside its clock, with no think() chain on its path', () => {
  const s = functionSource('sales_engineer');
  const a = s.indexOf("if (action === 'assist') {");
  // the turn is the assist handler: the last one in actions/portal.ts, so it ends where the next module's header comment begins
  const turn = s.slice(a, s.indexOf('\n// sales_engineer — ', a));
  assert.ok(a > 0 && turn.length > 0);
  assert.match(turn, /const deadline = t0 \+ PORTAL_TURN_MS;/);
  assert.match(turn, /await answerFromBrief\(\{/);
  assert.match(turn, /taskClass: 'customer_portal_assistant'/, 'the portal reply must stay on the conversation route (ruling 1219)');
  assert.match(turn, /images, deadline,/, 'the deadline must reach the model ladder');
  // the streamed words are shown as written: the prompt must ask for plain text (27 Oct: replies read {"answer":"..."})
  assert.match(turn, /rules: portalRules\(\), plainText: true \}/, 'the portal prompt must ask for plain text, not aiReply\'s JSON');
  assert.match(turn, /\.\.\.wrappedReply\(t\)[,\]]/, 'a reply wrapped as JSON must be refused sentence by sentence');
  assert.match(turn, /\.\.\.plainLanguage\(t, lang\)\]/, 'the plain-language gate (1013 item 7) must hold every sentence');
  // the reply-language rule (3 Nov 2026) holds the whole reply, never one sentence (review of #1830, 4 Nov 2026)
  assert.match(turn, /checkWhole: \(t: string\) => replyLanguageProblems\(t, lang\),/, 'the reply-language rule must hold the whole reply');
  for (const gone of ['supportReply(', 'think(', 'quoteQuestion(']) assert.ok(!turn.includes(gone), 'a serial reasoning chain is back on the portal turn: ' + gone);
  assert.ok(!s.includes('quoteQuestion('), 'the own-quote decision chain is back');
  assert.match(s, /if \(b\.action !== 'assist'\) return plain\(inner\);/, 'only assist streams; every other action is answered as before');
  assert.match(s, /streamReply\(STATUS\[lang\]/);
  const clock = read('supabase/functions/sales_engineer/portal_turn.ts');
  const ms = Number((clock.match(/PORTAL_TURN_MS = ([\d_]+);/) || [])[1]?.replace(/_/g, ''));
  assert.ok(ms > 0 && ms <= 75_000, 'PORTAL_TURN_MS must stay under half the 150 s edge wall: ' + ms);
});
