// The database and network side of marketing_social_comments.ts (marketing, 23 Sep 2026): one Store bound to
// the service-role client, shared by the Meta webhook (marketing_social_inbox) and the marketing duty
// 'social_comments' (retry sweep, handoff close; YouTube via Postiz when connected — X removed 23 Sep 2026). Every comment read is a row in social_message (direction 'in', with
// its classification, outcome, who decided and any handoff); every reply is a row (direction 'out') with
// its send status. Kept forever, like every conversation (founder, 14 Sep).
import { decide, unknown, type CorpusRow, type LibraryRow } from '../marketing_social_inbox/reply.ts';
import type { FaqRow, Lang } from './chat_answers.ts';
import { pickPage, type PageAccount } from '../marketing_social_inbox/meta.ts';
import { call, hideRequest, replyRequest, type CommentEvent, type Fetch, type Store } from './marketing_social_comments.ts';
import { raiseSocialHandoff } from '../marketing/social_handoffs.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export function adminStore(admin: Admin, f: Fetch, tokenFor: (ev: CommentEvent) => Promise<string | null>, gateway: string): Store {
  const sec = async (k: string) => {
    const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
    return String(data?.value ?? '').trim() || undefined;
  };
  const inRows = new Map<number, { conv: number; platform: string }>();
  return {
    async insertInbound(ev, cls) {
      const conv: Record<string, unknown> = { platform: ev.platform, user_id: ev.authorId || ('anon:' + ev.commentId), account_id: ev.accountId, last_inbound_at: ev.at.toISOString() };
      if (ev.handle) conv.handle = ev.handle.slice(0, 120);
      const { data: c, error: ce } = await admin.from('social_conversation').upsert(conv, { onConflict: 'platform,user_id' }).select('id').single();
      if (ce || !c) throw new Error('conversation: ' + (ce?.message || 'no row'));
      const { data, error } = await admin.from('social_message').upsert({
        conversation_id: c.id, platform: ev.platform, channel: 'comment', direction: 'in', author: 'person',
        meta_message_id: ev.commentId, parent_id: ev.threadId, body: ev.text, occurred_at: ev.at.toISOString(), classification: cls,
      }, { onConflict: 'platform,meta_message_id', ignoreDuplicates: true }).select('id,conversation_id');
      if (error) throw new Error('message: ' + error.message);
      let row = data?.[0];
      if (!row) {
        // Already stored. Answered (outcome set) means done; no outcome means an earlier run failed before it
        // finished, so this delivery takes it over — a comment is never left unanswered for ever.
        const { data: old } = await admin.from('social_message').select('id,conversation_id,outcome')
          .eq('platform', ev.platform).eq('meta_message_id', ev.commentId).eq('direction', 'in').maybeSingle();
        if (!old || old.outcome != null) return null;
        row = old;
      }
      inRows.set(row.id, { conv: row.conversation_id, platform: ev.platform });
      return row.id as number;
    },
    async release(inId) {
      // Nothing was sent: the row is removed so the next delivery (or the duty's sweep) processes it afresh.
      await admin.from('social_message').delete().eq('id', inId).is('outcome', null);
    },
    async threadAllowed(ev) {
      try { const { data, error } = await admin.rpc('rl_check', { p_key: 'social_thread:' + ev.platform + ':' + ev.threadId, p_limit: 3, p_seconds: 600 }); return error ? false : data !== false; }
      catch (_e) { return false; }   // unsure means no: a loop is worse than a late reply
    },
    async record(inId, o) {
      await admin.from('social_message').update({ outcome: o.outcome, classification: o.classification, decided_by: o.decided_by,
        guard_failures: o.guard_failures, handoff_id: o.handoff_id, send_status: o.reply ? null : o.send_status, send_error: o.reply ? null : (o.send_error ?? null) }).eq('id', inId);
      if (!o.reply) return;
      const kind = o.decided_by === 'model' ? 'model' : o.handoff_id ? 'escalated' : 'standard';
      const at = inRows.get(inId);
      const { error } = await admin.from('social_message').insert({ conversation_id: at?.conv, platform: at?.platform, channel: 'comment', direction: 'out', author: 'seat',
        in_reply_to: inId, body: o.reply, reply_kind: kind, decided_by: o.decided_by, send_status: o.send_status, send_error: o.send_error ?? null,
        meta_message_id: o.platform_reply_id ?? null, sent_at: o.send_status === 'sent' ? new Date().toISOString() : null, occurred_at: new Date().toISOString(),
      });
      if (error) throw new Error('reply row: ' + error.message);
    },
    handoff: (type, ev, cls, extra) => raiseSocialHandoff(admin, type, ev, cls, extra),
    async switchOn(key) { return (await sec(key)) === 'on'; },
    async library(key, lang) {
      const { data } = await admin.from('social_reply_library').select('reply_en,reply_ar').eq('key', key).eq('active', true).maybeSingle();
      return String((lang === 'ar' ? data?.reply_ar : data?.reply_en) || '');
    },
    async deterministic(ev) {
      const [{ data: lib }, { data: faqs }] = await Promise.all([
        admin.from('social_reply_library').select('key,priority,match_words,reply_en,reply_ar,active').eq('active', true),
        admin.from('company_faq').select('id,question,answer,language').eq('public', true).eq('status', 'approved'),
      ]);
      let corpus: CorpusRow[] = [];
      try { corpus = ((await admin.rpc('fn_support_corpus_search', { p_query: ev.text, p_public: true, p_limit: 6 })).data || []) as CorpusRow[]; } catch (_e) { corpus = []; }
      // Only the comment_* rows: a DM row carries DM instructions ("reply 'agent'", the founder's mobile)
      // that must never be posted under a public post. FAQ and knowledge answers pass guard() in processComment.
      const library = ((lib || []) as LibraryRow[]).filter((r) => r.key.startsWith('comment_'));
      // false: whether this commenter wants a person was already REASONED by the caller (needsAPerson) and
      // reached processComment as wantsPerson; this call only picks the answer text.
      const d = decide(ev.text, library, (faqs || []) as FaqRow[], corpus, false);
      return d.kind === 'unknown' ? { ...unknown(library, d.lang), text: '' } : d;
    },
    async draft(ev, lang: Lang) {
      const key = await sec('cred_fn_ai');
      if (!key) return null;
      let corpus: CorpusRow[] = [];
      try { corpus = ((await admin.rpc('fn_support_corpus_search', { p_query: ev.text, p_public: true, p_limit: 6 })).data || []) as CorpusRow[]; } catch (_e) { return null; }
      if (!corpus.length) return null;
      const sys = 'You are QuotesDone replying publicly to a comment on ' + ev.platform + '. Answer ONLY from the KNOWLEDGE below, in '
        + (lang === 'ar' ? 'native formal Gulf Arabic (formal plural)' : 'UAE English') + ', in one or two short sentences, plain text, no hashtags. '
        + 'Never name or describe any customer or supplier, never quote a price, never promise, never give legal views. '
        + 'If the KNOWLEDGE does not answer it, reply exactly UNKNOWN.\n\nKNOWLEDGE:\n' + corpus.map((c) => c.content).join('\n\n');
      try {
        const r = await f(gateway, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
          __secret: key, fn: 'marketing_social_inbox', agent: 'marketing', task_class: 'marketing_copy', sys,
          input: [{ role: 'user', content: ev.text }], max: 300, temperature: 0.2, cache_ttl_min: 0, try_faq: false }) });
        const j = await r.json().catch(() => ({})) as any;
        return typeof j?.content === 'string' ? j.content.trim() : null;
      } catch (_e) { return null; }
    },
    async reply(ev, text) {
      const t = await tokenFor(ev);
      return t ? await call(f, replyRequest(ev, text, t)) : { ok: false, error: 'no credential for ' + ev.platform };
    },
    async hide(ev) {
      const t = await tokenFor(ev);
      return t ? await call(f, hideRequest(ev, t)) : { ok: false, error: 'no credential for ' + ev.platform };
    },
  };
}

// THE PAGE TOKEN, DERIVED — never a typed-in secret. me/accounts with the system-user token lists every page it
// manages with that page's own token and linked Instagram account; the one matching is cached in
// marketing_meta_page and refetched on refresh (Graph 190). Shared by the webhook and the marketing duty.
export async function metaPageToken(admin: Admin, f: Fetch, platform: 'facebook' | 'instagram', accountId: string, refresh = false): Promise<string | null> {
  if (!refresh) {
    const { data } = await admin.from('marketing_meta_page').select('page_token').eq(platform === 'facebook' ? 'page_id' : 'ig_id', accountId).maybeSingle();
    if (data?.page_token) return data.page_token as string;
  }
  const { data: k } = await admin.from('app_secrets').select('value').eq('key', 'meta_access_token').maybeSingle();
  const sys = String(k?.value ?? '').trim();
  if (!sys) return null;
  try {
    const r = await f('https://graph.facebook.com/v21.0/me/accounts?fields=id,name,access_token,instagram_business_account&limit=100&access_token=' + encodeURIComponent(sys));
    const j = await r.json();
    const page = pickPage((j?.data || []) as PageAccount[], platform, accountId);
    if (!r.ok || !page) return null;
    await admin.from('marketing_meta_page').upsert({ page_id: page.id, ig_id: page.instagram_business_account?.id ?? null,
      page_token: page.access_token, fetched_at: new Date().toISOString() }, { onConflict: 'page_id' });
    return page.access_token;
  } catch (_e) { return null; }
}
