// The marketing seat's two measuring duties (marketing, 23 Sep 2026; founder instruction 865). Owner: marketing.
//   post_results  ties each published post to Postiz's post id and the platform's media id
//                 (marketing_post_platform), then reads every due checkpoint (+1d/+3d/+7d/+28d) into
//                 marketing_post_metric. READ-ONLY toward every platform. The calls and what each platform can
//                 and cannot give: ../_shared/marketing_post_results.ts.
//   scorecard     stores fn_marketing_scorecard weekly (Monday, Asia/Dubai: the month so far) and at month end
//                 (the 1st: the whole previous month) in marketing_scorecard_report. Plain SQL, no model.
import type { Duty, DutyContext } from './duties.ts';
import { metaPage } from '../_shared/marketing_channels.ts';
import {
  facebookPost, igMediaIdByPermalink, instagramMedia, postizIdsOf, postizReleases, viaPostiz,
  CHECKPOINTS, type Checkpoint, type Fetch, type GraphEnv, type MetricsResult, type Platform,
} from '../_shared/marketing_post_results.ts';

const POSTIZ_DEFAULT = 'https://api.postiz.com/public/v1';

async function graphEnv(ctx: DutyContext): Promise<GraphEnv | null> {
  const token = await ctx.sec('meta_access_token');
  if (!token) return null;
  const { data } = await ctx.admin.from('decision_policy').select('value').eq('key', 'marketing_meta_graph_version').maybeSingle();
  return { graph: 'https://graph.facebook.com/' + (data?.value ? String(data.value) : 'v21.0'), token };
}

export async function postResults(ctx: DutyContext, f: Fetch = fetch): Promise<Record<string, unknown>> {
  const { admin, now } = ctx;
  const postizKey = await ctx.sec('postiz_api_key');
  const postizBase = (await ctx.sec('postiz_api_url')) || POSTIZ_DEFAULT;
  const genv = await graphEnv(ctx);

  // 1. THE TIE, for published posts of the last 60 days that are not tied on every channel yet.
  const since = new Date(now.getTime() - 60 * 86400_000);
  const { data: pub, error: pErr } = await admin.from('marketing_post').select('id,channels,postiz_result,published_at')
    .eq('status', 'published').eq('is_demo', false).gte('published_at', since.toISOString());
  if (pErr) throw new Error('marketing_post unreadable: ' + pErr.message);
  const { data: tied } = await admin.from('marketing_post_platform').select('post_id,platform,platform_post_id').in('post_id', (pub || []).map((p: any) => p.id));
  const have = new Set((tied || []).filter((t: any) => t.platform_post_id).map((t: any) => t.post_id + ':' + t.platform));
  const untied = (pub || []).filter((p: any) => (p.channels || []).some((c: string) => !have.has(p.id + ':' + c)));
  let newlyTied = 0;
  let igUser: string | null = null;
  if (untied.length) {
    if (!postizKey) throw new Error('postiz_api_key is not in app_secrets: ' + untied.length + ' published post(s) cannot be tied to their platform ids');
    const releases = await postizReleases(f, postizBase, postizKey, since, new Date(now.getTime() + 86400_000));
    if (genv) igUser = (await metaPage(f, { ...genv, adAccountId: null, businessId: '' })).page?.ig?.id ?? null;
    for (const p of untied) {
      const ids = new Set(postizIdsOf(p.postiz_result));
      for (const r of releases.filter((x) => ids.has(x.postiz_post_id))) {
        let mediaId = r.platform_post_id;
        if (!mediaId && r.platform === 'instagram' && r.permalink && genv && igUser) mediaId = await igMediaIdByPermalink(f, genv, igUser, r.permalink);
        const { error } = await admin.from('marketing_post_platform').upsert(
          { post_id: p.id, platform: r.platform, postiz_post_id: r.postiz_post_id, platform_post_id: mediaId, permalink: r.permalink },
          { onConflict: 'post_id,platform' });
        if (error) throw new Error('marketing_post_platform: ' + error.message);
        newlyTied++;
      }
    }
  }

  // 2. THE CHECKPOINTS that are due.
  const { data: due, error: dErr } = await admin.rpc('fn_marketing_post_checkpoints_due', { p_limit: 25 });
  if (dErr) throw new Error('fn_marketing_post_checkpoints_due: ' + dErr.message);
  if (!due?.length) return { due: false, tied: newlyTied };
  let pageToken: string | null = null;
  if (genv && due.some((d: any) => d.platform === 'facebook')) {
    const pg = await metaPage(f, { ...genv, adAccountId: null, businessId: '' });
    if (pg.page) {
      const r = await f(`${genv.graph}/${pg.page.id}?fields=access_token&access_token=${encodeURIComponent(genv.token)}`);
      pageToken = (await r.json().catch(() => ({})))?.access_token ?? null;
    }
  }
  let written = 0;
  for (const d of due as Array<{ post_id: number; platform: Platform; platform_post_id: string | null; postiz_post_id: string | null; checkpoint: Checkpoint }>) {
    let res: MetricsResult;
    if (d.platform === 'instagram') {
      res = !genv ? { values: {}, unavailable: { '*': 'meta_access_token is not in app_secrets' } }
        : !d.platform_post_id ? { values: {}, unavailable: { '*': 'no Instagram media id tied to this post' } }
        : await instagramMedia(f, genv, d.platform_post_id);
    } else if (d.platform === 'facebook') {
      res = !genv || !pageToken ? { values: {}, unavailable: { '*': 'no Facebook page token (meta_access_token / ANALYZE task)' } }
        : !d.platform_post_id ? { values: {}, unavailable: { '*': 'no Facebook id tied to this post' } }
        : await facebookPost(f, genv, d.platform_post_id, pageToken);
    } else {
      res = !postizKey || !d.postiz_post_id ? { values: {}, unavailable: { '*': 'no Postiz key or Postiz post id' } }
        : await viaPostiz(f, postizBase, postizKey, d.postiz_post_id, CHECKPOINTS[d.checkpoint]);
    }
    const base = { post_id: d.post_id, platform: d.platform, platform_post_id: d.platform_post_id, checkpoint: d.checkpoint };
    const rows = [
      ...Object.entries(res.values).map(([metric, value]) => ({ ...base, metric, value, unavailable_reason: null })),
      ...Object.entries(res.unavailable).map(([metric, why]) => ({ ...base, metric, value: null, unavailable_reason: why })),
    ];
    if (!rows.length) rows.push({ ...base, metric: '*', value: null, unavailable_reason: 'the platform returned no metric' });
    const { error } = await admin.from('marketing_post_metric').upsert(rows, { onConflict: 'post_id,platform,checkpoint,metric', ignoreDuplicates: true });
    if (error) throw new Error('marketing_post_metric: ' + error.message);
    written += rows.length;
  }
  return { due: true, tied: newlyTied, checkpoints: due.length, rows: written };
}

/** The scorecards due at `now` (Asia/Dubai): Monday -> this week's, the 1st -> last month's month-end. */
export function scorecardPeriods(now: Date): Array<{ kind: 'weekly' | 'month_end'; period_key: string; month: string }> {
  const d = new Date(now.getTime() + 4 * 3600_000);           // Dubai wall clock, read with getUTC*
  const out: Array<{ kind: 'weekly' | 'month_end'; period_key: string; month: string }> = [];
  if (d.getUTCDay() === 1) {
    // ISO week number of the Dubai date
    const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 3));   // Thursday of this (Monday's) week
    const jan4 = new Date(Date.UTC(t.getUTCFullYear(), 0, 4));
    const week = 1 + Math.round(((t.getTime() - jan4.getTime()) / 86400_000 - 3 + ((jan4.getUTCDay() + 6) % 7)) / 7);
    out.push({ kind: 'weekly', period_key: `${t.getUTCFullYear()}-W${String(week).padStart(2, '0')}`, month: d.toISOString().slice(0, 7) });
  }
  if (d.getUTCDate() === 1) {
    const prev = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - 1, 1)).toISOString().slice(0, 7);
    out.push({ kind: 'month_end', period_key: prev + '-end', month: prev });
  }
  return out;
}

export async function scorecard(ctx: DutyContext): Promise<Record<string, unknown>> {
  const periods = scorecardPeriods(ctx.now);
  if (!periods.length) return { due: false };
  const stored: unknown[] = [];
  for (const p of periods) {
    const { data, error } = await ctx.admin.rpc('fn_marketing_scorecard_publish', { p_kind: p.kind, p_period_key: p.period_key, p_month: p.month });
    if (error) throw new Error('fn_marketing_scorecard_publish ' + p.period_key + ': ' + error.message);
    stored.push(data);
  }
  return { due: true, stored };
}

export const POST_RESULTS: Duty = { name: 'post_results', owner_seat: 'marketing', run: (ctx) => postResults(ctx) };
export const SCORECARD: Duty = { name: 'scorecard', owner_seat: 'marketing', run: scorecard };
