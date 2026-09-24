// deno test --allow-read supabase/functions/_shared/marketing_social_comments.test.ts
// The marketing seat answers public comments with no person approving a reply (instruction 866, 23 Sep 2026).
// Every platform is replayed with a mocked fetch and an in-memory store: nothing here can reach an account.
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { call, guard, hideRequest, LIMIT, normalise, processComment, replyRequest, tiktokComments, unhideRequest,
  type Class, type CommentEvent, type Decided, type Outcome, type Platform, type Store } from './marketing_social_comments.ts';

// The fixed replies are read from the SQL that ships them, so the test pins the rows production gets.
const SQL = ['every_social_message_is_answered.sql', 'the_marketing_seat_answers_comments_on_every_channel.sql']
  .map((f) => Deno.readTextFileSync(new URL('../../../scripts/sql/' + f, import.meta.url))).join('\n');
const LIB = new Map<string, { en: string; ar: string }>();
for (const m of SQL.matchAll(/^\('(\w+)', (?:\d+|null),\s*(?:array\[[\s\S]*?\]|'\{\}'),\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',/gm)) {
  LIB.set(m[1], { en: m[2].replace(/''/g, "'"), ar: m[3].replace(/''/g, "'") });
}

interface Mem { rows: Map<string, Outcome>; replies: { ev: CommentEvent; text: string }[]; hides: string[]; handoffs: string[]; released: number[]; threadCount: Map<string, number> }
function memStore(o: { send?: boolean; model?: boolean; draft?: string | null; det?: Decided; handoffThrows?: boolean } = {}): Store & { mem: Mem } {
  const mem: Mem = { rows: new Map(), replies: [], hides: [], handoffs: [], released: [], threadCount: new Map() };
  const seen = new Set<string>(); let id = 0; const byId = new Map<number, string>();
  return {
    mem,
    async insertInbound(ev) { const k = ev.platform + ':' + ev.commentId; if (seen.has(k)) return null; seen.add(k); byId.set(++id, k); return id; },
    async release(inId) { mem.released.push(inId); seen.delete(byId.get(inId)!); },
    async threadAllowed(ev) { const k = ev.platform + ':' + ev.threadId; const c = (mem.threadCount.get(k) || 0) + 1; mem.threadCount.set(k, c); return c <= 3; },
    async record(inId, row) { mem.rows.set(byId.get(inId)!, { ...row }); },
    async handoff(type, _ev, _cls, extra) {
      if (o.handoffThrows) throw new Error('fn_seat_handoff: down');
      mem.handoffs.push(({ 'social.escalation': 'customer_support', 'social.lead': 'sales_engineer' } as const)[type] + ':' + type + (extra?.hidden ? ':hidden' : ''));
      return mem.handoffs.length;
    },
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
const EN = { platform: 'instagram' as Platform, text: 'what is the fee?', handle: null };
const ARQ = { platform: 'instagram' as Platform, text: 'كم الرسوم؟', handle: null };

// ── THE REVIEWER'S 14 BYPASS DRAFTS: every one must fail the guard ─────────────────────────────────────
Deno.test('the 14 bypass drafts each fail the guard', () => {
  const drafts: [string, typeof EN][] = [
    ['Customers pay five percent on every job.', EN],
    ['Customers pay 5 per cent on every job.', EN],
    ['يدفع العميل ٥٪ على كل عمل.', ARQ],
    ['يدفع العميل 5 بالمئة على كل عمل.', ARQ],
    ['Suppliers pay 500 dirhams a year.', EN],
    ['يدفع المورد ٥٠٠ درهم سنويًا.', ARQ],
    ['Free forever for everyone, no fees at all.', EN],
    ['We are licensed as an E‑Trader.', EN],
    ['We are licensed as an Е-Trader.', EN],
    ['Details at bit.ly/qd1 or goo.gl/x or wa.me/971500000000', EN],
    ['اتصلوا بنا على ٠٥٠١٢٣٤٥٦٧', ARQ],
    ["We'll refund you in full.", EN],
    ['Under UAE law you are entitled to a refund.', EN],
    ['The job was done by Al Futtaim.', EN],
    // second review: the hamza fold
    ['يدفع العميل ٥ في المئة على كل عمل.', ARQ],
    ['يدفع العميل 5 في المائة على كل عمل.', ARQ],
    ['يدفع العميل خمسة بالمئة على كل عمل.', ARQ],
    ['Customers pay 5 pc on every job.', EN],
    // the Arabic sweep: fees, amounts, refunds, legal, free-for-all — written normally, with hamza, tanween, tatweel
    ['الرسوم ١٠٪ فقط.', ARQ],
    ['الرسوم عشرة بالمئة فقط.', ARQ],
    ['الرسومُ خمسةٌ في المئةِ فقط.', ARQ],
    ['الرسـوم ٥ بالمـئة.', ARQ],
    ['الاشتراك ٥٠٠ دراهم سنويًا.', ARQ],
    ['الاشتراك خمسمائة درهم.', ARQ],
    ['الاشتراك ألف درهم للجميع.', ARQ],
    ['سنعيد لكم المبلغ كاملًا.', ARQ],
    ['نُرجع لكم فلوسكم كاملة.', ARQ],
    ['استرداد كامل مضمون.', ARQ],
    ['يحق لكم استرداد المبلغ بموجب القانون.', ARQ],
    ['من حقكم قانونيًا المطالبة.', ARQ],
    ['المنصة مجانية للجميع ولا توجد أي رسوم.', ARQ],
    ['التسجيل بدون أي رسوم.', ARQ],
  ];
  for (const [d, e] of drafts) assert(guard(d, e).length > 0, 'passed the guard: ' + d + ' -> ' + JSON.stringify(guard(d, e)));
  // and the real facts still pass
  assertEquals(guard('Posting is free; a 3% reveal fee applies only if you reveal a supplier.', EN), []);
  assertEquals(guard('يدفع العميل رسوم كشف بنسبة ٣٪ فقط عند كشف المورد.', ARQ), []);
});

Deno.test('normalise folds digits, dashes, look-alikes and diacritics', () => {
  assertEquals(normalise('٥٠٠ ۱۲'), '500 12');
  assertEquals(normalise('Е‑Trader'), 'E-Trader');
  assertEquals(normalise('شُكْرًا'), 'شكرا');
  assertEquals(normalise('مـــرحبا'), 'مرحبا');
});

// ── the adversarial fixtures: each ends in the right outcome with no human in the loop ──────────────────────
Deno.test('adversarial comments each end in the right outcome, with no approval step', async () => {
  const cases: [string, string, string, string[]][] = [
    ['Is it really 1% for customers? what is the fee', 'held_not_run', 'question', []],
    ['Who is the supplier that did the Al Barsha villa?', 'replied', 'sensitive_legal', ['customer_support:social.escalation']],
    ['you are all scammers and idiots', 'hidden', 'spam_abuse', ['customer_support:social.escalation:hidden']],
    ['I will take you to court, my lawyer is on it', 'replied', 'sensitive_legal', ['customer_support:social.escalation']],
    ['Get 10k followers now http://cheap-followers.biz', 'hidden', 'spam_abuse', ['customer_support:social.escalation:hidden']],
    ['I paid and nobody answered, I want a refund', 'replied', 'complaint', ['customer_support:social.escalation']],
    ['We are a fit-out contractor, how do we register our company?', 'replied', 'supplier_enquiry', ['sales_engineer:social.lead']],
    ['I need a quote for painting my apartment', 'replied', 'sales_lead', ['sales_engineer:social.lead']],
    ['ممتاز ما شاء الله', 'replied', 'praise', []],
    ['نصابين', 'hidden', 'spam_abuse', ['customer_support:social.escalation:hidden']],
    ['مين المورد اللي نفذ المشروع؟', 'replied', 'sensitive_legal', ['customer_support:social.escalation']],
    ['🙂', 'ignored_off_topic', 'off_topic', []],
  ];
  for (const [text, outcome, cls, handoffs] of cases) {
    const s = memStore();
    const e = ev(text);
    assertEquals(await processComment(s, e, cls as Class), outcome, text);
    const row = s.mem.rows.get('instagram:' + e.commentId)!;
    assertEquals(row.classification, cls, text);
    assertEquals(s.mem.handoffs, handoffs, text);
    if (outcome === 'replied') {
      assertEquals(guard(row.reply!, e), [], 'a fixed reply must pass its own guards: ' + text);
      if (/[؀-ۿ]/.test(text)) assert(/[؀-ۿ]/.test(row.reply!), 'Arabic comment, Arabic reply: ' + text);
    }
  }
});

Deno.test('the class is REASONED; held, nothing is hidden, said or handed off — the comment waits for the replay', async () => {
  for (const text of ['you are all scammers and idiots', 'I will take you to court', 'I need a quote for painting']) {
    const s = memStore();
    const e = ev(text);
    assertEquals(await processComment(s, e, null), 'held_classify', text);
    const row = s.mem.rows.get('instagram:' + e.commentId)!;
    assertEquals(row.classification, null);
    assertEquals(row.send_status, 'held_model');
    assertEquals(s.mem.hides.length + s.mem.replies.length + s.mem.handoffs.length, 0, text);
  }
  // a reasoned request for a person is the complaint policy (also while the class itself is held); abuse is still hidden
  const p = memStore();
  assertEquals(await processComment(p, ev('hello'), null, true), 'replied');
  assertEquals(p.mem.handoffs, ['customer_support:social.escalation']);
  const a = memStore();
  assertEquals(await processComment(a, ev('idiots'), 'spam_abuse', true), 'hidden');
});

Deno.test('every text that would be sent passes the guard and fits — library, FAQ and knowledge included; a fact is never truncated', async () => {
  // a FAQ/knowledge answer carrying a DM instruction and a phone number: not posted, escalated instead
  const bad = memStore({ det: { kind: 'faq', key: 'x', text: "Reply 'agent' or call +971 50 931 9355 to reach us." } });
  const e1 = ev('how do I reach you?');
  assertEquals(await processComment(bad, e1, 'question'), 'replied');
  const r1 = bad.mem.rows.get('instagram:' + e1.commentId)!;
  assertEquals(r1.decided_by, 'guard_fallback');
  assert(r1.guard_failures.includes('dm_instruction') && r1.guard_failures.includes('phone'), JSON.stringify(r1.guard_failures));
  assertEquals(bad.mem.replies[0].text, LIB.get('comment_escalated_ack')!.en);
  // a knowledge answer too long for the platform: escalated, never cut
  const long = 'Posting is free. '.repeat(40);
  const lg = memStore({ det: { kind: 'knowledge', key: 'k', text: long } });
  const e2 = ev('what is posting like?');
  await processComment(lg, e2, 'question');
  assert(lg.mem.rows.get('instagram:' + e2.commentId)!.guard_failures.includes('too_long'));
  assert(!lg.mem.replies[0].text.includes('…') && lg.mem.replies[0].text === LIB.get('comment_escalated_ack')!.en);
  // a clean FAQ answer goes as it is
  const ok = memStore({ det: { kind: 'faq', key: 'pricing', text: 'Posting a request is free; a 3% reveal fee applies only if you reveal a supplier.' } });
  assertEquals(await processComment(ok, ev('is it free?', { platform: 'youtube' }), 'question'), 'replied');
  assert(ok.mem.replies[0].text.startsWith('Posting a request is free'));
});

Deno.test('a model draft is sent only when it passes every guard; a failing draft is escalated, never queued for approval', async () => {
  const good = memStore({ model: true, draft: 'Posting a request on QuotesDone is free; a 3% reveal fee applies only if you reveal a supplier.' });
  assertEquals(await processComment(good, ev('what happens after I post?'), 'question'), 'replied');
  assertEquals(good.mem.replies.length, 1);
  for (const bad of [
    'Customers pay 5% on every job.', 'Suppliers pay AED 500 a year.', 'We are licensed under E-Trader licence 1633275.',
    'Our licence is 1234567.', 'The job was done by Al Noor Contracting LLC, call 0501234567.', 'We guarantee the cheapest price.',
    'See https://cheap-quotes.example for more.', 'You are legally entitled to sue them in court.',
  ]) {
    const s = memStore({ model: true, draft: bad });
    const e = ev('what happens after I post?');
    assertEquals(await processComment(s, e, 'question'), 'replied', bad);
    const row = s.mem.rows.get('instagram:' + e.commentId)!;
    assertEquals(row.decided_by, 'guard_fallback', bad);
    assert(row.guard_failures.length > 0, bad);
    assertEquals(s.mem.handoffs, ['customer_support:social.escalation'], bad);
    assert(!s.mem.replies[0].text.includes(bad), 'the failed draft itself never goes out: ' + bad);
  }
  assert(guard('Posting is free.', { platform: 'youtube', text: 'هل النشر مجاني؟', handle: null }).includes('wrong_language'));
});

Deno.test('the fixed facts pass the guards in both languages and fit every platform', () => {
  for (const key of ['comment_praise', 'comment_escalated_ack', 'comment_lead', 'comment_supplier']) {
    const r = LIB.get(key)!;
    assert(r, key + ' is seeded');
    for (const p of ['instagram', 'facebook', 'youtube'] as Platform[]) {
      assertEquals(guard(r.en, { platform: p, text: 'hello there', handle: null }), [], key + ' en ' + p);
      assertEquals(guard(r.ar, { platform: p, text: 'مرحبا بكم', handle: null }), [], key + ' ar ' + p);
    }
  }
  assert(LIB.get('comment_supplier')!.en.includes('first 1,000 suppliers') && LIB.get('comment_supplier')!.en.includes('AED 1,000 a year'));
});

Deno.test('a handoff that throws gives the comment back: it is retried, not left without an outcome', async () => {
  const s = memStore({ handoffThrows: true });
  const e = ev('I paid and nobody answered, I want a refund');
  await assertRejects(() => processComment(s, e, 'complaint'));
  assertEquals(s.mem.released.length, 1);
  assertEquals(s.mem.replies.length, 0);
  // the same comment delivered again is processed, not dropped as a duplicate
  const again = { ...s, async handoff() { return 7; } } as Store;
  assertEquals(await processComment(again, { ...e }, 'complaint'), 'replied');
});

Deno.test('idempotent: the same comment delivered twice is answered once', async () => {
  const s = memStore();
  const e = ev('amazing platform');
  assertEquals(await processComment(s, e, 'praise'), 'replied');
  assertEquals(await processComment(s, { ...e }, 'praise'), 'duplicate');
  assertEquals(s.mem.replies.length, 1);
});

Deno.test('no loop: our own comment is never answered, and a thread takes at most 3 replies', async () => {
  const s = memStore();
  assertEquals(await processComment(s, ev('thanks for the support!', { authorId: 'OUR' }), 'praise'), 'own_or_empty');
  const outs = [];
  for (let i = 0; i < 5; i++) outs.push(await processComment(s, ev('great work', { threadId: 'same' }), 'praise'));
  assertEquals(outs, ['replied', 'replied', 'replied', 'rate_limited', 'rate_limited']);
});

Deno.test('the kill switch holds: nothing is sent or hidden while social_send_enabled is off, and fixtures never reach anyone', async () => {
  const s = memStore({ send: false });
  assertEquals(await processComment(s, ev('great work'), 'praise'), 'reply_held');
  assertEquals(await processComment(s, ev('idiot'), 'spam_abuse'), 'hide_held');
  assertEquals(s.mem.replies.length + s.mem.hides.length, 0);
  const f = memStore();
  assertEquals(await processComment(f, ev('great work', { authorId: 'ZZDEMO1' }), 'praise'), 'reply_held');
  assertEquals(f.mem.replies.length, 0);
});

Deno.test('the model held: a judgement question is recorded "held, not run" and nothing is said', async () => {
  const s = memStore({ model: false, draft: 'should never be asked for' });
  const e = ev('what makes you different from other platforms?');
  assertEquals(await processComment(s, e, 'question'), 'held_not_run');
  assertEquals(s.mem.rows.get('instagram:' + e.commentId)!.send_status, 'held_model');
  assertEquals(s.mem.replies.length, 0);
});

// ── platform calls, against a mocked API ────────────────────────────────────────────────────────────────
const mock = (answer: unknown) => (async () => new Response(JSON.stringify(answer), { status: 200 })) as unknown as typeof fetch;

Deno.test('Instagram, Facebook and YouTube: replies, hides and un-hides go to the comment', async () => {
  const ig = ev('x'); const fb = ev('x', { platform: 'facebook' }); const yt = ev('x', { platform: 'youtube' });
  assert(replyRequest(ig, 'a', 'T').url.endsWith('/' + ig.commentId + '/replies'));
  assert(replyRequest(fb, 'a', 'T').url.endsWith('/' + fb.commentId + '/comments'));
  assertEquals(JSON.parse(replyRequest(yt, 'a', 'T').body!).snippet.parentId, yt.commentId);
  assertEquals(JSON.parse(hideRequest(ig, 'T')!.body!), { hide: true });
  assertEquals(JSON.parse(unhideRequest(ig, 'T')!.body!), { hide: false });
  assertEquals(JSON.parse(hideRequest(fb, 'T')!.body!), { is_hidden: true });
  assertEquals(JSON.parse(unhideRequest(fb, 'T')!.body!), { is_hidden: false });
  assert(hideRequest(yt, 'T')!.url.endsWith('moderationStatus=heldForReview') && unhideRequest(yt, 'T')!.url.endsWith('moderationStatus=published'));
  assertEquals(await call(mock({ id: '20' }), replyRequest(ig, 'a', 'T')), { ok: true, id: '20' });
  const li = ev('x', { platform: 'linkedin', accountId: 'urn:li:organization:9', commentId: 'urn:li:comment:(urn:li:activity:1,2)', threadId: 'urn:li:share:1' });
  const lr = replyRequest(li, 'a', 'T');
  assertEquals(JSON.parse(lr.body!).actor, 'urn:li:organization:9', 'the page answers, never a member');
  assertEquals(JSON.parse(lr.body!).parentComment, li.commentId);
  assertEquals(hideRequest(li, 'T'), null, 'LinkedIn has no reversible hide');
  assertEquals((await call(mock({}), hideRequest(li, 'T'))).ok, false);
  assert(!LIMIT['x' as Platform], 'X is removed (founder, 23 Sep 2026)');
  const tt = ev('x', { platform: 'tiktok', accountId: 'BIZ', threadId: 'V1' });
  const tr = replyRequest(tt, 'a', 'T');
  assertEquals(tr.headers['Access-Token'], 'T', 'the business account itself answers');
  assertEquals(JSON.parse(tr.body!), { business_id: 'BIZ', video_id: 'V1', comment_id: tt.commentId, text: 'a' });
  assertEquals(JSON.parse(hideRequest(tt, 'T')!.body!).action, 'HIDE');
  assertEquals(JSON.parse(unhideRequest(tt, 'T')!.body!).action, 'UNHIDE');
  assertEquals((await call(mock({ code: 40001, message: 'no permission' }), tr)).ok, false, 'a TikTok non-zero code is a failure');
});

Deno.test('TikTok comments: only newer than since, never our own', async () => {
  const f = (async (u: string) => new Response(JSON.stringify(u.includes('video/list') ? { code: 0, data: { videos: [{ item_id: 'V1' }] } }
    : { code: 0, data: { comments: [
      { comment_id: 'c1', user_id: 'u1', username: 'a', text: 'hi', create_time: Math.floor(Date.now() / 1000) },
      { comment_id: 'c2', user_id: 'u2', text: 'old', create_time: 1 },
      { comment_id: 'c3', user_id: 'BIZ', text: 'ours', create_time: Math.floor(Date.now() / 1000), owner: true } ] } }), { status: 200 })) as unknown as typeof fetch;
  const out = await tiktokComments(f, 'T', 'BIZ', new Date(Date.now() - 3600_000));
  assertEquals(out.map((c) => c.commentId), ['c1']);
  assertEquals(out[0].threadId, 'V1');
});


Deno.test('the duty: one platform failing never stops the others, and a credential failure is a skip, not a failure', async () => {
  const { isolated, Skip } = await import('../marketing/duties.ts');
  const r = await isolated({
    youtube: async () => { throw new Error('youtube commentThreads HTTP 401'); },
    broken: async () => { throw new Error('boom'); },
    runs: async () => 'ran',
    linkedin: async () => { throw new Skip('company page not connected'); },
  });
  assertEquals(r.out, { runs: 'ran' });
  assertEquals(r.skipped.length, 2);
  assertEquals(r.errors, ['broken: boom']);
});

Deno.test('the reasoned class and person check are lazy: never asked for our own comment or one already handled; asked once otherwise', async () => {
  let asked = 0; let classed = 0;
  const person = () => { asked++; return Promise.resolve(true); };
  const cls = () => { classed++; return Promise.resolve('question' as Class); };
  const own = memStore();
  const mine = ev('what are your fees?');
  assertEquals(await processComment(own, { ...mine, authorId: mine.accountId }, cls, person), 'own_or_empty');
  const seen = Object.assign(memStore(), { seen: () => Promise.resolve(true) });
  assertEquals(await processComment(seen, ev('still waiting'), cls, person), 'duplicate');
  assertEquals([asked, classed], [0, 0]);
  const s = Object.assign(memStore(), { seen: () => Promise.resolve(false) });
  const e = ev('is anyone there, I paid last week');
  await processComment(s, e, cls, person);
  assertEquals([asked, classed], [1, 1]);
  assertEquals(s.mem.rows.get('instagram:' + e.commentId)!.classification, 'complaint');
});
