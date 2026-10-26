// public_site — the deterministic, no-sign-in endpoints behind the public website.
//
// WHY THIS EXISTS (website audit 14 Sep 2026). The intelligence a visitor could reach before
// signing in was a canned animation and a chat bubble. The routines that make QuotesDone smart
// without a model already exist in SQL — the bilingual router (fn_kb_route_decide), the ordered
// interview (fn_category_questions), the per-trade compliance checklist, the matcher
// (fn_match_capability) and the published price bands (fn_price_guidance). This function puts them
// on the first screen. NO MODEL IS CALLED — every OpenRouter route is held and this path must work
// regardless.
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

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
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

// The same emirate words inquiry_intake recognises, in both languages. Returned as the canonical
// English name because that is what /me and the matcher store.
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

async function routeBrief(text: string, lang: 'en' | 'ar') {
  const emirate = detectEmirate(text);
  const { data: decision, error } = await admin.rpc('fn_kb_route_decide', { p_text: text.slice(0, 1000) });
  if (error) return { ok: false, error: 'router_unavailable' };
  const d: any = decision || {};
  const liveSlug = d?.candidates?.[0]?.live_slug || null;
  let category: string | null = null;
  if (d.catalog_num && liveSlug) {
    const { data: mapped } = await admin.rpc('fn_intake_slug_for_catalog', { p_catalog_slug: liveSlug });
    if (mapped) category = String(mapped);
  }
  if (!category) {
    return {
      ok: true, recognised: false, emirate,
      clarification: d.action === 'ask_clarifying_question' && d.clarification ? String(d.clarification) : null,
      candidates: (d.candidates || []).slice(0, 3).map((c: any) => String(c.live_name || '')).filter(Boolean),
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

async function priceGuidance(question: string) {
  const { data: pg, error } = await admin.rpc('fn_price_guidance', { p_question: question.slice(0, 300), p_limit: 6 });
  if (error || !pg) return { ok: false, reason: 'unavailable' };
  const p: any = pg;
  if (p.ok && Array.isArray(p.bands)) {
    // Only the band itself. The evidence text and the kb_chunk/blog source ids stay server-side.
    const bands = p.bands.slice(0, 4).map((b: any) => ({
      item: String(b.item || ''), low: Number(b.low), high: Number(b.high),
      unit: b.unit && b.unit !== 'none' ? String(b.unit) : null, as_of: b.as_of || null,
    })).filter((b: any) => Number.isFinite(b.low) || Number.isFinite(b.high));
    const asOf = bands.map((b: any) => b.as_of).filter(Boolean).sort().pop() || null;
    return { ok: true, trade: p.trade, bands, as_of: asOf, unmatched_terms: p.unmatched_terms || [] };
  }
  if (p.reason === 'trade_has_a_recorded_gap') return { ok: false, reason: 'gap', trade: p.trade || null };
  return { ok: false, reason: String(p.reason || 'no_match') };
}

Deno.serve(async (req) => {
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
      const r = await priceGuidance(`How much does ${String(b.topic)} cost per square metre in the UAE?`);
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
      return J(await routeBrief(text.slice(0, 1000), lang));
    }
    if (action === 'price_guidance') {
      const q = String(b.question || '').trim() || (b.topic ? `How much does ${String(b.topic).slice(0, 80)} cost per square metre in the UAE?` : '');
      if (q.length < 3) return J({ ok: false, error: 'empty' }, 400);
      return J(await priceGuidance(q));
    }
    return J({ ok: false, error: 'unknown_action' }, 400);
  } catch (_e) {
    return J({ ok: false, error: 'internal' }, 500);
  }
});
