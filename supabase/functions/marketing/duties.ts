// THE MARKETING SEAT'S DUTY LIST: the 'duties' action runs every entry on every call (resilience_ping step
// 'marketing', every 30 minutes) before fn_marketing_tick. Owner of every entry: the marketing seat.
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
import { makeLlmRich } from '../_shared/llm.ts';
import { modelHeld } from '../_shared/llm_hold.ts';
import { type Deps, runStep, type Step } from '../_shared/marketing_judgement.ts';

// deno-lint-ignore no-explicit-any
export type Admin = any;
export interface DutyContext {
  admin: Admin;
  sec: (key: string) => Promise<string | undefined>;
  now: Date;
}
export interface Duty {
  name: string;
  run: (ctx: DutyContext) => Promise<Record<string, unknown>>;
}

// ── THE JUDGEMENT DUTIES (marketing, 23 Sep 2026; founder instructions 865, 866, 867) ─────────────────────────
// scripts/sql/the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql.
// Owner of every entry below: the marketing seat. Cadence: resilience_step 'marketing' (every 30 minutes); each
// duty bounds itself (fn_marketing_steps_due caps per day; at most 1 model step per beat, so the 55 s heartbeat call is never outrun; research weekly).
// While the founder's hold stands every model step records "held, not run" once a day and writes nothing else.

const IG_GRAPH = 'https://graph.facebook.com/v21.0';

/** The seat's model client: its own class per step, charged to the marketing ceiling. */
function marketingDeps(ctx: DutyContext): Deps {
  return {
    admin: ctx.admin,
    held: () => modelHeld(ctx.admin),
    callModel: async (taskClass, max, messages, requireCaps) => {
      const llm = makeLlmRich(undefined, { fn: 'marketing', taskClass, dept: 'marketing', agent: 'marketing', max, timeoutMs: 45000, temperature: 0.2 });
      const r = await llm('', '', max, '', { messages, requireCaps });
      return { content: r.content, error: r.error, truncated: r.truncated, model: r.model ?? null };
    },
    download: async (bucket, path) => {
      const { data, error } = await ctx.admin.storage.from(bucket).download(path);
      if (error || !data) throw new Error('download ' + path + ': ' + (error?.message || 'nothing'));
      return new Uint8Array(await data.arrayBuffer());
    },
    signedUrl: async (bucket, path) => {
      const { data } = await ctx.admin.storage.from(bucket).createSignedUrl(path, 3600);
      return data?.signedUrl ?? null;
    },
  };
}

export const DUTIES: Duty[] = [
  {
    // Item 7, the fetch. SOURCE: Instagram Graph API business_discovery — official and free, and it returns a
    // competitor business account's ORGANIC posts (caption, type, permalink, time, likes, comments). The Meta Ad
    // Library API was rejected for this: outside the EU/UK it returns only political and issue ads, so it has
    // nothing on a UAE supplier's commercial or organic content, and the plan is organic only (866). Needs
    // meta_access_token and meta_ig_user_id (the company's own IG business account); until both are set the duty
    // says so and is not due. Weekly; competitors are the rows of public.competitor with social_handles.instagram.
    name: 'competitor_study',
    run: async (ctx) => {
      const token = await ctx.sec('meta_access_token');
      const igUser = await ctx.sec('meta_ig_user_id');
      if (!token || !igUser) return { due: false, reason: 'meta_access_token and meta_ig_user_id are not both set' };
      const { data: last } = await ctx.admin.from('market_intel').select('fetched_at').eq('platform', 'instagram')
        .order('fetched_at', { ascending: false }).limit(1).maybeSingle();
      if (last?.fetched_at && ctx.now.getTime() - new Date(last.fetched_at).getTime() < 7 * 86400_000) return { due: false, reason: 'fetched this week' };
      const { data: comps } = await ctx.admin.from('competitor').select('id,name,social_handles').not('social_handles->>instagram', 'is', null).limit(25);
      const rows: Record<string, unknown>[] = []; const errors: string[] = [];
      for (const c of (comps || []) as Array<{ id: number; social_handles: Record<string, string> }>) {
        const handle = String(c.social_handles.instagram).replace(/^@/, '');
        const fields = `business_discovery.username(${handle}){media.limit(25){id,caption,media_type,permalink,timestamp,like_count,comments_count}}`;
        const r = await fetch(`${IG_GRAPH}/${igUser}?fields=${encodeURIComponent(fields)}&access_token=${encodeURIComponent(token)}`,
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
      if (errors.length && !rows.length) throw new Error('every competitor fetch failed: ' + errors.join('; '));
      return { due: true, competitors: (comps || []).length, posts: rows.length, stored: data, errors };
    },
  },
  {
    // Items 6 (perception), 7 (synthesis), 8 (quality review), 9 (verdict, plan, defence): whatever is due, at
    // most 1 per beat. The CEO's turn is never run here — it is the CEO's, in ceo_agent; this only reports it due
    // so resilience_ping hands it to the CEO's own function.
    name: 'judgement',
    run: async (ctx) => {
      const { data, error } = await ctx.admin.rpc('fn_marketing_steps_due', { p_at: ctx.now.toISOString() });
      if (error) throw new Error('fn_marketing_steps_due: ' + error.message);
      const due = (data || []) as Array<{ step: Step; subject: string; seat: string }>;
      const deps = marketingDeps(ctx);
      const ran = [];
      for (const d of due.filter((x) => x.seat === 'marketing').slice(0, 1)) ran.push(await runStep(deps, 'marketing', d.step, d.subject));
      const ceo = due.find((d) => d.seat === 'ceo');
      return { due: due.length, ran, ceo_turn_due: ceo ? ceo.subject : null };
    },
  },
  {
    // Item 9, the originator's side: close an agreed review with the CEO and send the brief to the founder once.
    name: 'plan_loop',
    run: async (ctx) => {
      const { data, error } = await ctx.admin.rpc('fn_marketing_plan_loop_tick');
      if (error) throw new Error('fn_marketing_plan_loop_tick: ' + error.message);
      return data as Record<string, unknown>;
    },
  },
];
