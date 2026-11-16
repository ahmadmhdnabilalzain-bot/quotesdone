// RULINGS 1195/1196/1197 (12 Oct 2026): in wa_inbound every CONVERSATION reply is written by a model in that turn.
// the handler cannot be driven end to end offline, so this reads it (index.ts and the modules it calls): every text that reaches sendWa(From, …) is assigned
// only from the model (say / sayFor / sayC, model_says.ts), from a guard over such text, from the HELD NOTICE (the
// fixed receipt when no model answered — a notification, review of #1335), or '' — and the one named notification
// (the accepted-offer confirmation). It fails the moment a literal sentence, a routine's own message, an FAQ row or a
// deterministic answer is assigned to a reply variable again. The menu's sends are proved by menu_flow.test.ts
// (1195-1197 test); the writer and the held notice by model_says.test.ts.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { functionFiles } from '../../../scripts/lib/function_sources.mjs';

// The handler's own code: every runtime file of the function except the sibling modules that were never part of index.ts.
const SIBLINGS = ['coverage.ts', 'directive_gate.ts', 'founder_directive.ts', 'founder_queries.ts', 'menu.ts', 'menu_flow.ts', 'model_says.ts', 'wa_row.ts'];
const src = functionFiles('wa_inbound').filter((f: string) => !SIBLINGS.some((s) => f.endsWith('/' + s)))
  .map((f: string) => Deno.readTextFileSync(new URL('../../../' + f, import.meta.url))).join('\n');
const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

Deno.test('1195-1197: every WhatsApp reply variable is assigned only model-written text, the held notice, or nothing', () => {
  const sends = [...code.matchAll(/sendWa\(From, (\w+)\)/g)].map((m) => m[1]);
  // 't' is holdUnwritten's send, which only ever sends HELD_NOTICE (model_says.test.ts)
  // 'receipt' is the I-HEARD RECEIPT of a voice note (hear.ts, it_engineer 10 Nov 2026): the speaker's OWN transcribed words in
  // a fixed frame (_shared/speech_to_text.ts heardReceipt), so a mishearing is corrected before it becomes a request. It says
  // nothing of ours beyond the frame; the answer to what they said is the model's, in the same turn, as for typed text.
  assertEquals(new Set(sends), new Set(['replyS', 'reply', 'replyD', 't', 'receipt']), 'a new direct send appeared: prove its text is model-written here');
  const sources = new Set([...sends.filter((v) => v !== 't' && v !== 'receipt'), 'text', 'out']);
  assertEquals([...code.matchAll(/(?:const|let) receipt\s*=\s*([^;\n]+)/g)].map((m) => m[1].trim()), ['toContact(heardReceipt(heard.text, audience))'],
    'the receipt frames the transcript and nothing else');
  assert(code.indexOf('if (!heard.ok) {') < code.indexOf('const receipt ='), 'the receipt is sent only for a voice note that was heard');
  const bad: string[] = [];
  for (const v of sources) {
    for (const m of code.matchAll(new RegExp(`(?:^|[^\\w.])(?:let |const )?${v}\\s*=\\s*([^;\\n]+(?:\\n\\s+[?:+][^;\\n]+)*)`, 'g'))) {
      const rhs = m[1].trim();
      const ok = /^''$/.test(rhs) || /^String\(out\.reply/.test(rhs)
        || /^(?:\(?await (?:say|sayFor|sayC)\b)/.test(rhs)
        || /^(?:text|out|reply|replyS|replyD) \? (?:toContact|bidiSafe)\((?:text|out|reply)\.slice\(0, 1200\)\) : ''$/.test(rhs)
        || /^reply\.trim\(\) \? bidiSafe\(reply\.slice\(0, 1200\)\) : ''$/.test(rhs)
        || /^\(await say\(situation\)\)\.slice\(0, 1200\)$/.test(rhs)
        || /^\(drafted \? adopt\(drafted\) : await say\(situation\)\)\.slice\(0, 1200\)$/.test(rhs)   // the model's draft asked beside the classification
        // the status and app lanes (status_lane.ts, ruling 1571): sayLane is askModel on status_reply, the model's words too
        || /^\(drafted \? adopt\(drafted\) : lane === 'conversation' \? await say\(situation\)\s*: await t\.sayLane\(lane, lean, String\(route\?\.deterministic_reply \|\| ''\)\)\)\.slice\(0, 1200\)$/.test(rhs)
        || rhs === 'toContact(reply)'                   // the outgoing guard over the model's own text
        || rhs === 'h.notice'                           // the HELD NOTICE: a notification when no model answered
        || (v === 'text' && rhs === 'msg.body')         // the accepted-offer template: OpenRouter-down fallback only (1339)
        // THE HOLDING LINE (holding.ts, founder ruling 1636): a fixed status notice sent only while the model's reply is still
        // being written, never in its place; the reply follows. Proved once per turn and never after the reply: holding.test.ts.
        // 12 Nov 2026 (final audit W2): the reviewed wordings are several; the ones this person was given recently are avoided
        || (v === 'text' && rhs === "holdingLine(o.lang, o.audience, went.map((r) => String(r.body ?? '')))")
        // 12 Nov 2026 (final audit W5): a lane reply that cannot answer is replaced by the full path's model reply (general_turn.ts)
        || (v === 'reply' && rhs === 'full' && /const full = \(await say\(situation\)\)\.slice\(0, 1200\);\n\s+if \(full\) reply = full;/.test(code));
      if (!ok) bad.push(v + ' = ' + rhs.slice(0, 120));
    }
  }
  assertEquals(bad, [], 'reply text assigned from something other than the model:\n' + bad.join('\n'));
});

// founder_instruction 1339 (27 Oct 2026): the accepted-offer confirmation is a reply to their message, so the model writes
// it from the template; the template itself goes out only when OpenRouter is down (sayOutage), and it is marked.
Deno.test('1339: the accepted-offer confirmation is the model\'s; the template only when OpenRouter is down, and marked', () => {
  assert(/if \(!text && t\.sayOutage\) \{ text = msg\.body; notice = true; \}/.test(code), 'the template is gated on the outage');
  assert(!/so\.state === 'accepted'\) \{ text = msg\.body;/.test(code), 'the template is sent as-is again while the model is up');
});
Deno.test('1339: every held notice is gated on the outage of the last model call', () => {
  assert(/holdUnwritten\(\{[^}]*outage: t\.sayOutage/.test(code), 'heldTurn passes the outage of the last say to holdUnwritten');
  assert(/t\.sayOutage = !r\.text && r\.outage;/.test(code), 'sayFor records whether OpenRouter was down');
});

Deno.test('1195-1197: no stored-sentence road remains, and no path leaves the person silent', () => {
  for (const gone of ["route: 'deterministic'", 'welcomeFirstContact(', 'supportReply(', 'publicSys', 'FACTS_SHARED', "p_answered_by: 'deterministic'"]) {
    assert(!code.includes(gone), gone + ' is back in wa_inbound');
  }
  // spec offer, founder setting, document, supplier price, supplier instruction (16 Nov 2026), main reply: each sends the held
  // notice when no model answered
  assertEquals((code.match(/const h = await heldTurn\(/g) || []).length, 6, 'every direct no-model path sends the held notice');
  assert(/held: \(r\) => heldTurn\(/.test(code), 'the menu sends the held notice too');
});

Deno.test('review of #1335: the per-number rate key is carried, and the model\'s own escalate flag is OR-ed with the router', () => {
  assert(code.includes("rateKey: signal ? 'wa-spec:' + From : 'wa:' + From"), 'the per-number ceiling (wa:<From>) reaches the gateway; a speculative draft has its own bucket');
  assert(code.includes('const escalate = route?.needs_a_person === true || t.modelEscalate;'), 'a complaint the router misses still reaches a person');
});

// customer_support, 2 Nov 2026: the reply is asked beside the classification. A draft asked before the class is known is adopted ONLY
// when the real route's inputs are exactly the ones it was composed on, and asking writes nothing the turn keeps, so a discarded draft
// can neither escalate, flag the turn nor be sent (the one send is the one at the end).
// Review of branch B (12 Nov 2026): the title said "the route"; since 10 Nov the rule is the same FACTS (composed text), and a few
// hours of "no missing hard fact" adoption (5400590a5, reverted) sent wrong drafts: speculation.ts says when adoption may widen.
Deno.test('a speculative reply is adopted only on the same facts it was composed on, and asking never touches the turn', () => {
  assert(/fn_wa_route_dry', \{ p_phone: From, p_body: Body\.slice\(0, 4000\), p_needs_person: false, p_intent: 'none' \}/.test(code), 'the draft is composed on the dry route for class (no person, none)');
  // 10 Nov 2026 (it_engineer, R4/R5): adopted when the real route's composed facts ARE the facts the draft was composed on,
  // on the conversation lane, with no person needed (it was intent 'none' only: 0 of 7 real turns).
  assert(code.includes("const sameFacts = speculative ? (await t.specFacts) === situation : false;"), 'the draft is compared on the facts it answered');
  assert(code.includes("speculative && sameFacts && lane === 'conversation' && needsPerson !== true && route?.needs_a_person !== true && !t.factsAnswer"), 'adopted only on the same facts, the conversation lane and no person');
  // discarded drafts cannot use up the real reply's rate allowance, and are aborted when discarded
  assert(code.includes("specAbort.signal") && /askModel\([^\n]*specAbort\.signal\)/.test(code), 'the speculative call carries the abort signal, which is what selects its own bucket');
  assert(code.includes("if (!(spec && spec.text)) specAbort.abort();") && code.includes('specAbort.abort();\n'), 'a discarded draft is aborted');
  assertEquals((code.match(/'wa:' \+ From/g) || []).length >= 1 && code.includes("'wa-spec:' + From"), true, 'two buckets: wa: for the real reply, wa-spec: for drafts');
  assert(code.includes("itFinding('wa_inbound:route_dry_unavailable'"), 'a dry route that is missing or failing is an IT finding, not silence');
  const ask = code.slice(code.indexOf('const askModel ='), code.indexOf('const adopt ='));
  assert(!/modelEscalate|sayOutage|sayProblems/.test(ask), 'askModel must not set the turn\'s escalate / outage / problems');
  // 10 Nov 2026 (ruling 1571): and by sayLane, the status lane's askModel (status_lane.ts)
  // 10 Nov 2026 (it_engineer, R4/R5): and the welcome line drafted beside the classification, adopted only for the welcome asked with
  // the same inputs (classification.ts write)
  assertEquals((code.match(/adopt\(/g) || []).length, 4, 'adopt is called by sayFor, sayLane, the speculative draft and the drafted welcome line, and nowhere else');
  assert(/if \(welcomeDraft && !r\.must\?\.length && \(await welcomeDraft\.key\) === writeKey\(r\)\) \{/.test(code), 'the drafted welcome line is adopted only for the same inputs');
  assert(/const sayLane = async \(lane: 'status' \| 'app', facts: string, databaseAnswer: string\) =>\s*adopt\(await askModel\(/.test(code), 'sayLane adopts only askModel\'s answer');
});
