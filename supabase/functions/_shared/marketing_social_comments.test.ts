// deno test --allow-read supabase/functions/_shared/marketing_social_comments.test.ts
// The marketing seat answers public comments with no person approving a reply (instruction 866, 23 Sep 2026).
// Every platform is replayed with a mocked fetch and an in-memory store: nothing here can reach an account.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { call, classify, guard, hideRequest, LIMIT, processComment, readX, readYouTube, replyRequest, youtubeToken,
  type CommentEvent, type Decided, type Outcome, type Platform, type Store } from './marketing_social_comments.ts';

// The fixed replies are read from the SQL that ships them, so the test pins the rows production gets.
const SQL = ['every_social_message_is_answered.sql', 'the_marketing_seat_answers_comments_on_every_channel.sql']
  .map((f) => Deno.readTextFileSync(new URL('../../../scripts/sql/' + f, import.meta.url))).join('\n');
const LIB = new Map<string, { en: string; ar: string }>();
for (const m of SQL.matchAll(/^\('(\w+)', (?:\d+|null),\s*(?:array\[[\s\S]*?\]|'\{\}'),\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',/gm)) {
  LIB.set(m[1], { en: m[2].replace(/''/g, "'"), ar: m[3].replace(/''/g, "'") });
}

interface Mem { rows: Map<string, Outcome>; replies: { ev: CommentEvent; text: string }[]; hides: string[]; handoffs: string[]; threadCount: Map<string, number> }
function memStore(o: { send?: boolean; model?: boolean; draft?: string | null; det?: Decided } = {}): Store & { mem: Mem } {
  const mem: Mem = { rows: new Map(), replies: [], hides: [], handoffs: [], threadCount: new Map() };
  const seen = new Set<string>(); let id = 0; const byId = new Map<number, string>();
  return {
    mem,
    async insertInbound(ev) { const k = ev.platform + ':' + ev.commentId; if (seen.has(k)) return null; seen.add(k); byId.set(++id, k); return id; },
    async threadAllowed(ev) { const k = ev.platform + ':' + ev.threadId; const c = (mem.threadCount.get(k) || 0) + 1; mem.threadCount.set(k, c); return c <= 3; },
    async record(inId, row) { mem.rows.set(byId.get(inId)!, { ...row }); },
    async handoff(to, type) { mem.handoffs.push(to + ':' + type); return mem.handoffs.length; },
    async switchOn(key) { return key === 'social_send_enabled' ? o.send !== false : !!o.model; },
    async library(key, lang) { return (LIB.get(key) as any)?.[lang] ?? ''; },
    async deterministic() { return o.det ?? { kind: 'unknown', key: 'unknown', text: '' }; },
    async draft() { return o.draft ?? null; },
    async reply(ev, text) { mem.replies.push({ ev, text }); return { ok: true, id: 'r' + mem.replies.length }; },
    async hide(ev) { mem.hides.push(ev.commentId); return { ok: true }; },
  };
}
let n = 0;
const ev = (text: string, over: Partial<CommentEvent> = {}): CommentEvent =>
  ({ platform: 'instagram', accountId: 'OUR', commentId: 'c' + (++n), authorId: 'u' + n, handle: 'person' + n, text, at: new Date(), threadId: 't' + n, ...over });

// ── the adversarial fixtures: each ends in the right outcome with no human in the loop ──────────────────────
Deno.test('adversarial comments each end in the right outcome, with no approval step', async () => {
  const cases: [string, string, string, string[]][] = [
    // text, expected outcome, expected classification, expected handoffs
    ['Is it really 1% for customers? what is the fee', 'held_not_run', 'question', []],                 // no fixed answer, model held
    ['Who is the supplier that did the Al Barsha villa?', 'replied', 'sensitive_legal', ['customer_support:social.escalation']],
    ['you are all scammers and idiots', 'hidden', 'spam_abuse', []],
    ['I will take you to court, my lawyer is on it', 'replied', 'sensitive_legal', ['customer_support:social.escalation']],
    ['Get 10k followers now http://cheap-followers.biz', 'hidden', 'spam_abuse', []],
    ['I paid and nobody answered, I want a refund', 'replied', 'complaint', ['customer_support:social.escalation']],
    ['We are a fit-out contractor, how do we register our company?', 'replied', 'supplier_enquiry', ['sales_engineer:social.lead']],
    ['I need a quote for painting my apartment', 'replied', 'sales_lead', ['sales_engineer:social.lead']],
    ['ممتاز ما شاء الله', 'replied', 'praise', []],
    ['نصابين', 'hidden', 'spam_abuse', []],
    ['مين المورد اللي نفذ المشروع؟', 'replied', 'sensitive_legal', ['customer_support:social.escalation']],
    ['🙂', 'ignored_off_topic', 'off_topic', []],
  ];
  for (const [text, outcome, cls, handoffs] of cases) {
    const s = memStore();
    const e = ev(text);
    assertEquals(await processComment(s, e), outcome, text);
    const row = s.mem.rows.get('instagram:' + e.commentId)!;
    assertEquals(row.classification, cls, text);
    assertEquals(s.mem.handoffs, handoffs, text);
    if (outcome === 'replied') {
      assertEquals(guard(row.reply!, e), [], 'a fixed reply must pass its own guards: ' + text);
      if (/[؀-ۿ]/.test(text)) assert(/[؀-ۿ]/.test(row.reply!), 'Arabic comment, Arabic reply: ' + text);
    }
  }
});

Deno.test('a model draft is sent only when it passes every guard; a failing draft is escalated, never queued for approval', async () => {
  const good = memStore({ model: true, draft: 'Posting a request on QuotesDone is free; a 3% reveal fee applies only if you reveal a supplier.' });
  assertEquals(await processComment(good, ev('what happens after I post?')), 'replied');
  assertEquals(good.mem.replies.length, 1);
  for (const bad of [
    'Customers pay 5% on every job.',                               // wrong fee
    'Suppliers pay AED 500 a year.',                                // wrong amount
    'We are licensed under E-Trader licence 1633275.',              // never "E-Trader"
    'Our licence is 1234567.',                                      // wrong licence
    'The job was done by Al Noor Contracting LLC, call 0501234567.',// identity + phone
    'We guarantee the cheapest price.',                             // promise
    'See https://cheap-quotes.example for more.',                   // foreign link
    'You are legally entitled to sue them in court.',               // legal
  ]) {
    const s = memStore({ model: true, draft: bad });
    const e = ev('what happens after I post?');
    assertEquals(await processComment(s, e), 'replied', bad);
    const row = s.mem.rows.get('instagram:' + e.commentId)!;
    assertEquals(row.decided_by, 'guard_fallback', bad);
    assert(row.guard_failures.length > 0, bad);
    assertEquals(s.mem.handoffs, ['customer_support:social.escalation'], bad);
    assert(!s.mem.replies[0].text.includes(bad), 'the failed draft itself never goes out: ' + bad);
  }
  // Arabic comment answered in English by the model: wrong language, not sent.
  assert(guard('Posting is free.', { platform: 'x', text: 'هل النشر مجاني؟', handle: null }).includes('wrong_language'));
});

Deno.test('the fixed facts pass the guards in both languages and fit every platform', () => {
  for (const key of ['comment_praise', 'comment_escalated_ack', 'comment_lead', 'comment_supplier']) {
    const r = LIB.get(key)!;
    assert(r, key + ' is seeded');
    for (const p of ['x', 'instagram', 'facebook', 'youtube'] as Platform[]) {
      assertEquals(guard(r.en, { platform: p, text: 'hello there', handle: null }), [], key + ' en ' + p);
      assertEquals(guard(r.ar, { platform: p, text: 'مرحبا بكم', handle: null }), [], key + ' ar ' + p);
    }
  }
  assert(LIB.get('comment_supplier')!.en.includes('first 1,000 suppliers') && LIB.get('comment_supplier')!.en.includes('AED 1,000 a year'));
});

Deno.test('idempotent: the same comment delivered twice is answered once', async () => {
  const s = memStore();
  const e = ev('amazing platform');
  assertEquals(await processComment(s, e), 'replied');
  assertEquals(await processComment(s, { ...e }), 'duplicate');
  assertEquals(s.mem.replies.length, 1);
});

Deno.test('no loop: our own comment is never answered, and a thread takes at most 3 replies', async () => {
  const s = memStore();
  assertEquals(await processComment(s, ev('thanks for the support!', { authorId: 'OUR' })), 'own_or_empty');
  const outs = [];
  for (let i = 0; i < 5; i++) outs.push(await processComment(s, ev('great work', { threadId: 'same' })));
  assertEquals(outs, ['replied', 'replied', 'replied', 'rate_limited', 'rate_limited']);
});

Deno.test('the kill switch holds: nothing is sent or hidden while social_send_enabled is off, and fixtures never reach anyone', async () => {
  const s = memStore({ send: false });
  assertEquals(await processComment(s, ev('great work')), 'reply_held');
  assertEquals(await processComment(s, ev('idiot')), 'hide_held');
  assertEquals(s.mem.replies.length + s.mem.hides.length, 0);
  const f = memStore();
  assertEquals(await processComment(f, ev('great work', { authorId: 'ZZDEMO1' })), 'reply_held');
  assertEquals(f.mem.replies.length, 0);
});

Deno.test('the model held: a judgement question is recorded "held, not run" and nothing is said', async () => {
  const s = memStore({ model: false, draft: 'should never be asked for' });
  const e = ev('what makes you different from other platforms?');
  assertEquals(await processComment(s, e), 'held_not_run');
  assertEquals(s.mem.rows.get('instagram:' + e.commentId)!.send_status, 'held_model');
  assertEquals(s.mem.replies.length, 0);
  // and a fixed answer still goes: determinism does not wait for the model
  const d = memStore({ model: false, det: { kind: 'standard', key: 'pricing', text: LIB.get('pricing')!.en } });
  assertEquals(await processComment(d, ev('is it free?', { platform: 'youtube' })), 'replied');
  assert(d.mem.replies[0].text.length <= LIMIT.youtube);
});

// ── read + reply per platform, against a mocked API ──────────────────────────────────────────────────────
type Seen = { url: string; init?: RequestInit };
const mock = (answer: (u: string) => unknown, seen: Seen[] = []) => (async (url: string, init?: RequestInit) => {
  seen.push({ url, init }); return new Response(JSON.stringify(answer(url)), { status: 200 });
}) as unknown as typeof fetch;

Deno.test('X: mentions are read and a reply is posted to the mention', async () => {
  const seen: Seen[] = [];
  const f = mock(() => ({ data: [{ id: '19', text: '@quotesdone how does it work?', author_id: '7', created_at: '2026-09-23T08:00:00Z', conversation_id: '11' }],
    includes: { users: [{ id: '7', username: 'buyer_ae' }] } }), seen);
  const [m] = await readX(f, 'TOK', '555', '18');
  assertEquals([m.platform, m.commentId, m.handle, m.text, m.threadId, m.accountId], ['x', '19', 'buyer_ae', 'how does it work?', '11', '555']);
  assert(seen[0].url.includes('/2/users/555/mentions') && seen[0].url.includes('since_id=18'));
  const r = replyRequest(m, 'hello', 'TOK');
  assertEquals([r.url, r.method, JSON.parse(r.body!).reply.in_reply_to_tweet_id], ['https://api.x.com/2/tweets', 'POST', '19']);
  assertEquals(hideRequest(m, 'TOK').url, 'https://api.x.com/2/tweets/19/hidden');
  assertEquals(await call(mock(() => ({ data: { id: '20' } })), r), { ok: true, id: '20' });
});

Deno.test('YouTube: a token is refreshed, comments are read, a reply is inserted and abuse is held for review', async () => {
  const seen: Seen[] = [];
  const f = mock((u) => u.includes('oauth2') ? { access_token: 'AT' } : { items: [{ id: 'th1', snippet: { videoId: 'v1', topLevelComment: { id: 'cm1',
    snippet: { authorChannelId: { value: 'UCx' }, authorDisplayName: 'Viewer', textOriginal: 'Is it free?', publishedAt: '2026-09-23T08:00:00Z' } } } }] }, seen);
  assertEquals(await youtubeToken(f, 'id', 'sec', 'rt'), 'AT');
  const [c] = await readYouTube(f, 'AT', 'UCours');
  assertEquals([c.platform, c.commentId, c.authorId, c.threadId, c.text], ['youtube', 'cm1', 'UCx', 'v1', 'Is it free?']);
  const r = replyRequest(c, 'hi', 'AT');
  assertEquals(JSON.parse(r.body!).snippet.parentId, 'cm1');
  assert(hideRequest(c, 'AT').url.includes('setModerationStatus?id=cm1&moderationStatus=heldForReview'));
});

Deno.test('Instagram and Facebook: replies and hides go to the comment through Graph', () => {
  const ig = ev('x'); const fb = ev('x', { platform: 'facebook' });
  assert(replyRequest(ig, 'a', 'T').url.endsWith('/' + ig.commentId + '/replies'));
  assert(replyRequest(fb, 'a', 'T').url.endsWith('/' + fb.commentId + '/comments'));
  assertEquals(JSON.parse(hideRequest(ig, 'T').body!), { hide: true });
  assertEquals(JSON.parse(hideRequest(fb, 'T').body!), { is_hidden: true });
});

Deno.test('classification spot checks', () => {
  assertEquals(classify('great, how do I register?'), 'question');
  assertEquals(classify('hello', true), 'complaint');   // a person asked for: handed to customer_support
  assert(classify('love https://quotesdone.com') !== 'spam_abuse');   // our own link is not spam
});
