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
//   7. the reply is SENT only when app_secrets.social_send_enabled = 'on' and a page token can be derived.
//      Until the founder's Meta app is connected the reply is stored as held_switch_off — the whole
//      path runs, nothing reaches anyone.
//
// Secrets, by key name in public.app_secrets: meta_app_secret, meta_webhook_verify_token, meta_access_token
// (the system-user token; the page token, page id and IG id are derived from it through me/accounts and
// cached in public.marketing_meta_page, refetched on a Graph 190), meta_app_id (optional; recognises our
// Messenger echoes), social_send_enabled,
// social_model_enabled (off: the model is held — OpenRouter is on hold), cred_fn_ai (the gateway key).
//
// META APP SETUP: scripts/marketing/connect_social_inbox.mjs does all of it once meta_app_secret is stored.
// Callback URL:
//   <SUPABASE_URL>/functions/v1/marketing_social_inbox   (the project's own URL; the ref is not written here)
// Verify token: the value stored in app_secrets.meta_webhook_verify_token. Subscribe: Page -> messages,
// message_echoes, feed; Instagram -> messages, comments. Permissions: pages_messaging,
// pages_manage_metadata, pages_read_engagement, pages_manage_engagement, instagram_basic,
// instagram_manage_messages, instagram_manage_comments (all carried by meta_access_token, measured 22 Sep).
//
// COMMENTS (23 Sep 2026, instruction 866): a public comment is not a conversation. It goes to processComment
// (_shared/marketing_social_comments.ts), the one comment policy YouTube also uses (marketing duty
// social_comments). X is removed and LinkedIn is the company page only (founder, 23 Sep 2026): see that file.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { observe } from '../_shared/observe.ts';
import { precedentBlock, recallCases } from '../_shared/case_recall.ts';
import type { FaqRow } from '../_shared/chat_answers.ts';
import { clip, handshake, maxLen, OUR_METADATA, parseEvents, pickPage, sendRequest, tokenExpired, verifySignature, withinWindow, type InboundEvent, type PageAccount } from './meta.ts';
import { decide, passagesFor, unknown, type CorpusRow, type Decision, type LibraryRow } from './reply.ts';
import { socialMeaning } from '../_shared/reasoned_channels.ts';
import { defaultDeps } from '../_shared/think.ts';
import { ackThenWork } from '../_shared/async_webhook.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { needsAPerson } from '../_shared/reasoned_decisions.ts';
import { processComment } from '../_shared/marketing_social_comments.ts';
import { adminStore, metaPageToken } from '../_shared/marketing_social_store.ts';

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
  // THE REASONED HANDOFF (23 Sep 2026). A person check held under the model hold, reasoned later by the
  // replay, arrives here with an internal credential; the handoff is sent on the platform reply path.
  if ((req.headers.get('content-type') || '').includes('application/json')) {
    let j: Record<string, unknown> = {};
    try { j = JSON.parse(raw); } catch (_e) { j = {}; }
    if (j.action === 'reasoned_handoff') {
      const auth = await requireInternal(admin, j.__secret, 'marketing_social_inbox');
      if (!auth.ok) return new Response(JSON.stringify({ ok: false, error: 'forbidden' }), { status: 403 });
      const out = await reasonedHandoff(String(j.platform || ''), String(j.message_id || ''));
      return new Response(JSON.stringify(out), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }
    // A DM's meaning held under the hold, reasoned later: the grounded reply it was owed is sent here.
    if (j.action === 'reasoned_reply') {
      const auth = await requireInternal(admin, j.__secret, 'marketing_social_inbox');
      if (!auth.ok) return new Response(JSON.stringify({ ok: false, error: 'forbidden' }), { status: 403 });
      const out = await reasonedReply(String(j.platform || ''), String(j.message_id || ''), String(j.meaning || ''), (Array.isArray(j.passages) ? j.passages : []) as CorpusRow[]);
      return new Response(JSON.stringify(out), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }
  }
  if (!(await verifySignature(raw, req.headers.get('x-hub-signature-256'), await sec('meta_app_secret')))) {
    return new Response('invalid signature', { status: 403 });
  }
  let body: unknown;
  try { body = JSON.parse(raw); } catch (_e) { return new Response('bad json', { status: 400 }); }

  const events = parseEvents(body);
  const handleAll = async () => {
    const outcomes: string[] = [];
    for (const ev of events) {
      // One bad event must not make Meta redeliver the whole batch: each is handled on its own, and
      // the batch is acknowledged with 200 either way (Meta disables a webhook that keeps failing).
      try { outcomes.push(await handle(ev)); }
      catch (e) { outcomes.push('error:' + String((e as Error)?.message || e).slice(0, 120)); }
    }
    return outcomes;
  };
  // META IS ANSWERED AT ONCE (23 Sep 2026): the signature is verified above, the events are handled after
  // the 200 under EdgeRuntime.waitUntil, so reasoning (think(): several model calls) can never run past
  // Meta's webhook deadline (_shared/async_webhook.ts). Each event's outcome is still written on its row.
  return ackThenWork(new Response(JSON.stringify({ ok: true, accepted: events.length }), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    handleAll, 'marketing_social_inbox');
}));

/** Send the handoff for a message whose person check was reasoned after the fact. Idempotent per message. */
async function reasonedHandoff(platform: string, messageId: string): Promise<{ ok: boolean; error?: string; outcome?: string }> {
  const { data: m } = await admin.from('social_message').select('id,conversation_id,channel,parent_id,body,occurred_at')
    .eq('platform', platform).eq('meta_message_id', messageId).eq('direction', 'in').maybeSingle();
  if (!m) return { ok: false, error: 'message_not_found' };
  const { data: already } = await admin.from('social_message').select('id').eq('in_reply_to', m.id).eq('reply_kind', 'handoff').limit(1);
  if (already && already.length) return { ok: true, outcome: 'already_handed_off' };
  const { data: conv } = await admin.from('social_conversation').select('id,platform,user_id,account_id,handle').eq('id', m.conversation_id).single();
  if (!conv) return { ok: false, error: 'conversation_not_found' };
  const ev: InboundEvent = { platform: conv.platform, channel: m.channel, accountId: conv.account_id, userId: conv.user_id, handle: conv.handle,
    messageId, text: String(m.body || ''), at: new Date(m.occurred_at), parentId: m.parent_id, echo: false, echoAppId: null, echoMetadata: null };
  // Meta's own window decides whether a reply may still be sent (meta.ts); outside it the founder is still told.
  const { data: lib } = await admin.from('social_reply_library').select('key,priority,match_words,reply_en,reply_ar,active').eq('active', true);
  const d = decide(ev.text, (lib || []) as LibraryRow[], [], [], true, null);
  await admin.rpc('fn_marketing_social_hand_to_human', { p_conversation_id: conv.id, p_reason: ev.text });
  if (!withinWindow(ev.at)) return { ok: true, outcome: 'handed_to_human:outside_window' };
  const text = clip(d.text, maxLen(ev.platform, ev.channel));
  const { data: out, error } = await admin.from('social_message').insert({
    conversation_id: conv.id, platform: ev.platform, channel: ev.channel, direction: 'out', author: 'seat',
    in_reply_to: m.id, body: text, reply_kind: 'handoff', reply_key: d.key, send_status: 'pending', occurred_at: new Date().toISOString(),
  }).select('id').single();
  if (error || !out) return { ok: false, error: error?.message ?? 'no reply row' };
  await send(ev, out.id as number, text);
  return { ok: true, outcome: 'handed_to_human' };
}

/** Send the grounded reply a held DM was owed, once its meaning is reasoned. Idempotent per message: a grounded
 *  reply already sent to it (standard / faq / knowledge / handoff) means nothing more goes. */
async function reasonedReply(platform: string, messageId: string, meaning: string, passages: CorpusRow[]): Promise<{ ok: boolean; error?: string; outcome?: string }> {
  const { data: m } = await admin.from('social_message').select('id,conversation_id,channel,body,occurred_at')
    .eq('platform', platform).eq('meta_message_id', messageId).eq('direction', 'in').maybeSingle();
  if (!m) return { ok: false, error: 'message_not_found' };
  const { data: already } = await admin.from('social_message').select('id').eq('in_reply_to', m.id)
    .in('reply_kind', ['standard', 'faq', 'knowledge', 'handoff']).limit(1);
  if (already && already.length) return { ok: true, outcome: 'already_answered' };
  const { data: conv } = await admin.from('social_conversation').select('id,platform,user_id,account_id,handle,status').eq('id', m.conversation_id).single();
  if (!conv) return { ok: false, error: 'conversation_not_found' };
  if (conv.status !== 'auto') return { ok: true, outcome: 'human_holds_conversation' };
  const [{ data: lib }, { data: faqs }] = await Promise.all([
    admin.from('social_reply_library').select('key,priority,match_words,reply_en,reply_ar,active').eq('active', true),
    admin.from('company_faq').select('id,question,answer,language').eq('public', true).eq('status', 'approved'),
  ]);
  const d = decide(String(m.body || ''), (lib || []) as LibraryRow[], (faqs || []) as FaqRow[], passages, false, meaning);
  if (d.kind === 'unknown') return { ok: true, outcome: 'reasoned:no_grounded_reply' };
  // Meta's own window decides whether a reply may still be sent (meta.ts).
  if (!withinWindow(new Date(m.occurred_at))) return { ok: true, outcome: 'outside_window' };
  const ev: InboundEvent = { platform: conv.platform, channel: m.channel, accountId: conv.account_id, userId: conv.user_id, handle: conv.handle,
    messageId, text: String(m.body || ''), at: new Date(m.occurred_at), parentId: null, echo: false, echoAppId: null, echoMetadata: null };
  const text = clip(d.text, maxLen(ev.platform, ev.channel));
  const { data: out, error } = await admin.from('social_message').insert({
    conversation_id: conv.id, platform: ev.platform, channel: ev.channel, direction: 'out', author: 'seat',
    in_reply_to: m.id, body: text, reply_kind: d.kind, reply_key: d.key, send_status: 'pending', occurred_at: new Date().toISOString(),
  }).select('id').single();
  if (error || !out) return { ok: false, error: error?.message ?? 'no reply row' };
  await send(ev, out.id as number, text);
  return { ok: true, outcome: 'answered:' + d.kind };
}

async function handle(ev: InboundEvent): Promise<string> {
  // A PUBLIC COMMENT follows the comment policy (instruction 866): classified, answered from fixed facts,
  // hidden when abusive, handed to the owning seat when it is a complaint, a dispute or a lead — no person
  // approves a reply (founder, 23 Sep 2026). DMs keep the conversation flow below.
  if (ev.channel === 'comment' && !ev.echo) {
    // Does this commenter want a person? REASONED (think()), never a phrase list; held, the comment is still
    // classified and answered from the policy, and the person check waits in the marketing queue.
    const person = await needsAPerson(defaultDeps(admin, 'marketing_social_inbox'), {
      seat: 'marketing', surface: 'marketing_social.comment_needs_a_person', message: ev.text.slice(0, 4000), audience: 'visitor',
      dedupeKey: 'social_comment:' + ev.platform + ':' + ev.messageId, subject: { platform: ev.platform, message_id: ev.messageId, user_id: ev.userId },
    });
    return await processComment(adminStore(admin, timedFetch, () => pageToken(ev), GATEWAY), {
      platform: ev.platform, accountId: ev.accountId, commentId: ev.messageId, authorId: ev.userId, handle: ev.handle,
      text: ev.text, at: ev.at, threadId: ev.parentId || ev.messageId }, person.value === true);
  }
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
    const token = isFixture(ev) ? null : await pageToken(ev);
    if (!conv.handle && token) await fillHandle(ev, conv.id, token);
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
  // HAVE WE ANSWERED A MESSAGE LIKE THIS BEFORE, AND HOW DID IT GO? (23 Sep 2026.) Recalled before
  // the decision, by meaning; the model path is told to stay consistent with a finalised reply.
  // Public surface: marketing's own social replies only, never another seat's cases.
  const memory = await recallCases(admin, { seat: 'marketing', path: 'social_reply', caseKind: 'social_reply', otherSeats: false, situation: ev.text });
  // Does this person want a person? REASONED (think(), founder_instruction 886-903), never a phrase list.
  // Held (the model hold, or a model that failed): the question is still ANSWERED now (903) from the library,
  // the FAQ and the knowledge; only the person check waits in the marketing seat's queue, and when it is
  // reasoned to need a person the handoff is sent on this platform (reasoned_handoff above, via
  // _shared/reasoned_delivery.ts). Nobody is paged on a guess, and nobody goes unanswered.
  const deps = defaultDeps(admin, 'marketing_social_inbox');
  const person = await needsAPerson(deps, {
    seat: 'marketing', surface: 'marketing_social.needs_a_person', message: ev.text.slice(0, 4000), audience: 'visitor',
    dedupeKey: 'social:' + ev.platform + ':' + ev.messageId, subject: { platform: ev.platform, message_id: ev.messageId, user_id: ev.userId },
  });
  // WHAT THEY ASK is reasoned once among every grounded reply (_shared/reasoned_channels.ts socialMeaning): a
  // standard library reply, the size statement, a cost/count/timeline FAQ, or one retrieved passage. Held, the
  // honest 'unknown' goes now (a gap recorded, a person offered) and the meaning waits in the marketing queue;
  // the replay sends the grounded reply on this platform (reasoned_reply above, via _shared/reasoned_delivery.ts).
  const passages = passagesFor(ev.text, corpus);
  const meaning = person.value === true ? null : (await socialMeaning(deps, {
    message: ev.text, library, passages, platform: ev.platform, messageId: ev.messageId, userId: ev.userId,
  })).value;
  const d = decide(ev.text, library, (faqs || []) as FaqRow[], passages, person.value === true, meaning);
  if (d.kind !== 'unknown' || !corpus.length || (await sec('social_model_enabled')) !== 'on') return d;

  // THE MODEL, SAME DOOR AS THE WEBSITE ASSISTANT (ai_gateway), and only over the passages retrieved
  // for this question. OFF until the founder lifts the OpenRouter hold; the honest 'unknown' stands.
  const key = await sec('cred_fn_ai');
  if (!key) return d;
  const sys = 'You are QuotesDone on ' + ev.platform + '. Answer ONLY from the KNOWLEDGE below, in the language of the message'
    + (d.lang === 'ar' ? ' (formal Gulf Arabic, formal plural)' : ' (UAE English)') + ', in under 80 words, plain text. '
    + 'Never state a price, fee, date, timeline or promise that is not written in the KNOWLEDGE. If the KNOWLEDGE does not answer it, reply exactly UNKNOWN.\n\nKNOWLEDGE:\n'
    + corpus.map((c) => c.content).join('\n\n')
    + (memory.cases.length ? precedentBlock(memory) + '\nNever mention another person, a case number or this block in the reply.' : '');
  try {
    const r = await timedFetch(GATEWAY, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
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
  if ((await sec('social_send_enabled')) !== 'on') { await set({ send_status: 'held_switch_off' }); return; }
  let token = await pageToken(ev);
  if (!token) { await set({ send_status: 'failed', send_error: 'no page we manage matches account ' + ev.accountId }); return; }
  try {
    const post = async (t: string) => {
      const { url, body } = sendRequest(ev, text, t);
      const r = await timedFetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      return { r, j: await r.json().catch(() => ({})) as any };
    };
    let { r, j } = await post(token);
    if (!r.ok && tokenExpired(j?.error) && (token = await pageToken(ev, true))) ({ r, j } = await post(token));
    // BEING THROTTLED IS NOT A FAILED REPLY (22 Sep 2026, it_engineer, CONN-07). Every non-2xx used to
    // become send_status='failed', which is terminal — nothing re-drains this table — so a Graph
    // rate-limit answer discarded a customer's answer for good. Meta's throttles are short: 613 is
    // calls-per-second, 4 is the app's hourly window, 17 is the user's. Two waits inside this same
    // handler clear the per-second one outright; if the hourly window is what we hit, the row is left
    // 'pending' with the reason rather than failed, so it is still owed and reads as owed.
    const live = token;   // narrowed: the refresh above may have set `token` back to null
    for (let attempt = 0; live && !r.ok && rateLimited(r.status, j?.error) && attempt < 2; attempt++) {
      await new Promise((ok) => setTimeout(ok, [1000, 4000][attempt]));
      ({ r, j } = await post(live));
    }
    if (r.ok) await set({ send_status: 'sent', sent_at: new Date().toISOString(), meta_message_id: j?.message_id || j?.id || null });
    else if (rateLimited(r.status, j?.error)) {
      await set({ send_status: 'pending', send_error: ('rate limited by Meta after 2 retries (' + String(j?.error?.code ?? r.status) + '): '
        + String(j?.error?.message || '').slice(0, 200) + ' — still owed, not failed').slice(0, 300) });
    }
    else await set({ send_status: 'failed', send_error: String(j?.error?.message || r.status).slice(0, 300) });
  } catch (e) { await set({ send_status: 'failed', send_error: String((e as Error)?.message || e).slice(0, 300) }); }
}

/** HTTP 429, or one of Graph's own throttle codes: 4 app-hourly, 17 user-hourly, 613 calls-per-second. */
export function rateLimited(status: number, err: unknown): boolean {
  if (status === 429) return true;
  const c = Number((err as { code?: unknown })?.code);
  return c === 4 || c === 17 || c === 613;
}

async function fillHandle(ev: InboundEvent, convId: number, token: string): Promise<void> {
  try {
    const r = await timedFetch('https://graph.facebook.com/v21.0/' + encodeURIComponent(ev.userId) + '?fields=name,username&access_token=' + encodeURIComponent(token));
    const j = await r.json();
    const h = j?.username || j?.name;
    if (r.ok && h) await admin.from('social_conversation').update({ handle: String(h).slice(0, 120) }).eq('id', convId);
  } catch (_e) { /* the founder is told the id instead */ }
}

// THE PAGE TOKEN, DERIVED — never a typed-in secret (metaPageToken in _shared/marketing_social_store.ts,
// shared with the marketing duty's comment sweep). Cached in marketing_meta_page; refetched on Graph 190.
const pageToken = (ev: InboundEvent, refresh = false) => metaPageToken(admin, timedFetch, ev.platform, ev.accountId, refresh);
