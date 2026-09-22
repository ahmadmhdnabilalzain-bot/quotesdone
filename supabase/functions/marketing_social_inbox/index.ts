// marketing_social_inbox — the marketing seat's front door on Instagram and Facebook (Meta webhook).
//
// Seat: marketing. Founder, 22 Sep 2026: "if there was any communication on Instagram or any social
// media platform, there should be an automated reply in which he is aware of and he carries on …
// Only if a customer is asking 'I want to speak with an agent', that's where I get a notification on
// my email, and I'll carry on. He should be wired to the company knowledge."
//
// Per message or comment Meta delivers:
//   1. the signature is checked over the raw body (meta_app_secret) — unsigned means 403, no read;
//   2. the message is stored (social_conversation / social_message, kept forever, owner marketing);
//      a redelivery hits the unique (platform, meta_message_id) and stops there — idempotency;
//   3. an echo (something the PAGE said) is never answered: the seat's own echo is recognised, and an
//      echo the seat did not send means a person answered in the Meta inbox, so the seat steps back;
//   4. a conversation handed to a human is not auto-answered until the founder hands it back
//      (fn_marketing_social_set_status … 'auto');
//   5. Meta's 24-hour window and our own per-person and global rate limits are applied;
//   6. reply.ts decides the answer without a model; asking for a person hands the conversation to
//      the founder through fn_marketing_social_hand_to_human -> fn_notify_founder(p_kind 'social_human_request');
//   7. the reply is SENT only when app_secrets.social_send_enabled = 'on' and a page token exists.
//      Until the founder's Meta app is connected the reply is stored as held_switch_off — the whole
//      path runs, nothing reaches anyone.
//
// Secrets, by key name in public.app_secrets: meta_app_secret, meta_webhook_verify_token,
// meta_page_access_token, meta_app_id (optional; recognises our Messenger echoes), social_send_enabled,
// social_model_enabled (off: the model is held — OpenRouter is on hold), cred_fn_ai (the gateway key).
//
// META APP SETUP (the founder's side). Callback URL:
//   <SUPABASE_URL>/functions/v1/marketing_social_inbox   (the project's own URL; the ref is not written here)
// Verify token: the value stored in app_secrets.meta_webhook_verify_token. Subscribe: Page -> messages,
// message_echoes, feed; Instagram -> messages, comments. Permissions: pages_messaging,
// pages_manage_metadata, pages_read_engagement, pages_manage_engagement, instagram_basic,
// instagram_manage_messages, instagram_manage_comments. Then store the Page token as
// meta_page_access_token, the app secret as meta_app_secret, and set social_send_enabled = 'on'.
//
// OTHER PLATFORMS — what their official APIs allow, as documented by the platforms (not tested here;
// no scraping, ever). LinkedIn: messages to a company Page are not open to third-party apps; comments
// on the Page's own posts can be read and answered through the Community Management API after LinkedIn
// approves the app. TikTok: direct messages to a business account are a limited-access Business
// Messaging API; comments on the account's own videos are available through the TikTok API for
// Business after approval. Either would be a second parser beside meta.ts feeding the same tables.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import type { FaqRow } from '../_shared/chat_answers.ts';
import { clip, handshake, maxLen, OUR_METADATA, parseEvents, sendRequest, verifySignature, withinWindow, type InboundEvent } from './meta.ts';
import { decide, unknown, type CorpusRow, type Decision, type LibraryRow } from './reply.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const GATEWAY = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  const v = String(data?.value ?? '').trim();
  return v || undefined;
}
async function rl(key: string, limit: number, seconds: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); return error ? true : data !== false; }
  catch (_e) { return true; }
}
// A fixture can never be messaged, whatever the switch says (tests use ZZDEMO ids and ZZ DEMO names).
const isFixture = (ev: InboundEvent) => /^ZZDEMO/i.test(ev.userId) || /^ZZ DEMO/i.test(ev.handle || '');

Deno.serve(observe('marketing_social_inbox', async (req) => {
  const url = new URL(req.url);
  if (req.method === 'GET') {
    const challenge = handshake(url, await sec('meta_webhook_verify_token'));
    return challenge ? new Response(challenge, { status: 200, headers: { 'Content-Type': 'text/plain' } }) : new Response('forbidden', { status: 403 });
  }
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });

  const raw = await req.text();
  if (!(await verifySignature(raw, req.headers.get('x-hub-signature-256'), await sec('meta_app_secret')))) {
    return new Response('invalid signature', { status: 403 });
  }
  let body: unknown;
  try { body = JSON.parse(raw); } catch (_e) { return new Response('bad json', { status: 400 }); }

  const outcomes: string[] = [];
  for (const ev of parseEvents(body)) {
    // One bad event must not make Meta redeliver the whole batch: each is handled on its own, and
    // the batch is acknowledged with 200 either way (Meta disables a webhook that keeps failing).
    try { outcomes.push(await handle(ev)); }
    catch (e) { outcomes.push('error:' + String((e as Error)?.message || e).slice(0, 120)); }
  }
  return new Response(JSON.stringify({ ok: true, outcomes }), { status: 200, headers: { 'Content-Type': 'application/json' } });
}));

async function handle(ev: InboundEvent): Promise<string> {
  // THE CONVERSATION, one per person per platform, owned by the marketing seat.
  const convRow: Record<string, unknown> = { platform: ev.platform, user_id: ev.userId, account_id: ev.accountId };
  if (ev.handle) convRow.handle = ev.handle;
  if (!ev.echo) convRow.last_inbound_at = ev.at.toISOString();
  const { data: conv, error: cErr } = await admin.from('social_conversation')
    .upsert(convRow, { onConflict: 'platform,user_id' }).select('id,status,handle').single();
  if (cErr || !conv) throw new Error('conversation: ' + (cErr?.message || 'no row'));

  if (ev.echo) return await echo(ev, conv.id, conv.status);

  // IDEMPOTENCY. Meta redelivers on any slow or failed acknowledgement; the second copy stops here.
  const { data: ins, error: iErr } = await admin.from('social_message').upsert({
    conversation_id: conv.id, platform: ev.platform, channel: ev.channel, direction: 'in', author: 'person',
    meta_message_id: ev.messageId, parent_id: ev.parentId, body: ev.text, occurred_at: ev.at.toISOString(),
  }, { onConflict: 'platform,meta_message_id', ignoreDuplicates: true }).select('id');
  if (iErr) throw new Error('message: ' + iErr.message);
  if (!ins || !ins.length) return 'duplicate';
  const inId = ins[0].id as number;
  const outcome = async (o: string) => { await admin.from('social_message').update({ outcome: o }).eq('id', inId); return o; };

  if (conv.status !== 'auto') return await outcome('human_holds_conversation');
  if (!withinWindow(ev.at)) return await outcome('outside_window');
  if (!(await rl('social_user:' + ev.platform + ':' + ev.userId, 6, 600)) || !(await rl('social_global', 300, 3600))) {
    return await outcome('rate_limited');
  }

  const d = await answer(ev);
  if (d.kind === 'unknown') {
    // The question is kept word for word as a knowledge gap, the same mechanism the widget uses.
    try { await admin.rpc('fn_support_knowledge_gap', { p_question: ev.text, p_refusal: 'no_grounded_answer', p_surface: ev.platform + '_' + ev.channel }); } catch (_e) { /* the reply still goes */ }
  }
  const text = clip(d.text, maxLen(ev.platform, ev.channel));
  if (!text) return await outcome('no_reply_text');

  const { data: out, error: oErr } = await admin.from('social_message').insert({
    conversation_id: conv.id, platform: ev.platform, channel: ev.channel, direction: 'out', author: 'seat',
    in_reply_to: inId, body: text, reply_kind: d.kind, reply_key: d.key, send_status: 'pending', occurred_at: new Date().toISOString(),
  }).select('id').single();
  if (oErr || !out) throw new Error('reply row: ' + (oErr?.message || 'no row'));

  if (d.kind === 'handoff') {
    const token = await sec('meta_page_access_token');
    if (!conv.handle && token && !isFixture(ev)) await fillHandle(ev, conv.id, token);
    await admin.rpc('fn_marketing_social_hand_to_human', { p_conversation_id: conv.id, p_reason: ev.text });
  }
  await send(ev, out.id as number, text);
  return await outcome(d.kind === 'handoff' ? 'handed_to_human' : 'answered:' + d.kind);
}

/** Deterministic first; the model only when switched on, only over retrieved knowledge. */
async function answer(ev: InboundEvent): Promise<Decision> {
  const [{ data: lib }, { data: faqs }] = await Promise.all([
    admin.from('social_reply_library').select('key,priority,match_words,reply_en,reply_ar,active').eq('active', true),
    admin.from('company_faq').select('id,question,answer,language').eq('public', true).eq('status', 'approved'),
  ]);
  let corpus: CorpusRow[] = [];
  try {
    const { data } = await admin.rpc('fn_support_corpus_search', { p_query: ev.text, p_public: true, p_limit: 6 });
    corpus = (data || []) as CorpusRow[];
  } catch (_e) { corpus = []; }
  const library = (lib || []) as LibraryRow[];
  const d = decide(ev.text, library, (faqs || []) as FaqRow[], corpus);
  if (d.kind !== 'unknown' || !corpus.length || (await sec('social_model_enabled')) !== 'on') return d;

  // THE MODEL, SAME DOOR AS THE WEBSITE ASSISTANT (ai_gateway), and only over the passages retrieved
  // for this question. OFF until the founder lifts the OpenRouter hold; the honest 'unknown' stands.
  const key = await sec('cred_fn_ai');
  if (!key) return d;
  const sys = 'You are QuotesDone on ' + ev.platform + '. Answer ONLY from the KNOWLEDGE below, in the language of the message'
    + (d.lang === 'ar' ? ' (formal Gulf Arabic, formal plural)' : ' (UAE English)') + ', in under 80 words, plain text. '
    + 'Never state a price, fee, date, timeline or promise that is not written in the KNOWLEDGE. If the KNOWLEDGE does not answer it, reply exactly UNKNOWN.\n\nKNOWLEDGE:\n'
    + corpus.map((c) => c.content).join('\n\n');
  try {
    const r = await fetch(GATEWAY, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
      __secret: key, fn: 'marketing_social_inbox', agent: 'marketing', task_class: 'visitor_chat', sys,
      input: [{ role: 'user', content: ev.text }], max: 300, temperature: 0.2, cache_ttl_min: 0, try_faq: false }) });
    const jd = await r.json();
    const c = typeof jd?.content === 'string' ? jd.content.trim() : '';
    if (c && !/^UNKNOWN\b/.test(c)) return { kind: 'knowledge', key: 'model', lang: d.lang, text: c };
  } catch (_e) { /* fall through to the honest answer */ }
  return unknown(library, d.lang);
}

/** An echo is never answered. Ours is recorded; one the seat did not send means a person answered. */
async function echo(ev: InboundEvent, convId: number, status: string): Promise<string> {
  const { data: seen } = await admin.from('social_message').select('id').eq('platform', ev.platform).eq('meta_message_id', ev.messageId).maybeSingle();
  if (seen) return 'echo:ours';
  const appId = await sec('meta_app_id');
  const ours = ev.echoMetadata === OUR_METADATA || (!!appId && ev.echoAppId === appId);
  if (!ours) {
    // Instagram carries no metadata: the echo can arrive before the send call returned its id, so
    // a seat reply with the same text in the last two minutes that has no id yet is this echo.
    const { data: pend } = await admin.from('social_message').select('id').eq('conversation_id', convId).eq('direction', 'out')
      .eq('author', 'seat').is('meta_message_id', null).eq('body', ev.text)
      .gte('created_at', new Date(Date.now() - 120000).toISOString()).limit(1);
    if (pend && pend.length) {
      await admin.from('social_message').update({ meta_message_id: ev.messageId }).eq('id', pend[0].id);
      return 'echo:ours';
    }
  }
  if (ours) return 'echo:ours';
  await admin.from('social_message').upsert({
    conversation_id: convId, platform: ev.platform, channel: ev.channel, direction: 'out', author: 'human',
    meta_message_id: ev.messageId, body: ev.text, occurred_at: ev.at.toISOString(), send_status: 'sent',
  }, { onConflict: 'platform,meta_message_id', ignoreDuplicates: true });
  if (status === 'auto') {
    await admin.rpc('fn_marketing_social_set_status', { p_conversation_id: convId, p_status: 'handed_to_human', p_by: 'meta_inbox_reply' });
  }
  return 'echo:human';
}

async function send(ev: InboundEvent, outId: number, text: string): Promise<void> {
  const set = (o: Record<string, unknown>) => admin.from('social_message').update(o).eq('id', outId);
  if (isFixture(ev)) { await set({ send_status: 'held_fixture' }); return; }
  const token = await sec('meta_page_access_token');
  if ((await sec('social_send_enabled')) !== 'on' || !token) { await set({ send_status: 'held_switch_off' }); return; }
  try {
    const { url, body } = sendRequest(ev, text, token);
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    if (r.ok) await set({ send_status: 'sent', sent_at: new Date().toISOString(), meta_message_id: j?.message_id || j?.id || null });
    else await set({ send_status: 'failed', send_error: String(j?.error?.message || r.status).slice(0, 300) });
  } catch (e) { await set({ send_status: 'failed', send_error: String((e as Error)?.message || e).slice(0, 300) }); }
}

async function fillHandle(ev: InboundEvent, convId: number, token: string): Promise<void> {
  try {
    const r = await fetch('https://graph.facebook.com/v21.0/' + encodeURIComponent(ev.userId) + '?fields=name,username&access_token=' + encodeURIComponent(token));
    const j = await r.json();
    const h = j?.username || j?.name;
    if (r.ok && h) await admin.from('social_conversation').update({ handle: String(h).slice(0, 120) }).eq('id', convId);
  } catch (_e) { /* the founder is told the id instead */ }
}
