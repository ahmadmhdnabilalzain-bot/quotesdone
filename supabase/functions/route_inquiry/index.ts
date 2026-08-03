// route_inquiry - HYBRID RETRIEVAL (vector gte-small + keyword) narrows the whole supplier base to the most
// relevant approved candidates, then an LLM adjudicates who can GENUINELY quote the exact job. Safe
// fallback to a plain approved-pull if retrieval fails.
// COST: model choice + budget now belong to ai_gateway (prompt caching handled there).
// Completeness gate: an essentially-empty brief is not dispatched to suppliers (returns needs_detail).
//
// v9 STRUCTURED CAPABILITY MATCHING (decision_policy.use_capability_matching):
//   OFF (default) - behaviour is byte-for-byte the legacy path below. Nothing changes.
//   ON            - the inquiry is normalised into the controlled vocabulary (inquiry_parse), then
//                   fn_match_capability applies HARD GATES (trade intersection, role capability,
//                   declared exclusions, mandatory authority approvals, value band, supplier-confirmed
//                   scope) and a structured score. Only candidates at or above match_relevance_floor
//                   reach the LLM adjudicator, which still has the final say.
//   Zero gated candidates is a GENUINE coverage gap and is reported as such - we do NOT silently fall
//   back to keyword retrieval, because that is exactly how irrelevant inquiries reach suppliers.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'route_inquiry', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 28 Jul 2026 (missed by the 27 Jul sweep): sec() returns undefined/'' when the
// app_secrets read fails or the row is missing, and the guard below compared strictly, so a caller
// posting {} matched and gained full service-role authority on a function that requires no JWT. The
// stored secret must now be a real value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function policyRaw(k: string){ const { data } = await admin.from('decision_policy').select('value').eq('key', k).maybeSingle(); return (data as any)?.value; }
async function policyBool(k: string){ const v = await policyRaw(k); return v === true || String(v) === 'true'; }
async function policyNum(k: string, dflt: number){ const n = Number(await policyRaw(k)); return Number.isFinite(n) ? n : dflt; }
// Same shape as policyBool but ON unless explicitly switched off, so the taxonomy pre-filter below
// is live by default and can still be killed from decision_policy without a redeploy.
async function policyOn(k: string){ const v = await policyRaw(k); return !(v === false || String(v).toLowerCase() === 'false'); }
function parseJson(t: string){ let s=String(t||'').trim(); const f=s.match(/```(?:json)?\s*([\s\S]*?)```/i); if(f) s=f[1].trim(); try { return JSON.parse(s); } catch { const m = s.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; } }
function clip(s: unknown, n: number){ return String(s == null ? '' : s).slice(0, n); }

const SYS = `You are QuotesDone's expert job-routing dispatcher for the UAE building, fit-out, MEP and home-services market. A customer posted a job. You are given candidate suppliers with their REAL capabilities (from their own company profile / catalogue). Your task: decide which suppliers — if any — can GENUINELY fulfil and price this exact job. You protect suppliers from irrelevant inquiries, so a wrong match is worse than no match.

HARD RULES:
1. Judge by the supplier's ACTUAL scope of work, not by superficial word overlap. Example: a fire-pump manufacturer must NOT receive a "steel pipe fitting" or "plumbing" job just because the words 'steel'/'pipe' appear in their catalogue. A supplier of laptops must not get a 'kitchen cabinet' job, etc.
2. Classify the job as SINGLE-TRADE or MULTI-TRADE. Multi-trade = it spans several different trades/materials or is a combined/turnkey scope (e.g. 'new flooring + redo the washroom + some decoration', a full apartment renovation, a complete fit-out). For a MULTI-TRADE job, route to ONE supplier who can handle the whole scope — a fit-out / turnkey / interior-decoration / general-contracting company. Do NOT split a combined job across several single-trade suppliers.
3. For a SINGLE simple item, route to the one correct trade, judged by material and scope. (A wooden table → carpentry/joinery or fit-out. A steel + acrylic display stand → acrylic/fabrication or fit-out. A fire pump → a fire-fighting/fire-pump supplier only.)
4. Only mark a supplier 'fit' if you are genuinely confident they can quote this specific job. If unsure, mark 'no'. It is correct to return ZERO fits if none of the candidates truly match.
5. Prefer the most specialised genuine match. Avoid returning long lists; return only the suppliers that should actually receive the inquiry (typically 1-4).

Return STRICT JSON only:
{"job_type":"single"|"multi","primary_trade":string,"reasoning":string,"matches":[{"id":number,"verdict":"fit"|"no","reason":string}]}
Include every candidate id you were given in matches, each with a verdict. reasoning = 1-2 sentences on the routing decision.`;

const SUP_COLS = 'id,company_name,sector,emirate,service_emirates,products,services,capability_summary,rating';
function approvedFilter(q: any) { return q.or('registration_submitted_at.not.is.null,source.eq.self_registered').eq('approval_status', 'approved').eq('banned', false).eq('matching_blocked', false); }
function usable(c: any) { return c && (c.capability_summary || c.products || c.services); }

async function embed(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    const model = new (globalThis as any).Supabase.ai.Session('gte-small');
    const emb = await model.run(text.slice(0, 1500), { mean_pool: true, normalize: true }) as number[];
    if (Array.isArray(emb) && emb.length) return '[' + emb.join(',') + ']';
  } catch (_e) { /* */ }
  return null;
}

async function retrieve(jobText: string, inq: any, emirate: string, diag: any = {}): Promise<number[]> {
  const order: number[] = []; const seen = new Set<number>();
  const push = (id: any) => { const n = Number(id); if (n && !seen.has(n)) { seen.add(n); order.push(n); } };
  try {
    const vec = await embed(jobText);
    diag.embed_ok = vec ? 1 : 0;
    if (vec) { const { data, error } = await admin.rpc('match_suppliers', { query_embedding: vec, match_count: 60, p_emirate: emirate || null, p_role: null, p_product: null, p_min_rating: 0 }); if (error) diag.vector_rpc_error = clip(error.message, 160); diag.vector_hits = (data || []).length; for (const r of (data || [])) push((r as any).id); }
  } catch (_e) { diag.vector_exception = clip((_e as Error)?.message || _e, 160); }
  try {
    const kw = Array.isArray(inq.trades) ? inq.trades.map((t: any) => String(t)).filter(Boolean).slice(0, 16) : [];
    const multi = inq.scope_type === 'multi' || inq.scope_type === 'turnkey';
    const { data, error } = await admin.rpc('match_suppliers_kw', { p_keywords: kw.length ? kw : [String(inq.category || '')], p_category: inq.category || null, p_emirate: emirate || null, p_role: null, p_min_rating: 0, p_limit: 40, p_multi: multi });
    if (error) diag.kw_rpc_error = clip(error.message, 160); diag.kw_hits = (data || []).length;
    for (const r of (data || [])) push((r as any).id);
  } catch (_e) { diag.kw_exception = clip((_e as Error)?.message || _e, 160); }
  return order;
}

// TAXONOMY PRE-FILTER 28 Jul 2026 (decision_policy.use_taxonomy_prefilter, default ON).
// The canonical catalogue (catalog_domains -> catalog_subcategories) is bridged onto the trade agents
// that actually hold category knowledge by subcategory_agent_map (sub_slug -> agent_slug), and 16309
// of the 16394 suppliers classified in lead_subcategory (99.5%) reach an agent that exists. Routing
// referenced none of it, so the adjudicator paid for up to 60-80 blurbs that the taxonomy already
// knew were the wrong trade. This resolves the inquiry's DECLARED trade signal to a set of canonical
// subcategories and reports which of the already-retrieved candidates are classified into them.
// It is a narrowing/reordering pass over the ids hybrid retrieval returned: it never adds a
// candidate, never touches the approved-supplier filter, the fallback, or the adjudicator, and it
// leaves `ids` exactly as retrieved whenever the taxonomy resolves nothing or overlaps nothing.
// The free-form summary is deliberately NOT used as input - a wrong trade guess here would narrow
// the pool towards the wrong suppliers, which is the failure mode the whole function exists to avoid.
const _norm = (s: unknown) => String(s ?? '').trim().toLowerCase();
function tradeTokens(v: unknown): string[] {
  const n = _norm(v); if (!n) return [];
  return [n, n.replace(/[\s/]+/g, '-').replace(/[^a-z0-9_-]/g, ''), n.replace(/[\s-]+/g, '_')].filter(Boolean);
}
async function taxonomyPrefilter(ids: number[], inq: any, inquiryId: string, diag: any): Promise<Set<number>> {
  const hit = new Set<number>();
  try {
    const tokens = new Set<string>();
    for (const t of tradeTokens(inq.category)) tokens.add(t);
    if (Array.isArray(inq.trades)) for (const t of inq.trades.slice(0, 16)) for (const x of tradeTokens(t)) tokens.add(x);
    if (inquiryId) {
      // READ ONLY. inquiry_parse is never invoked from here - that LLM call belongs to the v9
      // capability gate; this pre-filter must stay cheap enough to be unconditional.
      const { data: rq } = await admin.from('inquiry_requirement').select('trades_required').eq('inquiry_id', inquiryId).maybeSingle();
      if (rq && Array.isArray((rq as any).trades_required)) for (const t of (rq as any).trades_required) for (const x of tradeTokens(t)) tokens.add(x);
    }
    if (!tokens.size) { diag.tax_prefilter = 'no_trade_signal'; return hit; }
    // taxonomy_trade (25 rows) and lead_trade_map (24 rows) are the controlled vocabulary and its
    // agent bridge - both tiny, so they are pulled whole and matched in memory.
    const [tradesRes, mapRes] = await Promise.all([
      admin.from('taxonomy_trade').select('code,aliases'),
      admin.from('lead_trade_map').select('trade_key,catalog_slug,confidence'),
    ]);
    if (tradesRes.error || mapRes.error) { diag.tax_error = clip(tradesRes.error?.message || mapRes.error?.message, 160); return hit; }
    const codes = new Set<string>();
    for (const t of (tradesRes.data || [])) {
      const code = _norm((t as any).code); if (!code) continue;
      if (tokens.has(code)) { codes.add(code); continue; }
      for (const a of ((t as any).aliases || [])) if (tokens.has(_norm(a))) { codes.add(code); break; }
    }
    // ONLY high-confidence trade->agent rows may narrow anything. The medium/low ones are explicit
    // best-effort fudges for trades that have no agent of their own - lead_trade_map sends
    // 'landscaping' to facilities-management-companies, whose subcategories are laundry, pest control
    // and mailroom services. Narrowing a swimming-pool RFQ towards those would be worse than not
    // using the taxonomy at all, so an inquiry that only resolves through a weak row resolves to
    // nothing here and takes the untouched legacy path.
    const agents = new Set<string>();
    for (const r of (mapRes.data || [])) { const a = (r as any).catalog_slug; if (a && _norm((r as any).confidence) === 'high' && codes.has(_norm((r as any).trade_key))) agents.add(String(a)); }
    // A category that is already an agent slug (e.g. 'electrical-suppliers') maps straight through;
    // tokens that are not agent slugs simply match nothing in the bridge.
    for (const t of tokens) agents.add(t);
    const { data: sam, error: samErr } = await admin.from('subcategory_agent_map').select('sub_slug,confidence').in('agent_slug', [...agents].slice(0, 120));
    if (samErr) { diag.tax_error = clip(samErr.message, 160); return hit; }
    // Same reasoning one level down: the 'low' bridge rows are the ones whose own note says the trade
    // has no agent and it was parked on the nearest neighbour. They must not pull candidates in.
    const subs = [...new Set((sam || []).filter((r: any) => _norm(r.confidence) !== 'low').map((r: any) => String(r.sub_slug)).filter(Boolean))];
    diag.tax_trades = [...codes].join('+') || null;
    diag.tax_subcats = subs.length;
    if (!subs.length) { diag.tax_prefilter = 'no_taxonomy_match'; return hit; }
    // Bounded by the ids retrieval already produced, so this is an indexed lookup of at most ~80
    // rows - never a scan of the 25k-row classification table.
    const { data: cls, error: clsErr } = await admin.from('lead_subcategory').select('lead_id').in('sub_slug', subs.slice(0, 200)).in('lead_id', ids);
    if (clsErr) { diag.tax_error = clip(clsErr.message, 160); return hit; }
    for (const r of (cls || [])) { const n = Number((r as any).lead_id); if (n) hit.add(n); }
  } catch (e) { diag.tax_exception = clip((e as Error)?.message || e, 160); }
  return hit;
}

// v9: structured capability retrieval. Returns null when the feature is off or unusable, so the
// caller falls through to the untouched legacy path.
async function capabilityRetrieve(inquiryId: string, secret: string, diag: any): Promise<any[] | null> {
  try {
    let { data: reqRow } = await admin.from('inquiry_requirement').select('*').eq('inquiry_id', inquiryId).maybeSingle();
    if (!reqRow) {
      try {
        await fetch('https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/inquiry_parse', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret, inquiry_id: inquiryId }) });
        ({ data: reqRow } = await admin.from('inquiry_requirement').select('*').eq('inquiry_id', inquiryId).maybeSingle());
      } catch (e) { diag.cap_parse_error = clip((e as Error)?.message || e, 160); }
    }
    if (!reqRow || !Array.isArray(reqRow.trades_required) || !reqRow.trades_required.length) {
      diag.cap_no_requirement = 1; return null;
    }
    diag.cap_trades = reqRow.trades_required.join('+');
    diag.cap_need = reqRow.role_required || 'executes';
    const { data: rows, error } = await admin.rpc('fn_match_capability', {
      p_trades: reqRow.trades_required,
      p_need: reqRow.role_required || 'executes',
      p_products: reqRow.products_norm || [],
      p_brands: reqRow.brands_specified || [],
      p_project_type: reqRow.project_type,
      p_value: reqRow.value_band,
      p_emirate: reqRow.emirate,
      p_limit: 12,
    });
    if (error) { diag.cap_rpc_error = clip(error.message, 160); return null; }
    const floor = await policyNum('match_relevance_floor', 35);
    const all = rows || [];
    const kept = all.filter((r: any) => Number(r.score) >= floor);
    diag.cap_gated = all.length; diag.cap_above_floor = kept.length; diag.cap_floor = floor;
    return kept;
  } catch (e) { diag.cap_exception = clip((e as Error)?.message || e, 160); return null; }
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const inbound = await sec('cred_fn_route_inquiry');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'route_inquiry');
    if (!__auth.ok) { await logRun('error', { forbidden: 1, fits: 0 }, 'route_inquiry rejected a caller with a missing/wrong inbound secret (403). No routing was performed — if this came from dispatch_inquiry, that RFQ silently produced zero supplier fits and will be miscounted as a supply coverage gap.'); return J({ error:'forbidden' }, 403); }

    let inq = body.inquiry || {};
    let inqLoadErr: any = null;
    if (body.inquiry_id) { const { data, error } = await admin.from('inquiries').select('category,summary,raw_input,spec,emirate,scope_type,trades,budget,boq').eq('id', body.inquiry_id).maybeSingle(); inqLoadErr = error || null; if (data) inq = data; if (error || !data) { await logRun('error', { inquiry_loaded: 0, fits: 0 }, 'route_inquiry could not load inquiry ' + clip(body.inquiry_id, 60) + ' (' + clip(error?.message || 'no row found', 120) + '). Routing will proceed on an empty/partial brief, so this RFQ will very likely yield zero supplier fits for a data-access reason rather than a genuine absence of suppliers.'); } }
    const emirate = clip(inq.emirate, 40);

    // --- Completeness gate: do not dispatch an essentially-empty brief to suppliers. ---
    const _desc = [inq.summary, inq.raw_input].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
    const _specKeys = (inq.spec && typeof inq.spec === 'object') ? Object.keys(inq.spec).filter((k) => !String(k).startsWith('_')).length : 0;
    const _boq: any = inq.boq || null;
    const _hasBoq = !!(_boq && (Array.isArray(_boq.boq) ? _boq.boq.length : (typeof _boq === 'object' ? Object.keys(_boq).length : 0)));
    const _hasTrades = Array.isArray(inq.trades) && inq.trades.length > 0;
    const _meaningful = _desc.replace(new RegExp(String(inq.category || '').replace(/[.*+?^${}()|[\]\\]/g, ''), 'ig'), '').replace(/[^a-z0-9؀-ۿ]/gi, '').length;
    if (!_hasBoq && !_hasTrades && _specKeys === 0 && _meaningful < 12) {
      await logRun(inqLoadErr ? 'error' : 'ok', { fits: 0, needs_detail: 1, zero_fits_genuine: inqLoadErr ? 0 : 1, meaningful_chars: _meaningful, spec_keys: _specKeys, inquiry_loaded: inqLoadErr ? 0 : 1 }, inqLoadErr ? 'RFQ produced no supplier fits because the inquiry row could not be read and the brief therefore looked empty to the completeness gate — this is a data failure, NOT a genuine incomplete brief, and it will be miscounted as the customer not supplying enough detail.' : 'RFQ stopped at the completeness gate: the brief is genuinely too thin to send to suppliers (needs_detail). No supplier was contacted; the customer must add detail or this request goes nowhere.');
      return J({ ok: true, job_type: null, fits: [], needs_detail: true, note: 'incomplete_brief', missing: ['a short description of the work', 'a rough quantity or size', 'the material or product type'] });
    }

    const jobText = [inq.summary && ('Summary: '+inq.summary), inq.raw_input && ('Customer wrote: '+inq.raw_input), inq.category && ('Stated category: '+inq.category), inq.budget && ('Budget: '+inq.budget), inq.spec && Object.keys(inq.spec||{}).length ? ('Details: '+JSON.stringify(inq.spec)) : '', inq.trades && inq.trades.length ? ('Trades hint: '+inq.trades.join(', ')) : '', emirate && ('Emirate: '+emirate)].filter(Boolean).join('\n');

    let pool: any[] = []; let retrieval = 'hybrid';
    const diag: any = {};
    let capScores: Record<number, any> = {};
    let taxIds = new Set<number>();

    // ---------- v9: structured capability path (opt-in) ----------
    const useCap = await policyBool('use_capability_matching');
    diag.use_capability_matching = useCap ? 1 : 0;
    let capRows: any[] | null = null;
    if (useCap && body.inquiry_id) {
      capRows = await capabilityRetrieve(String(body.inquiry_id), String(inbound), diag);
    }

    if (useCap && capRows) {
      retrieval = 'capability_gated';
      const ids = capRows.map((r: any) => Number(r.id ?? r.supplier_id)).filter(Boolean);
      for (const r of capRows) capScores[Number(r.id ?? r.supplier_id)] = r;
      if (ids.length) {
        const { data: rows, error: rowsErr } = await admin.from('leads').select(SUP_COLS).in('id', ids);
        if (rowsErr) diag.leads_fetch_error = clip(rowsErr.message, 160);
        const byId = new Map((rows || []).map((r: any) => [Number(r.id), r]));
        for (const id of ids) { const c = byId.get(id); if (c) pool.push(c); }
      }
      // Zero gated candidates is a GENUINE coverage gap. Falling back to keyword retrieval here would
      // reintroduce exactly the irrelevant-inquiry problem the gates exist to prevent.
      if (!pool.length) {
        await logRun('ok', { fits: 0, evaluated: 0, zero_fits_genuine: 1, retrieval, ...diag },
          'RFQ produced no supplier fits under structured capability matching: no supplier has a CONFIRMED capability record that passes the hard gates (trade, role, exclusions, authority, value band) for this job. This is a real coverage gap, not a retrieval failure - no supplier was contacted, which is the correct outcome.');
        return J({ ok: true, job_type: null, fits: [], note: 'no_capability_match', retrieval, gated: diag.cap_gated ?? 0 });
      }
    } else {
      // ---------- legacy path, untouched ----------
      let ids = await retrieve(jobText, inq, emirate, diag);
      // Taxonomy pre-filter: prefer the retrieved candidates that the canonical taxonomy already
      // classifies into this trade. Everything below - the leads fetch, the approved filter, the
      // under-8 fallback and the adjudicator - is unchanged and still sees a plain list of ids.
      if (ids.length && await policyOn('use_taxonomy_prefilter')) {
        taxIds = await taxonomyPrefilter(ids, inq, String(body.inquiry_id || ''), diag);
        const preferred = ids.filter((id) => taxIds.has(id));
        diag.tax_retrieved = ids.length; diag.tax_candidates = preferred.length;
        const taxMin = await policyNum('taxonomy_prefilter_min', 8);
        if (preferred.length >= taxMin) { ids = preferred; diag.tax_prefilter = 'narrowed'; }
        else if (preferred.length) { ids = [...preferred, ...ids.filter((id) => !taxIds.has(id))]; diag.tax_prefilter = 'preferred'; }
        else if (!diag.tax_prefilter) diag.tax_prefilter = 'no_overlap';
      } else if (!diag.tax_prefilter) diag.tax_prefilter = 'off';
      if (ids.length) {
        const { data: rows, error: rowsErr } = await admin.from('leads').select(SUP_COLS).in('id', ids.slice(0, 80));
        if (rowsErr) diag.leads_fetch_error = clip(rowsErr.message, 160);
        const byId = new Map((rows || []).map((r: any) => [Number(r.id), r]));
        for (const id of ids) { const c = byId.get(id); if (c && usable(c)) pool.push(c); if (pool.length >= 60) break; }
        const { data: appr, error: apprErr } = await approvedFilter(admin.from('leads').select('id').in('id', ids.slice(0, 80)));
        if (apprErr) diag.approval_filter_error = clip(apprErr.message, 160);
        const okIds = new Set((appr || []).map((r: any) => Number(r.id)));
        pool = pool.filter((c) => okIds.has(Number(c.id)));
      }
      if (pool.length < 8) {
        retrieval = pool.length ? 'hybrid+fallback' : 'fallback';
        const q = approvedFilter(admin.from('leads').select(SUP_COLS)).limit(60);
        const { data: cands, error: candsErr } = await q;
        if (candsErr) diag.fallback_query_error = clip(candsErr.message, 160);
        let extra = (cands || []).filter(usable);
        if (emirate) { const inEm = extra.filter((c:any)=> (Array.isArray(c.service_emirates) && c.service_emirates.some((e:string)=> String(e).toLowerCase()===emirate.toLowerCase())) || String(c.emirate||'').toLowerCase()===emirate.toLowerCase()); if (inEm.length >= 3) extra = inEm; }
        const have = new Set(pool.map((c) => Number(c.id)));
        for (const c of extra) { if (!have.has(Number(c.id))) { pool.push(c); have.add(Number(c.id)); } }
      }
    }

    pool = pool.slice(0, 40);
    // Make the pre-filter's effect measurable in the existing telemetry: agent_runs.counts gets the
    // split, and the retrieval label (which dispatch_inquiry copies into inquiries.routing) records
    // that the taxonomy shaped this pool at all. Composes with 'hybrid', 'hybrid+fallback', 'fallback'.
    if (diag.tax_prefilter === 'narrowed' || diag.tax_prefilter === 'preferred') {
      retrieval += '+taxonomy';
      const fromTax = pool.filter((c: any) => taxIds.has(Number(c.id))).length;
      diag.tax_pool_from_taxonomy = fromTax; diag.tax_pool_from_legacy = pool.length - fromTax;
    }
    const retrievalBroke = !!(diag.vector_rpc_error || diag.vector_exception || diag.kw_rpc_error || diag.kw_exception || diag.leads_fetch_error || diag.approval_filter_error || diag.fallback_query_error);
    if (!pool.length) { await logRun(retrievalBroke ? 'error' : 'ok', { fits: 0, evaluated: 0, zero_fits_genuine: retrievalBroke ? 0 : 1, retrieval, ...diag }, retrievalBroke ? ('RFQ produced no supplier fits because supplier retrieval itself failed (' + clip(diag.fallback_query_error || diag.approval_filter_error || diag.leads_fetch_error || diag.kw_rpc_error || diag.kw_exception || diag.vector_rpc_error || diag.vector_exception, 140) + '), not because no supplier exists — dispatch_inquiry will record this as a supply coverage gap and the customer will be told nobody serves them, which is false.') : 'RFQ produced no supplier fits and this is genuine: retrieval and the approved-supplier fallback both ran cleanly and the approved supplier base contains nobody usable for this job. This is a real supply coverage gap.'); return J({ ok:true, job_type:null, fits:[], note:'no_registered_suppliers', retrieval }); }

    const list = pool.map((c:any)=> {
      const cs = capScores[Number(c.id)];
      const capLine = cs ? `\n  [structured gate PASSED — score ${cs.score}: ${clip(cs.why, 200)}]` : '';
      return `#${c.id} — ${clip(c.company_name,80)} [sector: ${clip(c.sector||'-',40)}]${capLine}\n  Capability: ${clip(c.capability_summary || '', 600)}\n  Products: ${clip(c.products||'', 400)}\n  Services: ${clip(c.services||'', 300)}`;
    }).join('\n\n');
    const user = `JOB:\n${jobText}\n\nCANDIDATE SUPPLIERS (route only to those who can truly quote this job):\n${list}`;

    let ai:any = null;
    let aiLastErr: any = null;
    let aiAttempts = 0;
    for(let at=0; at<2 && !ai; at++){ try{ aiAttempts++; const r=await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway',{ method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: inbound, fn: 'route_inquiry', sys: SYS, input: user, max:1800, temperature:0.1 }) }); const jd=await r.json(); if(!r.ok) aiLastErr = 'http ' + r.status + ' ' + clip(jd?.error?.message || '', 120); const c=jd?.content; if(c){ const p=parseJson(c); if(p && Object.keys(p).length){ ai=p; break; } else if (r.ok) aiLastErr = 'unparseable model output'; } else if (r.ok) aiLastErr = 'empty model response'; }catch(_e){ aiLastErr = clip((_e as Error)?.message || _e, 140); } }
    if (!ai) { await logRun('error', { fits: 0, evaluated: pool.length, zero_fits_genuine: 0, ai_attempts: aiAttempts, ai_ok: 0, retrieval, ...diag }, 'RFQ produced no supplier fits because the adjudicator call failed after ' + aiAttempts + ' attempts (' + clip(aiLastErr || 'unknown', 120) + '), not because no supplier exists — ' + pool.length + ' viable candidates were never judged. Downstream this is indistinguishable from a supply coverage gap and the customer\'s RFQ silently goes nowhere.'); return J({ error:'ai_exception', detail:'no model returned parseable output' }, 502); }

    const byId = new Map(pool.map((c:any)=>[Number(c.id), c]));
    const matches = Array.isArray(ai.matches) ? ai.matches : [];
    const fits = matches.filter((m:any)=> String(m.verdict)==='fit' && byId.has(Number(m.id)))
      .map((m:any)=>({ id: Number(m.id), company_name: byId.get(Number(m.id)).company_name, reason: clip(m.reason,300),
                       score: capScores[Number(m.id)]?.score ?? null }));
    const verdictsSeen = matches.filter((m:any)=> byId.has(Number(m.id))).length;
    const zeroFitsGenuine = fits.length > 0 ? null : (verdictsSeen > 0 ? 1 : 0);
    await logRun((fits.length === 0 && zeroFitsGenuine === 0) ? 'error' : 'ok', { fits: fits.length, evaluated: pool.length, verdicts_returned: verdictsSeen, zero_fits_genuine: zeroFitsGenuine, ai_attempts: aiAttempts, ai_ok: 1, retrieval, retrieval_degraded: retrievalBroke ? 1 : 0, ...diag },
      fits.length > 0
        ? ('RFQ routed successfully to ' + fits.length + ' supplier fit(s) out of ' + pool.length + ' candidates adjudicated via ' + retrieval + '.' + (retrievalBroke ? ' NOTE: part of supplier retrieval errored, so the candidate pool was narrower than it should have been and a better-matching supplier may have been excluded.' : ''))
        : (zeroFitsGenuine === 1
            ? ('RFQ produced no supplier fits and this IS genuine: the adjudicator returned explicit verdicts on ' + verdictsSeen + ' of ' + pool.length + ' candidates and judged none capable of quoting this job. A real supply coverage gap.' + (retrievalBroke ? ' Caveat: retrieval partially errored, so the pool judged may have been incomplete.' : ''))
            : ('RFQ produced no supplier fits because the adjudicator returned NO usable verdicts for the ' + pool.length + ' candidates (malformed matches array), not because no supplier exists — this will be miscounted downstream as a supply coverage gap and the customer will be wrongly told nobody serves them.')));
    return J({ ok:true, job_type: ai.job_type || null, primary_trade: clip(ai.primary_trade,80), reasoning: clip(ai.reasoning,400), fits, evaluated: pool.length, retrieval });
  } catch (e) { await logRun('error', { unhandled_exception: 1, fits: 0, zero_fits_genuine: 0 }, 'route_inquiry threw an unhandled exception and returned 500: ' + clip((e as Error)?.message||e, 200) + ' — this RFQ produced no supplier fits for an internal reason, not because no supplier exists, and will be miscounted as a supply coverage gap.'); return J({ error: String((e as Error)?.message||e) }, 500); }
});
