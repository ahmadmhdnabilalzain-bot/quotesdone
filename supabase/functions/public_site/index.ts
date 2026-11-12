// public_site — the deterministic, no-sign-in endpoints behind the public website.
//
// WHY THIS EXISTS (website audit 14 Sep 2026). The intelligence a visitor could reach before
// signing in was a canned animation and a chat bubble. The routines that make QuotesDone smart
// without a model already exist in SQL — the bilingual router (fn_kb_route_decide), the ordered
// interview (fn_category_questions), the per-trade compliance checklist, the matcher
// (fn_match_capability) and the published price bands (fn_price_guidance). This function puts them
// on the first screen. Which category a visitor's words ask for is REASONED (think(), 23 Sep 2026), and
// under the model hold the visitor is asked to describe the job. Which trade a price question asks about is
// reasoned too (founder_instruction 886-903); under the hold price_guidance answers reason 'held' rather than
// a band chosen by matching words. Everything else here calls no model.
//
// ACTIONS (POST {action, ...}):
//   counters        -> fn_public_site_counters(): aggregates, NULL below each floor.
//   route_brief     -> {text, lang}: recognised trade, the questions suppliers will need, required
//                      documents/authorities, and the matcher's count ONLY when > 0.
//   price_guidance  -> {question | topic, lang}: published UAE guide bands, or the recorded gap.
//   worked_case     -> fn_public_worked_case(): one real closed anonymised deal, or null.
//
// WHAT NEVER LEAVES. No supplier name, id, email or phone; no evidence snippet or kb_chunk id from
// the price table; no customer data. The matcher's rows are counted, never returned.
//
// ABUSE CONTROL. verify_jwt=false (a visitor has no session), so two ceilings are checked before
// any query, reusing rl_check and rl_hits exactly as site_assistant does: per caller IP
// (app_secrets.public_site_ip_hour, default 60) and a GLOBAL daily ceiling
// (public_site_global_day, default 5000) that does not trust the forgeable X-Forwarded-For.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { documentLine, isPageTopic } from './rules.ts';
import { defaultDeps } from '../_shared/think.ts';
import { priceGuidanceFor } from '../_shared/reasoned_suppliers.ts';
import { catalogueCategoryOf } from '../_shared/reasoned_matching.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
// GTE-SMALL RUNS IN embed_ml, NEVER IN THIS WORKER (it_engineer, 2 Nov 2026). Measured on production 1-2 Nov:
// 57 public_site POSTs in 24 h were killed at the 2 s edge CPU cap (function_logs "CPU Time exceeded", 546 after
// 1.0-2.4 s). A cold price_guidance embeds the question plus the 8 PRICE_EXEMPLARS in-process (9 gte-small runs at a
// median 324 ms CPU each, think.ts) and route_brief's think() embeds its steps the same way. Remote placement is
// the same model and space, one embed_ml worker per text, as the heartbeat already does (heartbeatDeps).
// prevented by: _shared/held_replay_keeps_gte_out_of_the_worker.test.ts (public_site case)
// A visitor is waiting on the page: 3 s per embedding, not 8; a timeout is the null path (no vector, no block).
// Written out at each call, so the decision-point guards (decision_points.json) still read the reasoned call itself.
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS, ...extra } });

async function secNum(k: string, dflt: number): Promise<number> {
  try {
    const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
    const n = Number(data?.value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : dflt;
  } catch (_e) { return dflt; }
}
async function rl(key: string, limit: number, seconds: number): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds });
    if (error) return true;
    return data !== false;
  } catch (_e) { return true; } // a limiter outage must not take the public site's answers offline
}

// The emirate words of the public site's own visitor preview, in both languages, returned as the canonical English name
// because that is what /me and the matcher store. Not inquiry_intake's: since 12 Nov 2026 (rulings 1664/1666) the request
// chat takes the emirate from the model and checks it against inquiry_intake/classify.ts emirateOf. This regex reading of a
// visitor's text is a known follow-up (LLM-first audit A1; it files nothing: preview count, demand signal, location skip).
const EMIRATES: [RegExp, string][] = [
  [/abu\s*dhabi|أبو\s*ظبي|ابوظبي|أبوظبي/i, 'Abu Dhabi'],
  [/dubai|دبي/i, 'Dubai'],
  [/sharjah|الشارقة|شارقة/i, 'Sharjah'],
  [/ajman|عجمان/i, 'Ajman'],
  [/ras\s*al\s*khaimah|\brak\b|رأس\s*الخيمة|راس\s*الخيمة/i, 'Ras Al Khaimah'],
  [/umm\s*al\s*quwain|أم\s*القيوين|ام\s*القيوين/i, 'Umm Al Quwain'],
  [/fujairah|الفجيرة/i, 'Fujairah'],
];
export function detectEmirate(t: string): string | null {
  for (const [re, name] of EMIRATES) if (re.test(t)) return name;
  return null;
}

// THE SAME QUESTION IS ANSWERED ONCE (it_engineer, 3 Nov 2026). Measured (ai_cost_log, 7 days): 809 public_site model calls
// on 73 distinct prompts, 0 cache hits. The prompt carries the price bands and catalogue it was answered from, so a changed
// band is a new prompt; an identical prompt is replayed for 6 hours by its exact hash, never by similarity (cacheExact).
const PUBLIC_MEMO_MIN = 360;

async function routeBrief(text: string, lang: 'en' | 'ar', ip = 'unknown') {
  const emirate = detectEmirate(text);
  // WHICH CATEGORY IS REASONED, NOT ALIAS-MATCHED (founder_instruction 886-903; decision point 24). The
  // router hands back the activated categories; think() reads the visitor's words over them
  // (reasoned_matching.ts catalogueCategoryOf) and the router is asked again with that category. Held: the
  // visitor is asked, in plain words, to describe the job — nothing is routed on a guess.
  const { data: open, error } = await admin.rpc('fn_kb_route_decide', { p_text: text.slice(0, 1000) });
  if (error) return { ok: false, error: 'router_unavailable' };
  const cats = ((open as any)?.candidates || []) as { catalog_num: number; live_name: string }[];
  // A visitor has no channel to be answered on later, so a held question is not queued: he is asked now.
  const pick = cats.length ? await catalogueCategoryOf(defaultDeps(admin, 'public_site', { gte: 'remote', embedTimeoutMs: 3000, cacheTtlMin: PUBLIC_MEMO_MIN }), { text, categories: cats, audience: 'visitor', queue: false }) : null;
  let d: any = open || {};
  if (pick?.value) {
    const { data: routed, error: re } = await admin.rpc('fn_kb_route_decide', { p_text: text.slice(0, 1000), p_catalog_num: pick.value });
    if (re) return { ok: false, error: 'router_unavailable' };
    d = routed || {};
  }
  const liveSlug = d?.candidates?.[0]?.live_slug || null;
  let category: string | null = null;
  if (d.catalog_num && liveSlug) {
    const { data: mapped } = await admin.rpc('fn_intake_slug_for_catalog', { p_catalog_slug: liveSlug });
    if (mapped) category = String(mapped);
  }
  // DEMAND SIGNAL (backlog T4, sales_engineer): a recognised trade is a visitor searching for it. Recorded as
  // trade + emirate only (no text), read by fn_demand_forecast_tick. Never blocks the answer.
  // At most 5 recorded searches per IP per day, so one visitor cannot inflate a trade's search count; searches
  // alone never start recruitment (fn_demand_forecast_tick acts on forecast inquiries only).
  if (category && await rl('demand_search_ip:' + ip, 5, 86400)) await admin.rpc('fn_demand_search_record', { p_category: category, p_emirate: emirate }).then(() => {}, () => {});
  if (!category) {
    return {
      ok: true, recognised: false, emirate,
      clarification: d.clarification ? String(d.clarification) : null,
      candidates: [],
    };
  }

  const [specRes, qRes] = await Promise.all([
    admin.from('category_specs').select('label, compliance_checklist, fields').eq('category', category).maybeSingle(),
    admin.rpc('fn_category_questions', { p_category: category, p_lang: lang, p_limit: 14 }),
  ]);
  const spec: any = specRes.data || {};
  // Measured live 14 Sep, "gypsum false ceiling, 120 sqm, Dubai": fn_category_questions answered with
  // the generic procurement frame ("What site, client, facility, user group or operating context
  // applies?") — true of every trade, useless to a visitor. category_specs.fields carries the trade's
  // own required questions in plain words, EN and AR (396/396 since
  // the_intake_asks_every_question_in_plain_words.sql), so those come first; the generic frame is the
  // fallback for a category with no plain questions. The location question is skipped when the visitor
  // already named an emirate — asking what they just said is the dumb-form behaviour.
  const isLocation = (k: string) => emirate !== null && /^(location|project-emirate|emirate)$/.test(k);
  const plain = (Array.isArray(spec.fields) ? spec.fields : [])
    .filter((f: any) => f && f.required && f[`question_plain_${lang}`] && !isLocation(String(f.key || '')))
    .map((f: any) => ({ key: String(f.key || ''), question: String(f[`question_plain_${lang}`]) }));
  const generic = ((qRes.data as any[]) || [])
    .filter((q) => q && q.question && q.mandatory && !isLocation(String(q.field_key || '')))
    .map((q) => ({ key: String(q.field_key || ''), question: String(q.question) }));
  const questions = (plain.length ? plain : generic).slice(0, 3);

  const cl = spec.compliance_checklist;
  const list = Array.isArray(cl?.list) ? cl.list : (Array.isArray(cl) ? cl : []);
  const documents = list.slice(0, 6).map((x: any) => documentLine(x, lang)).filter((x: any) => x.item);

  // Counted, never listed. Shown to the visitor only when the matcher found someone — "0 suppliers"
  // on the first screen would be a true number that teaches the wrong lesson, and the audit asked
  // for > 0 only.
  //
  // AND IT COUNTS A DIFFERENT THING FROM THE FAN-OUT (23 Sep 2026, SP-F-01). From that date an
  // inquiry carries the services it names and dispatch gates on them, so the number of suppliers who
  // will actually RECEIVE a particular brief is at most this one and usually smaller. This page has
  // no brief — the visitor has written nothing — so the count is honestly "suppliers registered for
  // this trade", and the page words it that way rather than as a promise about a future request. The
  // real fan-out is shown on the summary card at intake (inquiry_intake's supplier_count, which does
  // pass the services).
  // trade-level by design: no brief — the visitor has not written one yet.
  let supplierCount: number | null = null;
  try {
    const { data: cand } = await admin.rpc('fn_match_capability', {
      p_trades: [category], p_need: 'executes', p_products: [], p_brands: [],
      p_project_type: null, p_value: null, p_emirate: emirate, p_limit: 24,
    });
    const n = Array.isArray(cand) ? cand.length : 0;
    supplierCount = n > 0 ? n : null;
  } catch (_e) { supplierCount = null; }

  return {
    ok: true, recognised: true, category, label: String(spec.label || category), emirate,
    confidence: typeof d.confidence === 'number' ? d.confidence : null,
    questions, documents,
    documents_source: documents.length ? 'category_specs.compliance_checklist' : 'no checklist published for this category',
    supplier_count: supplierCount,
  };
}

// WHICH TRADE A QUESTION IS ABOUT, AND WHETHER IT ASKS A PRICE AT ALL, IS REASONED (think(),
// _shared/reasoned_suppliers.ts priceGuidanceFor; founder_instruction 886-903) — fn_price_guidance no
// longer reads the question. Held (the model hold): no band is offered on a guess; reason 'held'.
async function priceGuidance(question: string, ip: string) {
  const p: any = await priceGuidanceFor(defaultDeps(admin, 'public_site', { gte: 'remote', embedTimeoutMs: 3000, cacheTtlMin: PUBLIC_MEMO_MIN }), question.slice(0, 300), 6, 'visitor', 'ip:' + ip);
  if (p.ok && Array.isArray(p.bands)) {
    // Only the band itself. The evidence text and the kb_chunk/blog source ids stay server-side.
    const bands = p.bands.slice(0, 4).map((b: any) => ({
      item: String(b.item || ''), low: Number(b.low), high: Number(b.high),
      unit: b.unit && b.unit !== 'none' ? String(b.unit) : null, as_of: b.as_of || null,
    })).filter((b: any) => Number.isFinite(b.low) || Number.isFinite(b.high));
    const asOf = bands.map((b: any) => b.as_of).filter(Boolean).sort().pop() || null;
    // unmatched_terms stays empty: whether a band is for the item asked is not decided by matching its words.
    return { ok: true, trade: p.trade, bands, as_of: asOf, asked_item: p.asked_item ?? null, unmatched_terms: [] };
  }
  if (p.reason === 'trade_has_a_recorded_gap') return { ok: false, reason: 'gap', trade: p.trade || null };
  return { ok: false, reason: String(p.reason || 'no_match') };
}

// Any throw outside the per-action try blocks (the counters, worked_case and trade_needs reads) still
// answers WITH the CORS headers; without them the browser reports a plain 500 as a CORS failure.
// (A 546 CPU kill or a gateway 502 never reaches this code: those are met by the client retry.)
Deno.serve(async (req) => {
  try { return await handle(req); } catch (_e) { return J({ ok: false, error: 'internal' }, 500); }
});

async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return J({ error: 'method' }, 405);
  const b = await req.json().catch(() => ({} as any));
  const action = String(b.action || '');
  const lang: 'en' | 'ar' = String(b.lang || '').toLowerCase().startsWith('ar') ? 'ar' : 'en';

  // trade_needs {category, lang}: the published requirements of ONE trade, for /services/[slug].
  // Measured 14 Sep: service pages asked route_brief with a trade name and 10 of 24 trades did not
  // route, and a site build (one call per page per locale) spent most of the 60/hour IP budget. The
  // service page already knows its trade, so it names the category and skips the router; the answer
  // is static published data, cached by the CDN for a day, and is served before the visitor limiter.
  if (action === 'trade_needs') {
    const category = String(b.category || '');
    if (!/^[a-z][a-z-]{1,59}$/.test(category)) return J({ ok: false, error: 'bad_category' }, 400);
    const { data: spec } = await admin.from('category_specs').select('label, compliance_checklist, fields').eq('category', category).maybeSingle();
    if (!spec) return J({ ok: false, error: 'unknown_category' }, 404);
    const s: any = spec;
    const questions = (Array.isArray(s.fields) ? s.fields : [])
      .filter((f: any) => f && f.required && f[`question_plain_${lang}`])
      .slice(0, 6)
      .map((f: any) => ({ key: String(f.key || f[`question_plain_${lang}`]), question: String(f[`question_plain_${lang}`]) }));
    const cl = s.compliance_checklist;
    const list = Array.isArray(cl?.list) ? cl.list : (Array.isArray(cl) ? cl : []);
    const documents = list.slice(0, 6).map((x: any) => documentLine(x, lang)).filter((x: any) => x.item);
    return J({ ok: true, category, label: String(s.label || category), questions, documents }, 200,
      { 'Cache-Control': 'public, max-age=3600, s-maxage=86400' });
  }

  // PAGE-LOAD READS, SERVED BEFORE THE VISITOR LIMITER (14 Sep 2026). Measured on the live site after
  // the Sealed release: every Lighthouse run logged "Failed to load resource: 429" and lost
  // best-practices to it — the homepage asks for `counters` on load, how-it-works for `worked_case`,
  // the refund page for `guarantee_terms`, and a visitor who reloads a few pages exhausts the
  // 60/hour IP budget meant for the brief box. These three are aggregate or published, non-identifying
  // reads with CDN cache headers, so they sit beside trade_needs; route_brief and price_guidance —
  // the ones a script could hammer with free text — stay behind the limiter.
  if (action === 'counters') {
    const { data, error } = await admin.rpc('fn_public_site_counters');
    if (error) return J({ ok: false, error: 'counters_unavailable' });
    return J({ ok: true, ...(data as any) }, 200, { 'Cache-Control': 'public, max-age=300, s-maxage=300' });
  }
  if (action === 'worked_case') {
    const { data, error } = await admin.rpc('fn_public_worked_case');
    if (error) return J({ ok: false, error: 'unavailable' });
    return J({ ok: true, case: data ?? null }, 200, { 'Cache-Control': 'public, max-age=600, s-maxage=600' });
  }
  // The Reveal Guarantee ladder for the refund policy page (website audit W4, 14 Sep 2026), from the
  // same pricing_config row the refund sweep and the customer portal read. Days only; no money.
  if (action === 'guarantee_terms') {
    const { data, error } = await admin.from('pricing_config')
      .select('refund_window_working_days,chase_after_working_days,bank_settlement_working_days_min,bank_settlement_working_days_max')
      .eq('id', 1).maybeSingle();
    if (error || !data) return J({ ok: false, error: 'unavailable' });
    const d = data as Record<string, number | null>;
    return J({ ok: true, terms: { window_days: d.refund_window_working_days ?? null, chase_after_days: d.chase_after_working_days ?? null,
      bank_min_days: d.bank_settlement_working_days_min ?? null, bank_max_days: d.bank_settlement_working_days_max ?? null } },
      200, { 'Cache-Control': 'public, max-age=600, s-maxage=600' });
  }

  // A service page's own price question (./rules.ts PAGE_TOPICS, measured 22 Sep 2026: 116 of 472
  // crawled loads answered 429). Published bands for a fixed topic, so it skips the 60/hour visitor
  // limiter, but keeps a ceiling of its own: 600/hour per IP (app_secrets.public_site_page_ip_hour) is
  // ten full crawls of every service page in both languages, and still stops a loop hammering them.
  if (action === 'price_guidance' && isPageTopic(b)) {
    const pip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
    if (!(await rl('public_site_page_ip:' + pip, await secNum('public_site_page_ip_hour', 600), 3600))) return J({ ok: false, rate_limited: true }, 429);
    try {
      const r = await priceGuidance(`How much does ${String(b.topic)} cost per square metre in the UAE?`, pip);
      return J(r, 200, { 'Cache-Control': 'public, max-age=3600, s-maxage=86400' });
    } catch (_e) { return J({ ok: false, error: 'internal' }, 500); }
  }

  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
  const [ipLimit, dayLimit] = await Promise.all([
    secNum('public_site_ip_hour', 60), secNum('public_site_global_day', 5000),
  ]);
  const ipOk = await rl('public_site_ip:' + ip, ipLimit, 3600);
  const dayOk = ipOk ? await rl('public_site_global_day', dayLimit, 86400) : true;
  if (!ipOk || !dayOk) return J({ ok: false, rate_limited: true }, 429);

  try {
    if (action === 'route_brief') {
      const text = String(b.text || '').trim();
      if (text.length < 3) return J({ ok: false, error: 'empty' }, 400);
      return J(await routeBrief(text.slice(0, 1000), lang, ip));
    }
    if (action === 'price_guidance') {
      const q = String(b.question || '').trim() || (b.topic ? `How much does ${String(b.topic).slice(0, 80)} cost per square metre in the UAE?` : '');
      if (q.length < 3) return J({ ok: false, error: 'empty' }, 400);
      return J(await priceGuidance(q, ip));
    }
    return J({ ok: false, error: 'unknown_action' }, 400);
  } catch (_e) {
    return J({ ok: false, error: 'internal' }, 500);
  }
}
