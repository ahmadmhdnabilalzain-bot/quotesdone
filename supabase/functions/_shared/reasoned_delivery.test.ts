// A held question, reasoned after the hold lifts, is delivered on its own channel under the channel's rules.
import { assertEquals, assertMatch } from 'jsr:@std/assert';
import { casSecrets, deliverReasoned, holdingNotice, liveDeliveryIO, replayHeldComment, sendHeldNotices, type CommentReplayIO, type DeliveryIO } from './reasoned_delivery.ts';
import { call, processComment, replyRequest, type CommentEvent, type Store } from './marketing_social_comments.ts';
import { accessToken, open, seal, type SocialPlatform } from './marketing_social_oauth.ts';
import type { HeldRow, ThinkResult } from './think.ts';

function io(windowOpen: boolean) {
  const log: string[] = [];
  const x: DeliveryIO = {
    waWindowOpen: () => Promise.resolve(windowOpen),
    sendWaText: (p, b) => { log.push('text ' + p + ' ' + b); return Promise.resolve({ ok: true }); },
    queueWaTemplate: (p, q, a, l) => { log.push(`template ${p} ${l} [${q}] ${a}`); return Promise.resolve({ ok: true }); },
    founderContact: () => Promise.resolve('+971 50 000 0000'),
    reportToCeo: (k) => { log.push('ceo ' + k); return Promise.resolve(); },
    socialHandoff: (s) => { log.push('social ' + s.platform + ' ' + s.message_id); return Promise.resolve({ ok: true }); },
    socialCommentHandoff: (s) => { log.push('comment ' + s.platform + ' ' + s.message_id); return Promise.resolve({ ok: true }); },
    writeReply: (q, lang, o) => { log.push('write ' + lang + ' ' + (o?.channel ?? '') + ' ' + q); return Promise.resolve('MODEL: ' + q); },
    socialReply: (s, meaning) => { log.push('reply ' + s.platform + ' ' + s.message_id + ' ' + meaning); return Promise.resolve({ ok: true }); },
    accountantSweep: (id) => { log.push('sweep ' + id); return Promise.resolve({ ok: true, found: true, verdict: 'booked' }); },
    receiptToBookkeeper: (id) => { log.push('bookkeeper ' + id); return Promise.resolve({ ok: true }); },
    outreachPage: () => Promise.resolve({ full_name: 'ZZ DEMO Sara', language: 'en' as const }),
    outreachReasoned: (t, c, f) => { log.push(`outreach ${t} ${c} ${f ? 'draft' : 'none'}`); return Promise.resolve({ ok: true }); },
    arabicFinishReady: () => { log.push('arabic ready'); return Promise.resolve({ ok: true }); },
    socialCommentClassified: (s, c) => { log.push('classified ' + s.platform + ' ' + s.message_id + ' ' + c); return Promise.resolve({ ok: true }); },
  };
  return { x, log };
}
const row = (surface: string, question: string, subject: Record<string, unknown>, decision = true): HeldRow => ({
  id: 7, seat: 'customer_support', surface, subject,
  request: { seat: 'customer_support', surface, question, ...(decision ? { decision: { name: 'needs_a_person', options: [{ id: 'needs_a_person', meaning: '' }, { id: 'no_person', meaning: '' }] } } : {}) },
});
const answered = (choice: string | null, answer = 'They accuse us of taking money: a person is needed.'): ThinkResult =>
  ({ status: 'answered', answer, decision: { choice, fields: {} }, steps: [], context_used: {}, missing_context: [], sources: [], confidence: 0.8 });

Deno.test('WhatsApp, inside the 24-hour window: the contact goes as free text, and the CEO sees it', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('wa_inbound.needs_a_person', 'you took my money and vanished', { phone: 'whatsapp:+971500000001' }), answered('needs_a_person'), x);
  assertEquals([d.delivered, d.via], [true, 'whatsapp_text']);
  assertEquals(log[0], 'ceo reasoned:person:7');
  assertMatch(log[1], /^text whatsapp:\+971500000001 Thank you for your patience.*\+971 50 000 0000/);
});

Deno.test('WhatsApp, outside the window: only an approved template is allowed, so a support_reply row is queued', async () => {
  const { x, log } = io(false);
  const d = await deliverReasoned(row('wa_inbound.needs_a_person', 'نصبتوا علي', { phone: '+971500000001' }), answered('needs_a_person'), x);
  assertEquals([d.delivered, d.via], [true, 'whatsapp_template']);
  assertMatch(log[1], /^template \+971500000001 ar \[نصبتوا علي\] شكرًا لصبركم/);
  assertEquals(log.some((l) => l.startsWith('text')), false, 'no free text outside the window');
});

Deno.test('reasoned to need no person: nothing is sent again', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('wa_inbound.needs_a_person', 'is it legal to build a pool?', { phone: '+971500000001' }), answered('no_person'), x);
  assertEquals([d.delivered, d.via], [false, 'none']);
  assertEquals(log, []);
});

Deno.test('social: the handoff goes through the platform reply path', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('marketing_social.needs_a_person', 'is anyone actually there?', { platform: 'instagram', message_id: 'm1' }), answered('needs_a_person'), x);
  assertEquals([d.delivered, d.via], [true, 'social']);
  assertEquals(log, ['social instagram m1']);
});

Deno.test('a public comment reasoned to need a person gets the private handoff; one that does not gets nothing more', async () => {
  const { x, log } = io(true);
  const yes = await deliverReasoned(row('marketing_social.comment_needs_a_person', 'still waiting for my refund', { platform: 'youtube', message_id: 'c1' }), answered('needs_a_person'), x);
  assertEquals([yes.delivered, yes.via], [true, 'social']);
  const no = await deliverReasoned(row('marketing_social.comment_needs_a_person', 'is it legal to paint a villa blue?', { platform: 'youtube', message_id: 'c2' }), answered('no_person'), x);
  assertEquals([no.delivered, no.via], [false, 'none']);
  assertEquals(log, ['comment youtube c1']);
});

Deno.test('escalated at 48 hours: a WhatsApp customer is told a person is handling it; a row with no customer channel sends nothing', async () => {
  const { x, log } = io(true);
  const d = await holdingNotice({ id: 9, surface: 'wa_inbound.needs_a_person', question: 'where is my quote?', subject: { phone: '+971500000001' } }, x);
  assertEquals([d.delivered, d.via], [true, 'whatsapp_text']);
  assertMatch(log[0], /^text \+971500000001 Thank you for your patience\. Your question is now with our team/);
  const none = await holdingNotice({ id: 10, surface: 'ceo.command_intent', question: 'stop the campaign', subject: { command_id: 1 } }, x);
  assertEquals([none.delivered, none.via], [false, 'none']);
  assertEquals(log.length, 1);
});

Deno.test('a held ANSWER on WhatsApp goes back as the answer, under the same window rule', async () => {
  const { x, log } = io(false);
  const d = await deliverReasoned(row('think.answer', 'what depth can my pool be?', { channel: 'whatsapp', phone: '+971500000001' }, false),
    answered(null, 'In Dubai private pools need a DM permit; which emirate is the villa in?'), x);
  assertEquals(d.via, 'whatsapp_template');
  assertMatch(log[0], /\[what depth can my pool be\?\] In Dubai/);
});

// ── a held MEANING (reasoned_channels.ts): the answer the reasoned meaning selects, once ────────────
const meaningRow = (surface: string, question: string, subject: Record<string, unknown>): HeldRow => ({
  id: 9, seat: surface.startsWith('wa_') ? 'customer_support' : 'marketing', surface, subject,
  request: { seat: 'customer_support', surface, question, decision: { name: 'q', options: [{ id: 'none', meaning: '' }] } },
});

// Rulings 1195/1196 (12 Oct 2026): whatever the held meaning, the reply is written by a model now (io.writeReply); the
// database intent answer, the trade-list sentence and the capability statement are gone. Outside the window: the template.
Deno.test('WhatsApp meaning: an intent, a trade or size is answered by a model, on the channel rule', async () => {
  const wa = { channel: 'whatsapp', phone: '+971500000021' };
  const a = io(true);
  const i = await deliverReasoned(meaningRow('wa_inbound.intent_table', 'is it free?', wa), answered('intent:pricing'), a.x);
  assertEquals([i.delivered, i.via], [true, 'whatsapp_text']);
  assertEquals(a.log, ['write en WhatsApp is it free?', 'text +971500000021 MODEL: is it free?']);
  const c = io(false);
  const s = await deliverReasoned(meaningRow('wa_inbound.intent_table', 'how many suppliers do you have', wa), answered('size'), c.x);
  assertEquals(s.via, 'whatsapp_template');
  assertMatch(c.log[1], /^template \+971500000021 en \[how many suppliers do you have\] MODEL: /);
});

Deno.test('WhatsApp meaning: nothing more is sent for none, for a person (its own held row delivers that), or with no phone', async () => {
  const { x, log } = io(true);
  for (const [choice, subject] of [['none', { phone: '+971500000021' }], ['intent:contact_human', { phone: '+971500000021' }], ['intent:pricing', {}]] as const) {
    const d = await deliverReasoned(meaningRow('wa_inbound.intent_table', 'q', subject), answered(choice), x);
    assertEquals([d.delivered, d.via], [false, 'none'], choice);
  }
  assertEquals(log, []);
});

Deno.test('social meaning: the grounded reply is sent on the platform; none sends nothing', async () => {
  const { x, log } = io(true);
  const subject = { platform: 'instagram', message_id: 'mZZDEMO', passages: [] };
  const d = await deliverReasoned(meaningRow('marketing_social.library_match', 'who sets the warranty?', subject), answered('kb:0'), x);
  assertEquals([d.delivered, d.via], [true, 'social']);
  const n = await deliverReasoned(meaningRow('marketing_social.library_match', 'what is the weather', subject), answered('none'), x);
  assertEquals([n.delivered, n.via], [false, 'none']);
  assertEquals(log, ['reply instagram mZZDEMO kb:0']);
});

// Batch 8 (accountant + marketing): the effect of an expense or outreach reasoning, reached through deliverReasoned.
Deno.test('an expenses-mailbox email reasoned to be a receipt re-runs the accountant sweep; one reasoned "other" goes to the bookkeeper', async () => {
  const { x, log } = io(true);
  const sub = { email_id: 'zz-demo-e1', mailbox: 'expenses', provider_email_id: 'zz-demo-e1' };
  const yes = await deliverReasoned(row('accountant.document_kind', 'Fw: receipt', sub), answered('receipt_monthly', 'A monthly subscription receipt.'), x);
  assertEquals([yes.delivered, yes.via], [true, 'accountant_sweep']);
  const no = await deliverReasoned(row('accountant.document_kind', 'Fw: hello', sub), answered('other', 'Not an expense.'), x);
  assertEquals([no.delivered, no.via], [true, 'bookkeeper'], 'an expenses-mailbox email reasoned "other" still reaches a person');
  const other = await deliverReasoned(row('accountant.receipt_vendor', 'Fw: invoice', { email_id: 'zz-demo-e2', mailbox: 'other', provider_email_id: 'zz-demo-e2' }), answered('Apify', 'Apify issued it.'), x);
  assertEquals([other.delivered, other.via], [true, 'bookkeeper']);
  assertEquals(log, ['sweep zz-demo-e1', 'bookkeeper zz-demo-e1', 'bookkeeper zz-demo-e2']);
});

Deno.test('a LinkedIn reply reasoned after the hold gets its class and its drafted follow-up', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('marketing.outreach_reply', 'thanks, not for now', { mark_token: 'zz-tok' }), answered('later', 'Not now, not a refusal.'), x);
  assertEquals([d.delivered, d.via], [true, 'outreach_follow_up']);
  assertEquals(log, ['outreach zz-tok later draft']);
});

Deno.test('a held Arabic translation: a waiting regenerated quotation is rendered and asked for approval; anything else was already stored', async () => {
  const { x, log } = io(true);
  const r = (subject: Record<string, unknown>): HeldRow => ({ id: 9, seat: 'sales_engineer', surface: 'sales_engineer.document_arabic', subject, request: { seat: 'sales_engineer', surface: 'sales_engineer.document_arabic', question: 'x' } });
  // whoever filed the lines first (another document, another quote), every waiting quotation is looked up by its own id
  const d = await deliverReasoned(r({ sources: ['a'], inquiry_id: 'zz-other-document' }), answered(null, '{"1":"أ"}'), x);
  assertEquals([d.delivered, log], [true, ['arabic ready']]);
  const { x: bare } = io(true); delete (bare as Partial<DeliveryIO>).arabicFinishReady;
  assertEquals((await deliverReasoned(r({ sources: ['a'] }), answered(null), bare)).delivered, false);
});

Deno.test('a public comment whose CLASS was held runs through the comment policy with the reasoned class, once', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('marketing_social.comment_classify', 'I need a quote for my villa', { platform: 'instagram', message_id: 'c9' }), answered('sales_lead'), x);
  assertEquals([d.delivered, d.via], [true, 'social']);
  assertEquals(log, ['classified instagram c9 sales_lead']);
  const none = await deliverReasoned(row('marketing_social.comment_classify', 'x', { platform: 'instagram', message_id: 'c10' }), answered(null), x);
  assertEquals([none.delivered, none.via], [false, 'none']);
  assertEquals(log.length, 1);
});

Deno.test('the website widget: a visitor reasoned to have asked for a person is reported to the CEO; otherwise nothing', async () => {
  const { x, log } = io(true);
  const yes = await deliverReasoned(row('site_assistant.person', 'can I talk to someone real please', { path: '/pricing' }), answered('needs_a_person'), x);
  assertEquals([yes.delivered, yes.via], [true, 'none']);
  assertEquals(log, ['ceo widget:person:held:7']);
  const no = await deliverReasoned(row('site_assistant.person', 'how do fees work?', { path: '/' }), answered('no_person'), x);
  assertEquals(no.delivered, false);
  assertEquals(log.length, 1);
});

Deno.test('a holding notice that failed is recorded as failed and sent again; a throw is a failed attempt, not a lost batch', async () => {
  const { x } = io(true);
  let fail = true;
  const flaky: DeliveryIO = { ...x, sendWaText: () => Promise.resolve(fail ? { ok: false, err: 'twilio 63016' } : { ok: true }) };
  const rec: [number, boolean][] = [];
  const record = (id: number, d: { delivered: boolean }) => { rec.push([id, d.delivered]); return Promise.resolve(); };
  const rows = [{ id: 7, surface: 'wa_inbound.needs_a_person', question: 'where is my quote?', subject: { phone: '+971500000001' } }];
  const first = await sendHeldNotices(rows, flaky, record);
  assertEquals(first.map((r) => r.delivered), [false]);
  fail = false;                              // the next tick, fn_reason_held_notice_due returns the same row
  const second = await sendHeldNotices(rows, flaky, record);
  assertEquals(second.map((r) => r.delivered), [true]);
  assertEquals(rec, [[7, false], [7, true]]);
  const throwing: DeliveryIO = { ...x, waWindowOpen: () => Promise.reject(new Error('db down')) };
  const t = await sendHeldNotices([...rows, { ...rows[0], id: 8 }], throwing, record);
  assertEquals(t.map((r) => [r.id, r.delivered]), [[7, false], [8, false]]);
});

// ── A HELD COMMENT IS REPLAYED WITH ITS OWN PLATFORM'S TOKEN (24 Sep 2026; found in the review of PR #898) ─────────
// Until this change the replay gave LinkedIn the Meta page token and YouTube none, so neither could post. Here the
// real policy (processComment) runs over an in-memory store whose reply posts exactly as the live store does
// (marketing_social_store.ts: call(f, replyRequest(ev, text, await tokenFor(ev)))), and fetch is stubbed: nothing
// here can reach an account. The YouTube and LinkedIn tokens go through the real accessToken(), sealed and opened
// with a test key.
const MASTER = 'test-master-key-that-is-long-enough';
type Req = { url: string; auth: string; body: string };
function replayRig(o: { stored?: Partial<Record<SocialPlatform, Record<string, unknown>>>; refresh?: { status: number; json: unknown } } = {}) {
  const posted: Req[] = []; const metaLookups: string[] = []; const saved: string[] = []; let processed = 0;
  const f = (url: string, init?: RequestInit) => {
    const h = (init?.headers ?? {}) as Record<string, string>;
    if (url === 'https://oauth2.googleapis.com/token') {
      const r = o.refresh ?? { status: 200, json: { access_token: 'yt-refreshed', expires_in: 3600 } };
      return Promise.resolve(new Response(JSON.stringify(r.json), { status: r.status }));
    }
    posted.push({ url, auth: String(h.Authorization ?? ''), body: String(init?.body ?? '') });
    return Promise.resolve(new Response(JSON.stringify({ id: 'reply-1' }), { status: 201 }));
  };
  const sealed: Record<string, string> = {};
  const ready = (async () => {
    for (const [p, t] of Object.entries(o.stored ?? {})) sealed[p + '_oauth'] = await seal(MASTER, t);
  })();
  const sec = async (k: string) => { await ready; return sealed[k] ?? ({ google_oauth_client_id: 'gid', google_oauth_client_secret: 'gsecret' } as Record<string, string>)[k]; };
  const store = (tokenFor: (ev: CommentEvent) => Promise<string | null>): Store => ({
    insertInbound: () => Promise.resolve(1), release: () => Promise.resolve(), threadAllowed: () => Promise.resolve(true),
    record: () => Promise.resolve(), handoff: () => Promise.resolve(null), switchOn: () => Promise.resolve(true),
    write: () => Promise.resolve('Thank you for the kind words.'),
    async reply(ev, text) { const t = await tokenFor(ev); return t ? await call(f, replyRequest(ev, text, t)) : { ok: false, error: 'no credential for ' + ev.platform }; },
    async hide() { return { ok: false, error: 'not in this test' }; },
  });
  const rio = (ev: CommentEvent): CommentReplayIO => ({
    ownToken: (p) => accessToken(f, p, MASTER, sec, async (k, v) => { saved.push(k); sealed[k] = v; }),
    metaPageToken: (p, a) => { metaLookups.push(p + ':' + a); return Promise.resolve('meta-page-token'); },
    process: (tokenFor) => { processed++; return processComment(store(tokenFor), ev, 'praise'); },
  });
  return { posted, metaLookups, saved, rio, processed: () => processed };
}
const heldComment = (platform: CommentEvent['platform'], over: Partial<CommentEvent> = {}): CommentEvent => ({
  platform, accountId: platform === 'linkedin' ? 'urn:li:organization:111' : 'ACCOUNT', commentId: platform === 'linkedin' ? 'urn:li:comment:(urn:li:activity:9,77)' : 'cmt-1',
  authorId: 'author-1', handle: null, text: 'Great work on this project', at: new Date(), threadId: platform === 'linkedin' ? 'urn:li:activity:9' : 'post-1', ...over,
});
const later = Date.now() + 3600_000;

Deno.test('a replayed LinkedIn comment posts with the LinkedIn company-page token, never the Meta page token', async () => {
  const rig = replayRig({ stored: { linkedin: { platform: 'linkedin', account_id: '111', access_token: 'li-token', expires_at: later, connected_at: '' } } });
  const ev = heldComment('linkedin');
  const s = await replayHeldComment(ev, rig.rio(ev));
  assertEquals(s, { ok: true, err: 'replied' });
  assertEquals(rig.metaLookups, [], 'the Meta page-token lookup is never asked for a LinkedIn comment');
  assertEquals(rig.posted.length, 1);
  assertEquals(rig.posted[0].auth, 'Bearer li-token');
  // The same request the live path builds: the Community Management API, as the company page.
  assertEquals(rig.posted[0].url, 'https://api.linkedin.com/rest/socialActions/' + encodeURIComponent(ev.commentId) + '/comments');
  assertEquals(JSON.parse(rig.posted[0].body), { actor: ev.accountId, object: ev.threadId, parentComment: ev.commentId, message: { text: 'Thank you for the kind words.' } });
});

Deno.test('a replayed YouTube comment posts with the YouTube token, refreshed through accessToken when it has lapsed', async () => {
  const rig = replayRig({ stored: { youtube: { platform: 'youtube', account_id: 'UC1', access_token: 'yt-old', expires_at: Date.now() - 1000, refresh_token: 'yt-refresh', connected_at: '' } } });
  const ev = heldComment('youtube');
  const s = await replayHeldComment(ev, rig.rio(ev));
  assertEquals(s, { ok: true, err: 'replied' });
  assertEquals(rig.metaLookups, []);
  assertEquals(rig.saved, ['youtube_oauth'], 'the refreshed token set is re-sealed where it was read');
  assertEquals(rig.posted.length, 1);
  assertEquals(rig.posted[0].auth, 'Bearer yt-refreshed');
  assertEquals(rig.posted[0].url, 'https://www.googleapis.com/youtube/v3/comments?part=snippet');
  assertEquals(JSON.parse(rig.posted[0].body), { snippet: { parentId: ev.commentId, textOriginal: 'Thank you for the kind words.' } });
});

Deno.test('Instagram and Facebook are unchanged: the page token is looked up for the page, at the send', async () => {
  for (const platform of ['instagram', 'facebook'] as const) {
    const rig = replayRig();
    const ev = heldComment(platform, { accountId: 'PAGE-' + platform });
    const s = await replayHeldComment(ev, rig.rio(ev));
    assertEquals(s, { ok: true, err: 'replied' });
    assertEquals(rig.metaLookups, [platform + ':PAGE-' + platform]);
    assertEquals(rig.posted.length, 1);
    assertEquals(rig.posted[0].auth, 'Bearer meta-page-token');
    assertEquals(rig.posted[0].url, 'https://graph.facebook.com/v21.0/cmt-1/' + (platform === 'instagram' ? 'replies' : 'comments'));
  }
});

Deno.test('LinkedIn or YouTube not connected: a named skip, nothing run, nothing posted, nothing thrown', async () => {
  for (const platform of ['linkedin', 'youtube'] as const) {
    const rig = replayRig();
    const ev = heldComment(platform);
    const s = await replayHeldComment(ev, rig.rio(ev));
    assertEquals(s, { ok: false, skipped: platform + ' token missing' });
    assertEquals([rig.processed(), rig.posted.length, rig.metaLookups.length], [0, 0, 0], 'the policy never ran, so the comment stays held_classify');
  }
});

Deno.test('a YouTube token that cannot be refreshed is a named skip too, not a throw', async () => {
  const rig = replayRig({ stored: { youtube: { platform: 'youtube', account_id: 'UC1', access_token: 'yt-old', expires_at: Date.now() - 1000, refresh_token: 'revoked', connected_at: '' } },
    refresh: { status: 400, json: { error: 'invalid_grant' } } });
  const ev = heldComment('youtube');
  const s = await replayHeldComment(ev, rig.rio(ev));
  assertEquals(s.ok, false);
  assertMatch(String(s.skipped), /^youtube token refresh failed: youtube token refresh HTTP 400: invalid_grant/);
  assertEquals([rig.processed(), rig.posted.length], [0, 0]);
});

Deno.test('the held-comment delivery reports the skip by name and does not count it delivered', async () => {
  const { x } = io(true);
  const rig = replayRig();
  x.socialCommentClassified = (subject) => replayHeldComment(heldComment(subject.platform as CommentEvent['platform']), rig.rio(heldComment(subject.platform as CommentEvent['platform'])));
  const d = await deliverReasoned(row('marketing_social.comment_classify', 'nice', { platform: 'linkedin', message_id: 'c11' }), answered('praise'), x);
  assertEquals(d, { delivered: false, via: 'social', detail: 'skipped: linkedin token missing' });
});

// ── THE LIVE WIRING (review of PR #969): liveDeliveryIO.socialCommentClassified reads the platform's own key through
// accessToken, opened with the service-role key, and re-seals a refresh compare-and-set. A fake service-role client
// holds app_secrets and the held comment; every other table answers with an error, so a run that gets past the token
// stops at the store and never reaches a platform.
function fakeAdmin(secrets: Record<string, string>, comment: Record<string, unknown>) {
  const asked: string[] = []; const writes: { key: string; expected: string; wrote: boolean }[] = [];
  const from = (table: string) => {
    const f: Record<string, unknown> = {}; let op = 'select'; let payload: Record<string, unknown> = {};
    const q = {
      select() { return q; },
      eq(c: string, v: unknown) { f[c] = v; return q; },
      update(v: Record<string, unknown>) { op = 'update'; payload = v; return q; },
      upsert() { op = 'upsert'; return q; },
      maybeSingle() {
        if (table === 'app_secrets') { const k = String(f.key); asked.push(k); return Promise.resolve({ data: k in secrets ? { value: secrets[k] } : null }); }
        if (table === 'social_message') return Promise.resolve({ data: comment });
        return Promise.resolve({ data: null, error: { message: 'fake: no ' + table } });
      },
      single() { return Promise.resolve({ data: null, error: { message: 'fake: no ' + table } }); },
      then(res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) {
        let out: unknown = { data: null, error: { message: 'fake: no ' + table } };
        if (table === 'app_secrets' && op === 'update') {
          const k = String(f.key); const hit = secrets[k] === f.value;
          writes.push({ key: k, expected: String(f.value), wrote: hit });
          if (hit) secrets[k] = String(payload.value);
          out = { data: hit ? [{ key: k }] : [], error: null };
        }
        return Promise.resolve(out).then(res, rej);
      },
    };
    return q;
  };
  return { admin: { from }, secrets, asked, writes };
}
const heldRow = (platform: string) => ({ id: 5, meta_message_id: 'cmt-9', platform, body: 'Great work on this project', parent_id: 'post-9',
  occurred_at: new Date().toISOString(), outcome: 'held_classify', conversation: { user_id: 'author-9', handle: null, account_id: 'urn:li:organization:111' } });
const noNetwork = () => Promise.reject(new Error('no network in this test'));

Deno.test('live wiring: a LinkedIn comment with no stored token reads linkedin_oauth and skips by name', async () => {
  const { admin, asked } = fakeAdmin({}, heldRow('linkedin'));
  const s = await liveDeliveryIO(admin, { master: MASTER, fetch: noNetwork }).socialCommentClassified({ platform: 'linkedin', message_id: 'cmt-9' }, 'praise');
  assertEquals(s, { ok: false, skipped: 'linkedin token missing' });
  assertEquals(asked, ['linkedin_oauth']);
});

Deno.test('live wiring: a stored LinkedIn token is opened with the key and the replay goes on to the policy; a wrong key opens nothing', async () => {
  const sealed = await seal(MASTER, { platform: 'linkedin', account_id: '111', access_token: 'li-token', expires_at: Date.now() + 3600_000, connected_at: '' });
  const a = fakeAdmin({ linkedin_oauth: sealed }, heldRow('linkedin'));
  const s = await liveDeliveryIO(a.admin, { master: MASTER, fetch: noNetwork }).socialCommentClassified({ platform: 'linkedin', message_id: 'cmt-9' }, 'praise');
  // Past the token: the fake store refuses the conversation row, so the run stops there. Not skipped, not sent.
  assertEquals(s, { ok: false, err: 'conversation: fake: no social_conversation' });
  assertEquals(a.asked, ['linkedin_oauth']);
  const b = fakeAdmin({ linkedin_oauth: sealed }, heldRow('linkedin'));
  const w = await liveDeliveryIO(b.admin, { master: 'a-different-key-of-enough-length', fetch: noNetwork }).socialCommentClassified({ platform: 'linkedin', message_id: 'cmt-9' }, 'praise');
  assertEquals(w, { ok: false, skipped: 'linkedin token missing' });
});

Deno.test('live wiring: a lapsed YouTube token is refreshed and re-sealed only over the value that was read', async () => {
  const lapsed = { platform: 'youtube', account_id: 'UC1', access_token: 'yt-old', expires_at: Date.now() - 1000, refresh_token: 'yt-refresh', connected_at: '' };
  const refreshed = () => new Response(JSON.stringify({ access_token: 'yt-refreshed', expires_in: 3600 }), { status: 200 });
  const client = { google_oauth_client_id: 'gid', google_oauth_client_secret: 'gs' };
  // Unchanged since the read: the refreshed set replaces it.
  const old = await seal(MASTER, lapsed);
  const a = fakeAdmin({ youtube_oauth: old, ...client }, heldRow('youtube'));
  const s = await liveDeliveryIO(a.admin, { master: MASTER, fetch: (u) => Promise.resolve(u === 'https://oauth2.googleapis.com/token' ? refreshed() : new Response('{}', { status: 500 })) })
    .socialCommentClassified({ platform: 'youtube', message_id: 'cmt-9' }, 'praise');
  assertEquals(s.skipped, undefined);
  assertEquals(a.asked, ['youtube_oauth', 'google_oauth_client_id', 'google_oauth_client_secret']);
  assertEquals(a.writes, [{ key: 'youtube_oauth', expected: old, wrote: true }]);
  assertEquals((await open<{ access_token: string }>(MASTER, a.secrets.youtube_oauth))?.access_token, 'yt-refreshed');
  // The founder reconnects while the refresh is in flight: the newer token set is kept, not overwritten.
  const b = fakeAdmin({ youtube_oauth: old, ...client }, heldRow('youtube'));
  const reconnected = await seal(MASTER, { ...lapsed, access_token: 'yt-reconnected', expires_at: Date.now() + 3600_000, refresh_token: 'new' });
  await liveDeliveryIO(b.admin, { master: MASTER, fetch: (u) => {
    if (u === 'https://oauth2.googleapis.com/token') { b.secrets.youtube_oauth = reconnected; return Promise.resolve(refreshed()); }
    return Promise.resolve(new Response('{}', { status: 500 }));
  } }).socialCommentClassified({ platform: 'youtube', message_id: 'cmt-9' }, 'praise');
  assertEquals(b.writes, [{ key: 'youtube_oauth', expected: old, wrote: false }], 'the save found a newer value and wrote nothing');
  assertEquals(b.secrets.youtube_oauth, reconnected, 'the reconnected token set stands');
});

Deno.test('casSecrets: nothing read, nothing written', async () => {
  const { admin, writes } = fakeAdmin({ youtube_oauth: 'v1.stored' }, {});
  await casSecrets(admin).save('youtube_oauth', 'v1.other');
  assertEquals(writes, []);
});

// ── e-mail (email_triage, 28 Sep 2026) ──────────────────────────────────────────────────────────────
const mailIO = () => { const { x, log } = io(false); x.emailReply = (id, text, person) => { log.push(`mail ${id} ${person} ${text}`); return Promise.resolve({ ok: true }); }; return { x, log }; };

Deno.test('e-mail: a held answer, once verified, follows the receipt into the same thread', async () => {
  const { x, log } = mailIO();
  const r = { ...answered(null, 'You pay 3% only when you reveal.'), verified: { status: 'agreed' as const, by: 'm', notes: '' } };
  const d = await deliverReasoned(row('email_triage.reply', 'When do I pay?', { message_id: 42, channel: 'email' }, false), r, x);
  assertEquals([d.delivered, d.via], [true, 'email']);
  assertMatch(log[0], /^mail 42 false Hello,\n\nYou pay 3% only when you reveal\./);
});

Deno.test('e-mail: an unverified answer is not sent; a reasoned request for a person is', async () => {
  const { x, log } = mailIO();
  const d1 = await deliverReasoned(row('email_triage.reply', 'q', { message_id: 42, channel: 'email' }, false), answered(null, 'x'), x);
  assertEquals(d1.delivered, false);
  const d2 = await deliverReasoned(row('email_triage.needs_a_person', 'let me talk to a human', { message_id: 42, channel: 'email' }), answered('needs_a_person'), x);
  assertEquals([d2.delivered, d2.via], [true, 'email']);
  assertMatch(log[0], /^write en e-mail let me talk to a human/);
  assertMatch(log[1], /^mail 42 true Hello,\n\nMODEL: let me talk to a human/);
  const d3 = await deliverReasoned(row('email_triage.needs_a_person', 'when do I pay', { message_id: 42, channel: 'email' }), answered('no_person'), x);
  assertEquals(d3.delivered, false);
  assertEquals(log.length, 2);
});
