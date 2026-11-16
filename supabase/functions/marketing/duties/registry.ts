// The marketing duty list (split out of duties.ts, 9 Nov 2026; a pure move): every entry runs on every 'duties' call.
import { runStep, type Step } from '../../_shared/marketing_judgement.ts';
import { POST_RESULTS, SCORECARD } from '../post_results.ts';
import { graphBase, marketingDeps } from './shared.ts';
import { socialComments } from './social_comments.ts';
import { platformSpecFreshness } from './platform_spec_freshness.ts';
import { profileText } from './profile_text.ts';
import { geoAudit, reviews, trendWatch } from './trends_geo.ts';
import { blogArticle } from './blog_article.ts';
import { searchConsole } from './search_console.ts';
import type { Duty } from './types.ts';

// ── THE JUDGEMENT DUTIES (marketing, 23 Sep 2026; founder instructions 865, 866, 867) ─────────────────────────
// scripts/sql/the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql.
// Owner of every entry below: the marketing seat. Cadence: resilience_step 'marketing' (every 30 minutes); each
// duty bounds itself (fn_marketing_steps_due caps per day; at most 1 model step per beat, so the 55 s heartbeat call is never outrun; research weekly).
// While the founder's hold stands every model step records "held, not run" once a day and writes nothing else.

// post_results: ties each published post to its platform ids and reads its results at +1d/+3d/+7d/+28d.
// scorecard:    fn_marketing_scorecard stored weekly (Monday, Asia/Dubai) and at month end (the 1st).
// platform_spec_freshness: the cited platform pages re-read monthly (above).
// social_comments: public comments read and answered on every synced channel (instruction 866, above).
// PROFILE TEXT (instruction 920): once a day, every profile an API may write is made to equal profile_text.json.
// competitor_study, judgement, plan_loop: the judgement duties (instructions 865-867, above); profile_text (920).
export const DUTIES: Duty[] = [
  POST_RESULTS, SCORECARD, platformSpecFreshness, socialComments,
  {
    // Item 7, the fetch. SOURCE: Instagram Graph API business_discovery — official and free, and it returns a
    // competitor business account's ORGANIC posts (caption, type, permalink, time, likes, comments). The Meta Ad
    // Library API was rejected for this: outside the EU/UK it returns only political and issue ads, so it has
    // nothing on a UAE supplier's commercial or organic content, and the plan is organic only (866). Needs
    // meta_access_token and meta_ig_user_id (the company's own IG business account); until both are set the duty
    // says so and is not due. Weekly; competitors are the rows of public.competitor with social_handles.instagram.
    name: 'competitor_study',
    owner_seat: 'marketing',
    run: async (ctx) => {
      const token = await ctx.sec('meta_access_token');
      // the company's own IG business id: the secret, else the one the social inbox derived from the page (19 Oct 2026)
      const igUser = await ctx.sec('meta_ig_user_id') || ((await ctx.admin.from('marketing_meta_page').select('ig_id')
        .not('ig_id', 'is', null).limit(1).maybeSingle()).data?.ig_id as string | undefined);
      if (!token || !igUser) return { due: false, reason: 'meta_access_token and meta_ig_user_id are not both set' };
      const { data: last } = await ctx.admin.from('market_intel').select('fetched_at').eq('platform', 'instagram')
        .order('fetched_at', { ascending: false }).limit(1).maybeSingle();
      if (last?.fetched_at && ctx.now.getTime() - new Date(last.fetched_at).getTime() < 7 * 86400_000) return { due: false, reason: 'fetched this week' };
      // A DATED FAILURE MARKER: a fetch that failed today is not retried, and not raised again, until tomorrow.
      const today = new Date(ctx.now.getTime() + 4 * 3600_000).toISOString().slice(0, 10);   // Dubai day
      const { data: failedToday } = await ctx.admin.from('marketing_model_run').select('id').eq('step', 'competitor_fetch')
        .eq('outcome', 'failed').eq('run_day', today).limit(1);
      if (failedToday && failedToday.length) return { due: false, reason: 'the fetch failed today; next try tomorrow' };
      const base = await graphBase(ctx);
      const { data: comps } = await ctx.admin.from('competitor').select('id,name,social_handles').not('social_handles->>instagram', 'is', null).limit(25);
      const rows: Record<string, unknown>[] = []; const errors: string[] = [];
      for (const c of (comps || []) as Array<{ id: number; social_handles: Record<string, string> }>) {
        const handle = String(c.social_handles.instagram).replace(/^@/, '');
        const fields = `business_discovery.username(${handle}){media.limit(25){id,caption,media_type,permalink,timestamp,like_count,comments_count}}`;
        const r = await fetch(`${base}/${igUser}?fields=${encodeURIComponent(fields)}&access_token=${encodeURIComponent(token)}`,
          { signal: AbortSignal.timeout(15000) });
        // deno-lint-ignore no-explicit-any
        const j = await r.json().catch(() => null) as any;
        if (!r.ok) { errors.push(handle + ': ' + String(j?.error?.message || r.status).slice(0, 120)); continue; }
        for (const m of j?.business_discovery?.media?.data || []) {
          rows.push({ platform: 'instagram', source: 'business_discovery', external_id: m.id, competitor_id: c.id,
            source_url: m.permalink, posted_at: m.timestamp, caption: m.caption ?? null, media_type: m.media_type,
            metrics: { likes: m.like_count ?? null, comments: m.comments_count ?? null } });
        }
      }
      const { data, error } = await ctx.admin.rpc('fn_marketing_intel_upsert', { p_rows: rows });
      if (error) throw new Error('fn_marketing_intel_upsert: ' + error.message);
      if (errors.length && !rows.length) {
        // recorded once for the day, then raised once (the runtime turns this throw into marketing's IT finding)
        await ctx.admin.from('marketing_model_run').insert({ step: 'competitor_fetch', subject: today, seat: 'marketing',
          task_class: 'deterministic', outcome: 'failed', reason: ('every competitor fetch failed: ' + errors.join('; ')).slice(0, 1000), run_day: today });
        throw new Error('every competitor fetch failed: ' + errors.join('; '));
      }
      return { due: true, competitors: (comps || []).length, posts: rows.length, stored: data, errors };
    },
  },
  {
    // Items 6 (perception), 7 (synthesis), 8 (quality review), 9 (verdict, plan, defence): whatever is due, at
    // most 1 per beat. The CEO's review is never run here: it is a seat_deliberation (founder_instruction 873),
    // advanced by resilience_ping on another model family, and 'plan_loop' below reads its verdict back.
    name: 'judgement',
    owner_seat: 'marketing',
    run: async (ctx) => {
      const { data, error } = await ctx.admin.rpc('fn_marketing_steps_due', { p_at: ctx.now.toISOString() });
      if (error) throw new Error('fn_marketing_steps_due: ' + error.message);
      const due = (data || []) as Array<{ step: Step; subject: string }>;
      const ran = [];
      for (const d of due.slice(0, 1)) ran.push(await runStep(marketingDeps(ctx), 'marketing', d.step, d.subject));
      return { due: due.length, ran };
    },
  },
  {
    // Item 9, the author's side: send a waiting plan into the CEO's review (seat_deliberation), take each CEO
    // verdict back into marketing_plan_review_turn, close the deliberation once agreed, send the brief once.
    name: 'plan_loop',
    owner_seat: 'marketing',
    run: async (ctx) => {
      const { data, error } = await ctx.admin.rpc('fn_marketing_plan_loop_tick');
      if (error) throw new Error('fn_marketing_plan_loop_tick: ' + error.message);
      return data as Record<string, unknown>;
    },
  },
  profileText, trendWatch, geoAudit, reviews, blogArticle,
  // search_console (15 Nov 2026): Google Search Console, once a day, inert until its two secrets are set
  searchConsole,
];
