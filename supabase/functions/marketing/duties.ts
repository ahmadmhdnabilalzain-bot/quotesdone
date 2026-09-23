// THE MARKETING SEAT'S DUTY LIST (post_results and scorecard since 23 Sep 2026, instruction 865): the 'duties' action runs every entry on every
// call (resilience_ping step 'marketing', every 30 minutes) before fn_marketing_tick.
//
// The builds that fill it (founder instruction 721, 22 Sep 2026):
//   * publishing / analytics / ad spend — schedule the approved posts through Postiz, read each channel's
//     analytics, and report each platform day of spend with fn_marketing_records_ad_spend (never book it);
//   * the social inbox — answer DMs from company knowledge (fn_marketing_assist) and hand a conversation to
//     the founder with fn_marketing_asks_the_founder_to_take_over the moment someone asks for a person.
//
// HOW TO ADD ONE. Append an entry. A duty decides its own due-ness (return { due: false } when it is not
// time) and returns counts. It throws only on a real failure: the runtime turns a throw into an IT finding
// owned by the marketing seat (fn_it_duty_settle 'marketing_duties'), closed on the first run it passes.
// The Meta and Postiz credentials may be read ONLY under supabase/functions/marketing/ (rule 641,
// scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs). Email and WhatsApp go through
// customer_support (_shared/deliver.ts); replies on the company's own social channels are this seat's.
import { timedFetch } from '../_shared/timed_fetch.ts';
import { call, linkedinTarget, processComment, unhideRequest, type CommentEvent, type Platform } from '../_shared/marketing_social_comments.ts';
import { adminStore, metaPageToken } from '../_shared/marketing_social_store.ts';
import { postizIntegrations, type PostizIntegration } from '../_shared/marketing_channels.ts';
import { wantsHuman } from '../marketing_social_inbox/reply.ts';

// deno-lint-ignore no-explicit-any
export type Admin = any;
export interface DutyContext {
  admin: Admin;
  sec: (key: string) => Promise<string | undefined>;
  now: Date;
}
export interface Duty {
  name: string;
  owner_seat: 'marketing';   // every duty names the seat that owns it
  run: (ctx: DutyContext) => Promise<Record<string, unknown>>;
}

// ── EACH PLATFORM ON ITS OWN ─────────────────────────────────────────────────────────────────────────
// One platform failing never stops the others. A credential failure (missing, expired, refused) SKIPS that
// platform and says so; any other failure is collected and thrown once every step has run, so it becomes the
// seat's IT finding without costing the other platforms their run.
const CREDENTIAL = /\b(401|403|190)\b|token|credential|unauthori[sz]ed|forbidden|expired|oauth|not connected|no .*key/i;
export async function isolated(steps: Record<string, () => Promise<unknown>>) {
  const out: Record<string, unknown> = {}; const skipped: string[] = []; const errors: string[] = [];
  for (const [name, step] of Object.entries(steps)) {
    try { out[name] = await step(); }
    catch (e) {
      const msg = String((e as Error)?.message || e).slice(0, 200);
      if (e instanceof Skip || CREDENTIAL.test(msg)) skipped.push(name + ': ' + msg); else errors.push(name + ': ' + msg);
    }
  }
  return { out, skipped, errors };
}
export class Skip extends Error {}

// SOCIAL COMMENTS (instruction 866; founder rulings of 23 Sep 2026). Instagram and Facebook comments arrive by
// Meta webhook at marketing_social_inbox; this duty
//   1. retries every Instagram/Facebook comment an earlier run left unfinished (no outcome after 10 minutes);
//   2. un-hides what a reviewing seat said was not abuse, and closes each social.* handoff the receiving seat
//      has answered (the originator closes: fn_marketing_social_handoffs_close);
//   3. YouTube: through the founder's Postiz YouTube connection only — skipped, and SAYS so, until it is there;
//   4. LinkedIn: the QuotesDone company page only (linkedinTarget) — a personal profile is refused.
// X is removed (founder, 23 Sep 2026: no paid X API).
export const socialComments: Duty = {
  name: 'social_comments',
  owner_seat: 'marketing',
  async run({ admin, sec, now }) {
    const gateway = Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway';
    const metaToken = (ev: { platform: Platform; accountId: string }) =>
      ev.platform === 'youtube' ? Promise.resolve(null) : metaPageToken(admin, timedFetch, ev.platform, ev.accountId);
    let postiz: PostizIntegration[] | null = null;
    const integrations = async () => {
      if (postiz) return postiz;
      const key = await sec('postiz_api_key');
      if (!key) throw new Skip('no postiz_api_key');
      const r = await postizIntegrations(timedFetch, (await sec('postiz_api_url')) || 'https://api.postiz.com/public/v1', key);
      if (r.error) throw new Error('postiz integrations HTTP ' + r.status + ': ' + r.error);
      return (postiz = r.list.filter((x) => !x.disabled && !x.refreshNeeded));
    };

    const { out, skipped, errors } = await isolated({
      async retry_unfinished() {
        const { data, error } = await admin.from('social_message')
          .select('meta_message_id,platform,body,parent_id,occurred_at,conversation:social_conversation(user_id,handle,account_id)')
          .eq('direction', 'in').eq('channel', 'comment').is('outcome', null)
          .lt('created_at', new Date(now.getTime() - 10 * 60_000).toISOString())
          .gt('created_at', new Date(now.getTime() - 24 * 3600_000).toISOString()).limit(50);
        if (error) throw new Error('unfinished comments: ' + error.message);
        const counts: Record<string, number> = {};
        for (const r of data || []) {
          const ev: CommentEvent = { platform: r.platform, accountId: r.conversation?.account_id, commentId: r.meta_message_id,
            authorId: r.conversation?.user_id, handle: r.conversation?.handle ?? null, text: r.body, at: new Date(r.occurred_at), threadId: r.parent_id || r.meta_message_id };
          const o = await processComment(adminStore(admin, timedFetch, metaToken, gateway), ev, wantsHuman(ev.text))
            .catch((e) => 'error:' + String(e?.message || e).slice(0, 60));
          counts[o] = (counts[o] || 0) + 1;
        }
        return counts;
      },
      async close_handoffs() {
        // A hide the reviewing seat reversed is un-hidden first; then every answered handoff is closed by us.
        const { data } = await admin.from('agent_actions').select('id,detail').eq('kind', 'handoff').eq('status', 'pending')
          .in('detail->>type', ['social.escalation', 'social.lead']).eq('detail->>unhide', 'true').is('detail->>unhidden_at', null).limit(50);
        let unhidden = 0;
        for (const h of data || []) {
          const d = h.detail || {};
          const ev = { platform: d.platform, accountId: d.account, commentId: d.comment } as CommentEvent;
          const t = await metaToken(ev);
          if (!t) continue;
          const r = await call(timedFetch, unhideRequest(ev, t));
          if (r.ok) { await admin.from('agent_actions').update({ detail: { ...d, unhidden_at: now.toISOString() } }).eq('id', h.id); unhidden++; }
        }
        const { data: closed, error } = await admin.rpc('fn_marketing_social_handoffs_close');
        if (error) throw new Error('fn_marketing_social_handoffs_close: ' + error.message);
        return { unhidden, closed };
      },
      async youtube() {
        const yt = (await integrations()).find((x) => x.identifier === 'youtube');
        if (!yt) throw new Skip('youtube not connected in Postiz');
        // Measured 23 Sep 2026 (docs.postiz.com/llms.txt): Postiz's public API has no comment read or reply and
        // hands out no platform token, and the founder ruled out our own Google OAuth keys. Nothing is read.
        throw new Skip('youtube connected in Postiz (' + yt.id + '), but Postiz exposes no comment endpoint or token');
      },
      async linkedin() {
        const ours = await sec('linkedin_company_page_integration_id');
        const page = (await integrations()).find((x) => linkedinTarget(x, ours));
        if (!page) throw new Skip('the company page named by linkedin_company_page_integration_id is not connected in Postiz (personal profiles are refused)');
        throw new Skip('linkedin company page connected, but Postiz exposes no comment endpoint');
      },
    });
    const counts = { ...out, skipped };
    if (errors.length) throw new Error(errors.join(' | ') + ' (the other steps ran: ' + JSON.stringify(counts).slice(0, 300) + ')');
    return counts;
  },
};

import { POST_RESULTS, SCORECARD } from './post_results.ts';

// A page's VISIBLE text, so a rotated script nonce or tracking tag is not a "change" — only the words are.
export function visibleText(html: string): string {
  return html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')
    // Google's help pages carry a fresh random 10+ digit token on every load; it is not a word of the page.
    .replace(/&[a-z#0-9]+;/gi, ' ').replace(/\b\d{10,}\b/g, ' ').replace(/\s+/g, ' ').trim();
}
async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// PLATFORM SPEC FRESHNESS (founder instruction 869, 23 Sep 2026). Every page marketing_platform_spec cites is re-read
// once a month, three per beat (the edge CPU cap). A changed page, or one that stops answering, is an IT finding owned
// by marketing (fn_marketing_platform_spec_freshness -> fn_it_duty_settle 'marketing_platform_spec_freshness') and it
// stays open until the rows are re-checked and fn_marketing_platform_spec_source_verified(url, who) is called.
const platformSpecFreshness: Duty = {
  name: 'platform_spec_freshness',
  owner_seat: 'marketing',
  run: async ({ admin }) => {
    const due = await admin.rpc('fn_marketing_platform_spec_sources_due', { p_limit: 3 });
    if (due.error) throw new Error('sources_due: ' + due.error.message);
    const urls = (due.data || []) as string[];
    let changed = 0;
    for (const url of urls) {
      let hash: string | null = null, status = 0, error: string | null = null;
      try {
        const r = await fetch(url, { headers: { 'User-Agent': 'QuotesDone-marketing-spec-check' }, signal: AbortSignal.timeout(12000) });
        status = r.status;
        if (r.ok) hash = await sha256(visibleText(await r.text()));
        else error = 'HTTP ' + r.status;
      } catch (e) { error = String((e as Error)?.message || e); }
      const seen = await admin.rpc('fn_marketing_platform_spec_source_seen', { p_url: url, p_hash: hash, p_status: status, p_error: error });
      if (seen.error) throw new Error('source_seen: ' + seen.error.message);
      if (seen.data?.changed) changed++;
    }
    const settled = await admin.rpc('fn_marketing_platform_spec_freshness');
    if (settled.error) throw new Error('freshness: ' + settled.error.message);
    return { due: urls.length > 0, read: urls.length, changed, open_findings: settled.data?.failing ?? null };
  },
};

// post_results: ties each published post to its platform ids and reads its results at +1d/+3d/+7d/+28d.
// scorecard:    fn_marketing_scorecard stored weekly (Monday, Asia/Dubai) and at month end (the 1st).
// platform_spec_freshness: the cited platform pages re-read monthly (above).
// social_comments: public comments read and answered on every synced channel (instruction 866, above).
export const DUTIES: Duty[] = [POST_RESULTS, SCORECARD, platformSpecFreshness, socialComments];
