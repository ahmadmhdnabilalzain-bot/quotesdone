// The homepage widget for a visitor who is not signed up (founder ruling, 18 Oct 2026). The model's behaviour on a
// real message is graded live by scripts/eval/widget_visitor_scope.mjs; this file proves the code half: the rules the
// model is given, the sign-up button, and the cap.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { capReply, capReplyByModel, capRules, pastVisitorCap, signupAction, VISITOR_CAP, visitorRules } from './visitor_scope.ts';
import { modelOrOutage } from '../_shared/openrouter_down.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';

const index = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));

Deno.test('general questions: a visitor is told to answer what QuotesDone is, how it works, the fees and trust', () => {
  const r = visitorRules('unknown', 'en');
  for (const topic of ['what QuotesDone is', 'how it works', 'the fees', 'trusted']) assert(r.includes(topic), topic);
  // the visitor rules replace the signed-in follow-up rule; they are not added beside it
  assertMatch(index, /\$\{who \? '- Answer what they asked[^']*' : visitorRules\(audience, replyLang\)\}/);
});

// conversation-quality run, 3 Nov 2026: 2 of 5 widget replies told a visitor "your note has been recorded" (تم تسجيل) and
// in the next sentence that the chat cannot take job details. The widget records nothing on a request.
Deno.test('a visitor is never told a job detail was recorded', () => {
  assertMatch(visitorRules('unknown', 'en'), /never say a detail was noted on, recorded, saved or updated in their request/);
});
// the same run, the judge's finding: "so you won't need to repeat anything" — a visitor posts the request after sign-up
Deno.test('a visitor is never promised they will not need to repeat anything', () => {
  for (const aud of ['unknown', 'customer', 'supplier'] as const) assertMatch(visitorRules(aud, 'en'), /never say they will not need to repeat anything/);
});

Deno.test('an inquiry leads to sign-up with no spec questions, in the visitor\'s language and seat', () => {
  for (const [aud, lang, url] of [['customer', 'en', '/me'], ['unknown', 'ar', '/ar/me'], ['supplier', 'en', '/portal']] as const) {
    const r = visitorRules(aud, lang);
    assert(r.includes('sign up free at ' + url), aud + lang);
    assert(r.includes('Never ask them a question about their job'));
    assert(r.includes('Do not ask anything about the job first'));
    for (const t of ['materials', 'dimensions', 'specifications', 'wardrobe']) assert(r.includes(t), t);
  }
  // a visitor's reply carries the sign-up button; a signed-in caller's does not
  assertMatch(index, /const signup = who \? null : signupAction\(audience, visitorLang\)/);
  assertMatch(index, /\.\.\.\(signup \? \{ signup \} : \{\}\)/);
  // suppliers are always English
  assertMatch(index, /const visitorLang = audience === 'supplier' \? 'en' :/);
  assertEquals(signupAction('supplier', 'ar').url, '/portal');
});

Deno.test('the cap: past it every reply is sign-up only, no full answer runs, counted by conversation and IP', async () => {
  const cases: ['customer' | 'unknown' | 'supplier', 'en' | 'ar'][] = [['customer', 'en'], ['unknown', 'ar'], ['supplier', 'en']];
  for (const [aud, lang] of cases) {
    const r = capReply(aud, lang);
    assert(r.endsWith('\n' + signupAction(aud, lang).url), r);
    assert(!r.includes('?'), 'a cap reply asks nothing');
    assertEquals(/[؀-ۿ]/.test(r), lang === 'ar' && aud !== 'supplier');
  }
  // the cap is checked before the reads and the model, and returns the sign-up reply
  const cap = index.indexOf('pastVisitorCap(rl,'), model = index.indexOf('await answerFromBrief({');
  assert(cap > 0 && cap < model, 'the cap must refuse before the model call');
  assertMatch(index, /return J\(\{ reply, scope: 'public', routed: 'visitor_cap', visitor_cap: true, signup \}\)/);

  // 8 messages in a conversation pass; the 9th is past the cap. Counted on the server (a rate-limiter fake here).
  const hits = new Map<string, number>();
  const rl = (k: string, limit: number) => { const n = (hits.get(k) ?? 0) + 1; hits.set(k, n); return Promise.resolve(n <= limit); };
  const out: boolean[] = [];
  for (let i = 0; i < 9; i++) out.push(await pastVisitorCap(rl, { ip: '1.2.3.4', conv: 'conv-aaaaaaaa' }));
  assertEquals(out, [...Array(VISITOR_CAP.conv).fill(false), true]);
  // a new conversation from the same IP is still counted against the IP
  for (let n = VISITOR_CAP.conv; n < VISITOR_CAP.ip; n++) await pastVisitorCap(rl, { ip: '1.2.3.4', conv: 'conv-b' + n + 'bbbbbb' });
  assertEquals(await pastVisitorCap(rl, { ip: '1.2.3.4', conv: 'conv-new-cccccc' }), true, 'IP cap of ' + VISITOR_CAP.ip);
  // and a visitor with no conversation id is counted by IP alone
  assertEquals(await pastVisitorCap(rl, { ip: '9.9.9.9', conv: '' }), false);
});

// ── 1339 (27 Oct 2026): the cap reply is the MODEL'S; capReply's code text only on a true OpenRouter outage ──────────
// Founder, ledger 1339: "the engineer and customer support never replies without llm unless the server of open router is
// down". capReplyByModel is the real aiReply over a stubbed gateway here: no network, no paid call.
function gateway(reply: () => LlmReply) {
  const seen: { system: string; input: string }[] = [];
  const deps = {
    gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
    llm: (_p: string, system: string, input: string) => { seen.push({ system, input }); return Promise.resolve(reply()); },
  } as unknown as ThinkDeps;
  return { deps, seen };
}
const say = (answer: string): LlmReply => ({ content: JSON.stringify({ answer }), model: 'stub' } as LlmReply);
const fail = (error: string): LlmReply => ({ content: null, error } as LlmReply);
const sent = async (g: ReturnType<typeof gateway>, aud: 'customer' | 'unknown' | 'supplier' = 'unknown', lang: 'en' | 'ar' = 'en') =>
  modelOrOutage(await capReplyByModel(g.deps, { audience: aud, lang, message: 'how much for a 3x2m wardrobe?' }), capReply(aud, lang));

Deno.test('1339: past the cap, the model writes the sign-up reply when it is up; the code text never goes', async () => {
  const g = gateway(() => say('Thanks for your questions. To carry on, sign up free and our sales engineer takes it from there:\n/me'));
  const r = await sent(g);
  assertEquals(r, 'Thanks for your questions. To carry on, sign up free and our sales engineer takes it from there:\n/me');
  assert(r !== capReply('unknown', 'en'));
  assertMatch(g.seen[0].system, /THIS VISITOR HAS USED THE MESSAGES/, 'the model is told what to write (capRules)');
  assert(!/\b8\b|40/.test(capRules('unknown', 'en')), 'the cap number is never given to the model');
  // the link must be carried: a draft without it is rewritten by the model, never patched by code
  let n = 0;
  const g2 = gateway(() => (++n === 1 ? say('Thanks, please sign up to continue.') : say('Thanks, please sign up free to continue:\n/portal')));
  assertEquals(await sent(g2, 'supplier'), 'Thanks, please sign up free to continue:\n/portal');
  assertMatch(g2.seen[1].input, /must appear exactly/);
});

Deno.test('1339: only a TRUE outage (5xx, network, timeout) sends capReply\'s code text', async () => {
  for (const err of ['gateway_http_503', 'gateway_http_500 upstream', 'client_error: error sending request', 'client_timeout_20000ms', 'circuit_open']) {
    assertEquals(await sent(gateway(() => fail(err))), capReply('unknown', 'en'), err);
  }
  assertEquals(await sent(gateway(() => fail('gateway_http_502')), 'customer', 'ar'), capReply('customer', 'ar'));
});

Deno.test('1339: a 4xx is never an outage: no code-written text (the widget shows the sign-up button alone)', async () => {
  for (const err of ['gateway_http_400 upstream timeout', 'gateway_http_401', 'gateway_http_429 rate_limited', 'gateway_http_404 connection']) {
    assertEquals(await sent(gateway(() => fail(err))), '', err);
  }
  // a model that answered but whose drafts all fail the guard: not an outage either
  const refused = await sent(gateway(() => say('A wardrobe that size costs AED 7,350.')));
  assertEquals(refused, '', 'the model answered (refused every time): nothing is sent, and never the code text');
  const widget = Deno.readTextFileSync(new URL('../../../src/components/ChatWidget.tsx', import.meta.url));
  assert(widget.includes("const capOnly = j.done?.visitor_cap === true && !!signup;") && widget.includes("show(reply || (capOnly ? '' : t.err), signup)"), 'an empty cap reply shows the button, not the error line');
  // a turn past the cap is stored under the visitor's conversation, or it vanishes from the chat on the next reload (browser proof, 2 Nov 2026)
  assert(index.includes("gap_task_id: null, ...(hasConv ? { conv_id: visitorKey(conv) } : {})"), 'the cap reply row carries conv_id');
  // known-bad control: the pre-fix row had no conv_id, which the same assertion would have refused
  assert(!"gap_task_id: null, audience: logParty(who, audience, source, true), path".includes('conv_id'));
});

Deno.test('1339: customer-safe: an internal sentence or an unstated figure the model writes is never sent (ledger 1338)', async () => {
  const r = await sent(gateway(() => say('Thanks for chatting with us. To continue, sign up free:\n/me\nOur openrouter budget per visitor is AED 7,350.')));
  assert(r.includes('/me'), r);
  assert(!/openrouter|7,350/i.test(r), r);
});

Deno.test('1339: index.ts sends the cap reply only through modelOrOutage over the model-written reply', () => {
  assertMatch(index, /const capped = await capReplyByModel\(defaultDeps\(admin, 'site_assistant'\)/);
  assertMatch(index, /const reply = modelOrOutage\(capped, capReply\(audience, visitorLang\)\)/);
  assertEquals(index.split('capReply(').length - 1, 1, 'capReply is used once, inside modelOrOutage');
});
