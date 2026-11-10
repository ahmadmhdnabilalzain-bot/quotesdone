// Trend watch, the GEO audit and the brand reviews (split out of duties.ts, 9 Nov 2026; a pure move).
import { modelHeld } from '../../_shared/llm_hold.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { defaultDeps, think } from '../../_shared/think.ts';
import { competitorsNamed, modelCitation, parseRss } from '../../_shared/marketing_trends.ts';
import { marketingDeps } from './shared.ts';
import type { Duty } from './types.ts';

// ── TRENDS, GEO AND THE REVIEWS (marketing, 24 Sep 2026; ledger 983, GAPS.md "## Marketing" gaps 3, 5, 8) ───────
// scripts/sql/marketing_watches_trends_audits_answer_engines_and_reviews_the_brand_each_quarter.sql.
// Each bounds itself for the edge CPU cap: two feeds and ONE judgement per beat; two GEO checks per beat.

/** One trend's relevance, reasoned (surface marketing.trend_relevance). Held: null, and it is asked again next beat. */
export async function judgeTrend(deps: Parameters<typeof think>[0], t: { id: number; title: string; url: string; source: string }) {
  const r = await think(deps, {
    seat: 'marketing', surface: 'marketing.trend_relevance', queueWhenHeld: false, research: false,
    question: `A news item from "${t.source}": ${t.title} (${t.url}). Does it matter to QuotesDone, a UAE construction and fit-out procurement marketplace that is registering suppliers now and launches to customers in January 2027? If it does, say in one line what the marketing seat should do with it.`,
    context: { audience: 'internal' },
    decision: { name: 'trend_relevance', options: [
      { id: 'relevant', meaning: 'it changes what UAE buyers or suppliers of construction, fit-out, MEP or building materials need, fear or search for, or what a competitor offers; usable in content or positioning' },
      { id: 'not_relevant', meaning: 'nothing the company can act on' },
    ], fields: [{ key: 'why_it_matters', question: 'in one line, why it matters and what content or positioning it suggests' }] },
  });
  if (r.status !== 'answered' || !r.decision?.choice) return null;
  const why = (r.decision.fields?.why_it_matters?.value || r.answer || '').trim().slice(0, 300);
  // "Relevant" with no reason is not usable in a plan; recording it as not relevant (and saying why) ends the retry
  // instead of re-asking the model about the same headline every beat.
  if (r.decision.choice === 'relevant' && !why) return { relevant: false, why: 'judged relevant but no reason was given; not used', model: r.model ?? 'think' };
  return { relevant: r.decision.choice === 'relevant', why, model: r.model ?? 'think' };
}

export const trendWatch: Duty = {
  name: 'trend_watch',
  owner_seat: 'marketing',
  async run({ admin }) {
    const { data: srcs, error } = await admin.rpc('fn_marketing_trend_sources_due', { p_limit: 2 });
    if (error) throw new Error('fn_marketing_trend_sources_due: ' + error.message);
    let fresh = 0; const failed: string[] = [];
    for (const s of (srcs || []) as Array<{ id: number; name: string; feed_url: string }>) {
      let items: ReturnType<typeof parseRss> = [], err: string | null = null;
      try {
        const r = await timedFetch(s.feed_url, { headers: { 'User-Agent': 'QuotesDone-marketing-trends/1.0 (+https://www.quotesdone.ae)' } }, 12_000);
        if (r.ok) items = parseRss(await r.text()); else err = 'HTTP ' + r.status;
      } catch (e) { err = String((e as Error)?.message || e).slice(0, 200); }
      const seen = await admin.rpc('fn_marketing_trend_seen', { p_source_id: s.id, p_items: items, p_error: err });
      if (seen.error) throw new Error('fn_marketing_trend_seen: ' + seen.error.message);
      if (err) failed.push(s.name + ': ' + err); else fresh += Number(seen.data) || 0;
    }
    const { data: next } = await admin.rpc('fn_marketing_trend_next_to_judge');
    let judged: unknown = null;
    const t = (next || [])[0];
    if (t) {
      const j = await judgeTrend(defaultDeps(admin, 'marketing'), t);
      if (j) {
        const w = await admin.rpc('fn_marketing_trend_judged', { p_id: t.id, p_relevant: j.relevant, p_why: j.why, p_by: j.model });
        if (w.error) throw new Error('fn_marketing_trend_judged: ' + w.error.message);
        judged = { id: t.id, relevant: j.relevant };
      } else judged = { id: t.id, held: true };
    }
    // A feed that fails is recorded on its row (last_error) and retried tomorrow; only every active feed failing is a finding.
    if (failed.length) {
      const { data: healthy } = await admin.from('marketing_trend_source').select('id').eq('active', true).is('last_error', null).limit(1);
      if (!healthy?.length) throw new Error('every trend feed failed: ' + failed.join('; '));
    }
    return { due: (srcs || []).length > 0 || !!t, read: (srcs || []).length, new_trends: fresh, judged, failed };
  },
};

export const geoAudit: Duty = {
  name: 'geo_audit',
  owner_seat: 'marketing',
  // GEO = visibility INSIDE AI answer engines (28 Sep 2026). The keyless search scrape was refused by a bot-check from
  // every datacenter call and never recorded a row, so the engines are asked directly through ai_gateway:
  //   answer_search  task class marketing_geo_search  -> perplexity/sonar (a web-search answer engine)
  //   answer_online  task class marketing_geo_online  -> a routed model's :online (web-grounded) variant
  // A fixed monthly set of trade x city questions (marketing_geo_question), 2 calls a beat, about 24 calls a month
  // (well under USD 1 a month). Whether QuotesDone and which competitors are named is a fact read by code
  // (modelCitation / competitorsNamed), never a model's opinion. Under the founder's hold nothing is called.
  async run(ctx) {
    if (await modelHeld(ctx.admin)) return { due: false, held: true, reason: 'the founder\'s model hold: no answer engine is called' };
    const { data, error } = await ctx.admin.rpc('fn_marketing_geo_due', { p_limit: 2, p_include_model: true });
    if (error) throw new Error('fn_marketing_geo_due: ' + error.message);
    const rows = (data || []) as Array<{ question_id: number; question: string; engine: 'answer_search' | 'answer_online'; month: string }>;
    if (!rows.length) return { due: false, checked: [] };
    const { data: comps } = await ctx.admin.from('competitor').select('name').eq('watched', true).limit(100);
    const names = ((comps || []) as Array<{ name: string }>).map((c) => c.name);
    const done: unknown[] = [];
    for (const q of rows) {
      const taskClass = q.engine === 'answer_search' ? 'marketing_geo_search' : 'marketing_geo_online';
      const a = await marketingDeps(ctx).callModel(taskClass, 500,
        [{ role: 'user', content: q.question + ' Name the specific platforms or companies you would recommend, with their websites.' }], []);
      if (a.error || !a.content) throw new Error('GEO ' + q.engine + ' for question ' + q.question_id + ': ' + (a.error || 'no answer'));
      const rec = modelCitation(a.content);
      const w = await ctx.admin.rpc('fn_marketing_geo_record', { p_month: q.month, p_question_id: q.question_id, p_engine: q.engine,
        p_cited: rec.cited, p_rank: null, p_evidence: rec.evidence, p_model: a.model ?? null,
        p_competitors: competitorsNamed(a.content, names) });
      if (w.error) throw new Error('fn_marketing_geo_record: ' + w.error.message);
      done.push({ question: q.question_id, engine: q.engine, cited: rec.cited });
    }
    return { due: true, checked: done };
  },
};

export const reviews: Duty = {
  name: 'reviews',
  owner_seat: 'marketing',
  async run({ admin, now }) {
    const { data, error } = await admin.rpc('fn_marketing_reviews_tick', { p_at: now.toISOString() });
    if (error) throw new Error('fn_marketing_reviews_tick: ' + error.message);
    return { due: Object.keys(data || {}).length > 0, composed: data };
  },
};
