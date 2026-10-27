// The homepage widget for a visitor who is not signed up (founder ruling, 18 Oct 2026). The model's behaviour on a
// real message is graded live by scripts/eval/widget_visitor_scope.mjs; this file proves the code half: the rules the
// model is given, the sign-up button, and the cap.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { capReply, pastVisitorCap, signupAction, VISITOR_CAP, visitorRules } from './visitor_scope.ts';

const index = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));

Deno.test('general questions: a visitor is told to answer what QuotesDone is, how it works, the fees and trust', () => {
  const r = visitorRules('unknown', 'en');
  for (const topic of ['what QuotesDone is', 'how it works', 'the fees', 'trusted']) assert(r.includes(topic), topic);
  // the visitor rules replace the signed-in follow-up rule; they are not added beside it
  assertMatch(index, /\$\{who \? '- Answer what they asked[^']*' : visitorRules\(audience, replyLang\)\}/);
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

Deno.test('the cap: past it every reply is sign-up only, no model runs, counted by conversation and IP', async () => {
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
