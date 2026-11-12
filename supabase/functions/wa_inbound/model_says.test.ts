// modelSays with a stubbed model. No network, no paid call. Rulings 1195-1197: the words are the model's; code hands
// over what happened as facts, and when no model answers the result is '' (the caller sends nothing).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { modelSays } from './model_says.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';

function stub(answers: (string | null)[]) {
  const calls: { system: string; input: string; o: Record<string, unknown> }[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, system: string, input: string, o: Record<string, unknown>) => {
      calls.push({ system, input, o });
      const a = answers.shift();
      return Promise.resolve((a == null ? { content: null, error: 'down' } : { content: a, model: 'stub' }) as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;
  return { deps, calls };
}
const A = (answer: string) => JSON.stringify({ answer });

Deno.test('the routine result reaches the model as facts and the model writes the reply', async () => {
  const s = stub([A('Done: your quotation for the ZZ DEMO job is now AED 9,000.')]);
  const r = await modelSays(s.deps, { audience: 'supplier', lang: 'ar', message: 'make it 9000', situation: 'They asked to change their quotation price to AED 9000. pricing routine: {"ok":true,"old":10000,"new":9000}',
    subject: { fixture: true, phone: '+971500000021' } });
  assertEquals(r.text, 'Done: your quotation for the ZZ DEMO job is now AED 9,000.');
  // the facts ride in the turn itself, after the cached conversation (chat_history.ts, 18 Oct 2026), not in the system prompt
  assert(s.calls[0].input.includes('"new":9000'), 'the routine result is in the facts');
  assert(s.calls[0].system.includes('suppliers are always answered in English'), 'a supplier is answered in English even when they wrote Arabic');
  assertEquals((s.calls[0].o.subject as Record<string, unknown>).fixture, true, 'a ZZ DEMO turn is tagged for the rehearsal window');
});

Deno.test('no model answers: the text is empty — never a canned sentence', async () => {
  const s = stub([null, null, null, null]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'hi', situation: 'greet them' });
  assertEquals(r.text, '');
  assert(s.calls.length >= 2, 'the backup model was asked too: ' + r.attempts.join(','));
});

Deno.test('a thrown model is the same as no model: empty, nothing invented', async () => {
  const deps = { gate: () => Promise.resolve(null), llm: () => { throw new Error('boom'); }, embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }) } as unknown as ThinkDeps;
  assertEquals((await modelSays(deps, { audience: 'visitor', lang: 'en', message: 'x', situation: 'y' })).text, '');
});

import { HELD_NOTICE, holdUnwritten, UNWRITTEN_SURFACE } from './model_says.ts';
Deno.test('OpenRouter down: the held notice is sent (supplier in English) and the turn is filed for a model retry', async () => {
  const sent: string[] = []; const filed: Record<string, unknown>[] = [];
  const r = await holdUnwritten({ from: 'whatsapp:+971500000021', body: 'ZZ DEMO: هل تدفعون عمولة؟', messageSid: 'SMzz', audience: 'supplier', lang: 'ar',
    situation: 'a supplier asked about commission', why: 'no_model_answer', outage: true, enabled: () => Promise.resolve(true),
    send: (t) => { sent.push(t); return Promise.resolve({ ok: true }); },
    rpc: (fn, a) => { filed.push({ fn, ...a }); return Promise.resolve({ data: 7, error: null }); } });
  assertEquals(sent, [HELD_NOTICE.en]);
  assertEquals(r.held_id, 7);
  assertEquals(filed[0].fn, 'fn_reason_hold');
  assertEquals(filed[0].p_surface, UNWRITTEN_SURFACE);
  assertEquals((filed[0].p_subject as Record<string, unknown>).phone, 'whatsapp:+971500000021');
  assert(String((filed[0].p_request as Record<string, unknown>).question).includes('a supplier asked about commission'));
});

Deno.test('the rate key reaches the gateway call, and the model\'s escalate flag comes back', async () => {
  const s = stub([JSON.stringify({ answer: 'I am sorry about this. Your payment is recorded against your request, and a person from our team now has your message and will contact you here today to resolve it with you. If you would like to speak to someone straight away, call or WhatsApp us on the number below during working hours.', escalate: true })]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO: you took my money and vanished', situation: 'a complaint', rateKey: 'wa:whatsapp:+971500000021' });
  assertEquals(s.calls[0].o.rateKey, 'wa:whatsapp:+971500000021');
  assertEquals(r.escalate, true);
});

// prevented by: this test. Run 5 (qd_run:321d13ae, agent_runs 3793567) held a WhatsApp turn 73.7 s in serial model
// calls and still ended llm_failed. A hanging model now costs at most the reply budget: each call is given only the
// time left (never more than PER_CALL_MS), no call starts with under MIN_CALL_MS left, and the result is '' so the
// caller sends the held notice and queues the turn.
Deno.test('a hanging model ends the reply inside its budget, each call given only the time left', async () => {
  const timeouts: number[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    // the gateway honours the caller's timeout: it hangs until then and answers nothing
    llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => {
      timeouts.push(Number(o.timeoutMs));
      return new Promise<LlmReply>((res) => setTimeout(() => res({ content: null, error: 'timeout' } as LlmReply), Number(o.timeoutMs)));
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;
  const r = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'how long does installation take?', situation: 'facts', budgetMs: 9_000 });
  assertEquals(r.text, '', 'no model answered: the caller sends the held notice');
  assert(r.ms < 10_000, `the turn took ${r.ms} ms against a 9 s budget`);
  assertEquals(timeouts.length, 1, 'no second call starts with under MIN_CALL_MS left');
  assert(timeouts[0] <= 9_000, `the call was given ${timeouts[0]} ms, more than the budget`);
  assert(r.attempts.some((a) => a.startsWith('deadline')), 'the attempts say the clock ran out: ' + r.attempts.join(','));
});

Deno.test('the default WhatsApp budget caps a reply call at 25 s', async () => {
  const s = stub([A('Installation of aluminium windows on a villa usually takes a few days, depending on the area.')]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'how long?', situation: 'facts' });
  assert(r.text.length > 0);
  assert(Number(s.calls[0].o.timeoutMs) <= 25_000, 'a reply call keeps no more than 25 s');
});

Deno.test('the 45 s clock runs from arrival: time spent before the model call is taken off the budget', async () => {
  const { budgetLeft, WA_REPLY_BUDGET_MS, WA_SEND_MARGIN_MS } = await import('./model_says.ts');
  assertEquals(budgetLeft(1_000, 1_000), WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS);
  assertEquals(budgetLeft(0, 30_000), WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS - 30_000);
  assertEquals(budgetLeft(0, 90_000), 0);   // the budget is spent: no call starts and the turn is queued
  assertEquals(budgetLeft(0, 50_000), WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS - 50_000);   // a 50 s routing still leaves the reply its time
});

Deno.test('no budget left: no model call starts and the text is empty, so the caller sends the held notice', async () => {
  const { deps, calls } = stub(['{"reply":"late answer"}']);
  const said = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'hi', situation: 'x', budgetMs: 0 });
  assertEquals(calls.length, 0);
  assertEquals(said.text, '');
});

// founder_instruction 1339 (27 Oct 2026): "the engineer and customer support never replies without llm unless the server of
// open router is down". A model that answered and was refused: the turn is filed for the model, NO fixed notice goes out.
Deno.test('1339: model up, nothing safe to send: no code-written notice, the turn is still filed for the model', async () => {
  const sent: string[] = []; const filed: Record<string, unknown>[] = [];
  const r = await holdUnwritten({ from: 'whatsapp:+971500000022', body: 'ZZ DEMO: question', messageSid: 'SMzy', audience: 'customer', lang: 'en',
    situation: 'a customer asked a question', why: 'guard_refused', outage: false, enabled: () => Promise.resolve(true),
    send: (t) => { sent.push(t); return Promise.resolve({ ok: true }); },
    rpc: (fn, a) => { filed.push({ fn, ...a }); return Promise.resolve({ data: 8, error: null }); } });
  assertEquals(sent, [], 'a code-written notice went out while the model was up');
  assertEquals(r.notice, '');
  assertEquals(r.held_id, 8);
  assertEquals(filed[0].fn, 'fn_reason_hold');
});
Deno.test('1339: modelSays reports an outage only when no call reached a model', async () => {
  const mk = (res: unknown) => ({ gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }), llm: () => Promise.resolve(res) }) as unknown as ThinkDeps;
  assertEquals((await modelSays(mk({ content: null, error: 'gateway_http_502' }), { audience: 'visitor', lang: 'en', message: 'x', situation: 'y' })).outage, true);
  assertEquals((await modelSays(mk({ content: JSON.stringify({ answer: 'openrouter circuit_open' }), model: 'm' }), { audience: 'visitor', lang: 'en', message: 'x', situation: 'y' })).outage, false);
});

// Run 41530397323 (main), the lean "scam" turn: the model was up, nothing it wrote inside the budget could be used, and the
// person got no reply for the turn. Here every call that carries the company brief answers something unusable (an object cut off
// mid-answer); the one brief-less last-chance ask answers properly and IS the reply. On the pre-fix modelSays the text is ''.
Deno.test('the model is up but nothing passes in the budget: one brief-less last chance writes the reply', async () => {
  const calls: Record<string, unknown>[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => {
      calls.push(o);
      return Promise.resolve((o.sysStable ? { content: '{"answer":"I am sorry to hear that, let me', model: 'stub' }
        // (12 Nov 2026: the sample answer named our WhatsApp number; a WhatsApp reply may no longer give the number they are on, W5)
        : { content: A('I am sorry this happened. Your message has been passed to our team; you can also write to management@quotesdone.com.'), model: 'stub' }) as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;
  // (12 Nov 2026, re-check R3: the facts say the hand-off was filed, as compose.ts writes them when a person is needed)
  const r = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO you took my money and vanished, this is a scam', situation: 'They need a person: say their message has been passed to our team.', situationAnswers: true });
  assert(r.text.includes('management@quotesdone.com'), 'the last chance wrote the reply: ' + r.attempts.join(' | '));
  assert(calls.some((o) => !o.sysStable && !o.sysShared), 'the last chance carried no brief');
  assert(r.attempts.some((a) => a.startsWith('last-chance')), 'and is named in the attempts: ' + r.attempts.join(' | '));
  assert(r.attempts.some((a) => a.includes('unparseable')), 'the unusable answer is recorded with what it said: ' + r.attempts.join(' | '));
});

Deno.test('control: an outage gets no last chance (the held notice owns that), and a speculative draft gets none', async () => {
  const s = stub([]);   // every call: error 'down' -> no; use a real outage error below
  const deps = { ...s.deps, llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => { s.calls.push({ system: '', input: '', o }); return Promise.resolve({ content: null, error: 'gateway_http_503 upstream unavailable' } as LlmReply); } } as unknown as ThinkDeps;
  const r = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'hi', situation: 'greet them' });
  assertEquals(r.text, '');
  assertEquals(r.outage, true);
  assert(!r.attempts.some((a) => a.startsWith('last-chance')), 'no last chance in an outage: ' + r.attempts.join(' | '));
  const spec = stub(['prose', 'prose', 'prose', 'prose', 'prose', 'prose']);
  const r2 = await modelSays(spec.deps, { audience: 'customer', lang: 'en', message: 'hi', situation: 'greet them', signal: new AbortController().signal });
  assert(!r2.attempts.some((a) => a.startsWith('last-chance')), 'no last chance for a speculative draft');
});

Deno.test('a reply object with a real line break inside the answer string is read, not dropped', async () => {
  // (12 Nov 2026: the sample answer named our WhatsApp number, which a WhatsApp reply may no longer give, W5; a link keeps the line break)
  const s = stub(['{"answer":"Your message is with our team. You can also post it here:\nhttps://quotesdone.com/me\nor write to management@quotesdone.com","escalate":true}']);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO I want to speak to a person please', situation: 'They need a person.' });
  assert(r.text.includes('https://quotesdone.com/me\n'), 'read: ' + r.attempts.join(' | '));
  assertEquals(s.calls.length, 1, 'the first answer was used; no second rung');
  assertEquals(r.escalate, true);
});

// Review of #1816: without the brief a company question can only be answered from memory. A fact question whose first ask
// produced nothing usable gets NO brief-less answer: the caller did not say the facts answer the turn. Fails on fe852ccd.
Deno.test('a company fact question whose first ask failed gets no brief-less answer (the facts do not answer it)', async () => {
  const calls: Record<string, unknown>[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => {
      calls.push(o);
      return Promise.resolve((o.sysStable ? { content: '{"answer":"We vet suppliers by', model: 'stub' }
        : { content: A('We vet every supplier with a site visit and three references.'), model: 'stub' }) as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;
  const r = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO how do you vet suppliers?', situation: 'No intent row fits.' });
  assertEquals(r.text, '', 'nothing invented: ' + r.attempts.join(' | '));
  assert(calls.every((o) => o.sysStable), 'no call went without the brief');
  assert(!r.attempts.some((a) => a.startsWith('last-chance')));
});

// Re-review of #1816: a spent sender bucket gets no last chance either (it carries no key, so it would be unchecked spend).
Deno.test('a spent sender bucket: one model call, no last chance, no text, not an outage', async () => {
  const calls: Record<string, unknown>[] = [];
  const deps = { gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
    llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => { calls.push(o);
      return Promise.resolve((o.rateKey ? { content: null, error: 'rate_limited' } : { content: A('Please reach our team on +1 218 316 6814.'), model: 'stub' }) as LlmReply); } } as unknown as ThinkDeps;
  const r = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO you took my money', situation: 'They need a person.', situationAnswers: true, rateKey: 'wa:whatsapp:+971500000031' });
  assertEquals(calls.length, 1, r.attempts.join(' | '));
  assert(!r.attempts.some((a) => a.startsWith('last-chance')));
  assertEquals(r.text, '');
  assertEquals(r.outage, false);
});

// Final audit 12 Nov 2026, W5: "6" (Talk to a person) was answered with "+1 218 316 6814", the number the person was writing to.
// A draft that gives our own WhatsApp number is refused and rewritten; the rule says what the hand-off really is. Fails on main
// (the first draft is the reply).
Deno.test('a WhatsApp reply never gives the person the number they are writing to: the draft is rewritten', async () => {
  const s = stub([
    JSON.stringify({ answer: 'You can speak with a person on WhatsApp, Monday to Friday, 9am-6pm GST:\n+1 218 316 6814\nmanagement@quotesdone.com', escalate: true }),
    JSON.stringify({ answer: 'I have passed your message to our team. For a member of the team to reply to you here, send MENU and choose "Talk to a person". By e-mail: management@quotesdone.com', escalate: true }),
  ]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO 6', situation: 'They need a person.' });
  assert(!r.text.replace(/\D/g, '').includes('12183166814'), 'our number was sent: ' + r.text);
  assert(r.text.includes('Talk to a person'), r.attempts.join(' | '));
  assert(s.calls[0].system.includes('never give them a phone or WhatsApp number'), 'the rule is in the prompt');
});

// Re-check of 12 Nov 2026, R3: "Your message has been passed to our team" was said when no hand-off was filed. A draft that says
// so when the facts do not is rewritten. Fails on dc9a17b75 (the first draft is the reply).
Deno.test('a reply never says the message was passed on when no hand-off was filed', async () => {
  const s = stub([
    JSON.stringify({ answer: 'Your message has been passed to our team.', escalate: false }),
    JSON.stringify({ answer: 'For a member of the team to reply to you here, send MENU and choose "Talk to a person".', escalate: false }),
  ]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO 6', situation: 'No intent row fits.' });
  assert(!/passed/i.test(r.text) && r.text.includes('Talk to a person'), r.attempts.join(' | '));
  const ok = stub([JSON.stringify({ answer: 'Your message has been passed to our team.', escalate: true })]);
  const r2 = await modelSays(ok.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO refund now', situation: 'They need a person: say their message has been passed to our team.' });
  assertEquals(r2.text, 'Your message has been passed to our team.', 'said when the facts say it');
});

// Re-check of 12 Nov 2026, R13: an invented keyword ("Reply REGISTER ...") and our internal sources named to the person ("The portal
// guide doesn't specify ...") are rewritten. Fails on dc9a17b75.
Deno.test('no invented reply keyword and no internal source named to the person', async () => {
  const { wordingProblems } = await import('./model_says.ts');
  assertEquals(wordingProblems('Reply REGISTER and I will send him the link.').length, 1);
  assertEquals(wordingProblems("The portal guide doesn't specify a separate control for profile photos.").length, 1);
  assertEquals(wordingProblems('Send MENU and choose "Talk to a person". Reply STOP to opt out.'), []);
  assertEquals(wordingProblems('Please send your trade licence as a PDF.'), []);
  const s = stub([JSON.stringify({ answer: 'Reply REGISTER and I will send him the link.', escalate: false }),
    JSON.stringify({ answer: 'He can register free here: https://quotesdone.com/suppliers', escalate: false })]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO how does my cousin register?', situation: 'No intent row fits.' });
  assert(!/REGISTER/.test(r.text), r.attempts.join(' | '));
});

// Review of branch B (12 Nov 2026), items 7 and 8: true statements are kept, and file instructions are not keywords. Fails on
// c4a467389 (the forwarded/escalated sentences and "Reply YES 1043" / "Send PDF" were rewritten; a self-escalating draft lost its
// true "escalated to our team"; the our-number rewrite told the model to say "passed to our team", 4 calls for one reply).
Deno.test('true hand-off statements are kept: forwarded to the suppliers, escalated to the sales engineer, and our own escalation', async () => {
  const { passedProblems, wordingProblems } = await import('./model_says.ts');
  assertEquals(passedProblems('Your request was forwarded to the suppliers with the change.', 'No intent row fits.'), []);
  assertEquals(passedProblems('Your request has been escalated to our sales engineer, who is chasing the suppliers.', 'No intent row fits.'), []);
  assertEquals(passedProblems('Your message has been passed to our team.', 'No intent row fits.').length, 1);
  const own = stub([JSON.stringify({ answer: 'I am sorry about this. I have escalated your complaint to our team and they will review it.', escalate: true })]);
  const r = await modelSays(own.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO the supplier never showed up', situation: 'No intent row fits.' });
  assert(r.text.includes('escalated your complaint to our team') && r.escalate, 'a draft that escalates itself keeps its true statement');
  assertEquals(own.calls.length, 1);
  const num = stub([JSON.stringify({ answer: 'You can reach a person on WhatsApp at +1 218 316 6814.', escalate: false }),
    JSON.stringify({ answer: 'For a member of the team to reply to you here, send MENU and choose "Talk to a person".', escalate: false })]);
  const n = await modelSays(num.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO can I talk to someone', situation: 'No intent row fits.' });
  assertEquals(num.calls.length, 2, 'one rewrite, not four: ' + n.attempts.join(' | '));
  assert(!/passed/i.test(n.text));
  assertEquals(['Reply YES 1043 to confirm.', 'reply yes 1043 within 30 minutes', 'Please send PDF or JPG copies.', 'Send PDF of your trade licence.',
    'Send DWG or PDF drawings.', 'Send RFQ details here.', 'Reply ASAP please.', 'Type OK when done.'].filter((t) => wordingProblems(t).length), []);
  assertEquals(wordingProblems('Reply HUMAN and the team will look into it.').length, 1);
});

// Review of branch B, ROUND 2 (12 Nov 2026), item 1: the false "passed to our team" went out when the re-asked draft said it again
// (2 calls) and when the re-ask found the model down (3 calls). Now neither is sent: the turn is a refused draft, held for the model
// replay with the claim named, and the held notice goes out when the model is down. Fails on ebf5a76f6 (both texts were the claim).
Deno.test('a false "passed to our team" is never sent: not when the re-ask repeats it, not when the re-ask finds the model down', async () => {
  const CLAIM = JSON.stringify({ answer: 'Your message has been passed to our team.', escalate: false });
  const rep = stub([CLAIM, CLAIM, CLAIM, CLAIM]);
  const a = await modelSays(rep.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO where is my refund', situation: 'No intent row fits.' });
  assertEquals(a.text, '', 'the repeated claim is not the reply: ' + a.attempts.join(' | '));
  assertEquals(a.outage, false);
  assert(a.problems?.some((p) => p.includes('no hand-off was filed')), 'the replay is told why');
  let n = 0;
  const downDeps = { ...rep.deps, llm: () => Promise.resolve((n++ === 0 ? { content: CLAIM, model: 'stub' } : { content: null, error: 'gateway_http_503 upstream unavailable' }) as LlmReply) } as unknown as ThinkDeps;
  const b = await modelSays(downDeps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO where is my refund', situation: 'No intent row fits.' });
  assertEquals(b.text, '', 'model down on the re-ask: the claim is not sent: ' + b.attempts.join(' | '));
  assertEquals(b.outage, true, 'so the held notice goes out and the turn is filed for the model');
  // the refused-draft path: the person still gets an answer (the held notice now, the model replay later), never silence
  const { holdUnwritten } = await import('./model_says.ts');
  const sent: string[] = []; const filed: Record<string, unknown>[] = [];
  const h = await holdUnwritten({ audience: 'customer', lang: 'en', from: 'whatsapp:+971500000093', messageSid: 'ZZDEMO1', body: 'ZZ DEMO where is my refund',
    situation: 'No intent row fits.', why: 'no_model_answer', outage: b.outage, problems: b.problems, enabled: () => Promise.resolve(true),
    send: (t: string) => { sent.push(t); return Promise.resolve({ ok: true }); },
    rpc: (_f: string, args: Record<string, unknown>) => { filed.push(args); return Promise.resolve({ data: 7, error: null }); } } as Parameters<typeof holdUnwritten>[0]);
  assert(h.sent && sent.length === 1 && filed.length === 1, 'held notice sent and the turn filed for the replay');
  // a last chance that says it again is not sent either
  const lc = stub([CLAIM, CLAIM, CLAIM, CLAIM, CLAIM, CLAIM]);
  const c = await modelSays(lc.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO where is my refund', situation: 'No intent row fits.', situationAnswers: true });
  assertEquals(c.text, '', 'the last chance repeating the claim is refused too: ' + c.attempts.join(' | '));
  // control: when the facts say the hand-off was filed, the claim is true and is sent on the first call
  const ok = stub([CLAIM]);
  const d = await modelSays(ok.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO refund now', situation: 'They need a person: say their message has been passed to our team.' });
  assertEquals(d.text, 'Your message has been passed to our team.');
  assertEquals(ok.calls.length, 1);
  // review round 2, item 4: TRN and BOQ are things we really ask for, not invented keywords
  const { wordingProblems } = await import('./model_says.ts');
  assertEquals(['Reply TRN 100234567800003 to confirm it.', 'Type BOQ items one per line.'].filter((t) => wordingProblems(t).length), []);
});
