// quote_compare v21 — adjudicates EVERY live quote with the supplier's own priced line
// items, our completeness check, expiry, source, anonymous track record, AND (new in v21)
// QuotesDone's own curated per-category EXPERT REFERENCE: UAE market price ranges + red
// flags, spec hierarchy, and what a complete quote must itemise — so the agent sanity-checks
// prices against the market and ranks technical quality authoritatively for any trade.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'quote_compare', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const DISCLAIMER_EN = "This is QuotesDone's impartial recommendation, prepared to make your decision easier. From all the quotes you received, we have shortlisted the three that best match your job on specification, value and terms, and compared those in detail. You remain completely free to reveal and choose any supplier from your full list of quotes — we simply highlight the strongest options so you don't have to read every quote line by line.";
const DISCLAIMER_AR = "هذه توصية محايدة من QuotesDone أعددناها لتسهيل قرارك. من بين جميع العروض التي استلمتها، اخترنا الثلاثة الأنسب لعملك من حيث المواصفات والقيمة والشروط، وقارنّاها بالتفصيل. يبقى لك كامل الحرية في كشف واختيار أي مورّد من قائمة عروضك الكاملة — نحن فقط نُبرز أقوى الخيارات حتى لا تضطر لقراءة كل عرض سطرًا بسطر.";
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
async function sha256hex(s: string){ const b=await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,'0')).join(''); }
function supplierLabel(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }
function parseJson(t: string){ let s=String(t||'').trim(); const f=s.match(/```(?:json)?\s*([\s\S]*?)```/i); if(f) s=f[1].trim(); try { return JSON.parse(s); } catch {} const m = s.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch {} } return null; }
const SYS = `You are the customer's personal EXPERT advisor for ONE job — think of yourself as the sharpest procurement director they could hire. First, silently work out the trade/domain of this job (e.g. joinery/wood, steel/metal, AC/HVAC, painting, flooring, glass/aluminium, printing/signage, CCTV/security, fire/MEP, events) and analyse AS A TOP EXPERT in that exact field.\n\nAUDIENCE: assume the customer is a complete non-expert with no patience. Use plain, simple language and short sentences. Whenever you use a technical word, explain it in a few words, e.g. \"MDF (cheap engineered board, not real wood)\", \"0.5mm gauge (thin steel)\".\n\nYou compare ANONYMIZED quotes labelled \"Supplier A/B/C...\" only. NEVER reveal or guess a supplier's identity, and never speculate about which company a quote might be from.\n\nSHORTLISTING (do this FIRST): you may be given MANY quotes — sometimes dozens. Do NOT compare them all. Fairly assess EVERY quote against the customer's brief: how well it matches the requested specification and scope, completeness, price, warranty, lead time and payment terms. Then SELECT THE THREE STRONGEST OVERALL. This is a balanced value judgement, NOT simply the three cheapest — a well-specified quote at a fair price beats a rock-bottom quote that under-specs or misses scope. Build the detailed side-by-side (the \"quotes\" array) for ONLY those three shortlisted quotes, and make \"top3\" rank those same three (best first). In \"shortlist_reason\", state in one plain sentence how you chose the three (and, if you excluded cheaper ones, why). If there are three or fewer quotes, include them all. Keep each quote's original label (Supplier A, B, C...).\n\nLINE-BY-LINE (the core of your job when itemised): a quote may carry an \"items\" array — the supplier's OWN priced breakdown, with description, brand, model, specification, qty, unit, unit_price, labour, install, commissioning, amount and country_of_origin. When items are present you MUST compare AT LINE LEVEL, exactly as a procurement director would:\n- Match equivalent lines across the shortlisted quotes and name where one supplier charges materially more or less FOR THE SAME THING. Quote the real numbers, e.g. \"B charges AED 420/panel vs A at AED 265/panel for the same 12mm toughened pane.\"\n- Catch brand/model/spec/origin substitution: \"A quotes an unbranded patch fitting; C quotes Dorma — that is why C is dearer.\" Only state a brand/spec if it is actually written in that line.\n- Catch OMITTED lines: an item the others price and this one simply does not include. That is the most common way a quote looks cheap.\n- Catch cost hidden in labour / install / commissioning rather than unit_price, and quotes where the items do not add up to the headline total.\n- If a quote has NO items array it was submitted as a lump sum: say so plainly, because a lump sum cannot be verified line by line and carries more risk.\n\nQUOTE INTEGRITY: each quote may carry \"completeness\" (our own automated check: a score, whether it passed, and how many mandatory fields are still missing), \"expired\" (the supplier's own validity has lapsed) and \"source\" (\"form\" = typed into our structured form, \"upload\" = read from the supplier's own PDF, so wording is theirs). Weigh these honestly: ALWAYS flag an expired quote, and treat a quote that fails the completeness check as riskier than its price alone suggests.\n\nTRACK RECORD (secondary, never primary): a quote may carry \"track_record\" — anonymous platform history for that supplier: rating and review_count (and whether the rating is from QuotesDone jobs or Google), verified (we checked their trade licence), years_active, jobs_won on QuotesDone, and win_rate. Use it ONLY as a tie-breaker between otherwise comparable quotes, or as a risk note (e.g. \"lowest price but unrated and unverified on our platform — ask for references\"). It must NEVER outrank specification and price: a well-specified, fairly priced quote from a supplier with no history still beats a worse-specified quote from a long-established one. Say so plainly if that is the case. Do NOT use track record to guess who the supplier is.\n\nEXPERT REFERENCE (use it, never quote it verbatim): the input may include \"expert_reference\" — QuotesDone's OWN curated knowledge for this exact trade: UAE market price ranges, red flags, the spec/quality hierarchy (which materials, grades, brands are better and dearer), and what a complete quote must itemise. Apply it to (1) SANITY-CHECK the shortlisted prices against the UAE market range — flag any quote that is suspiciously cheap (usually a lower grade, thinner spec or missing scope) or unusually expensive, and say what a fair range looks like; (2) rank technical quality AUTHORITATIVELY (e.g. porcelain vs ceramic, solid wood vs MDF, 4MP vs 8MP, S355 vs S275, laminated-tempered vs annealed); (3) know exactly which specs a complete quote MUST state for this trade so you catch omissions even in a trade you personally know less well. The input may also include \"must_state_specs\" — the specifications a complete quote for this trade must contain; if a shortlisted quote omits any, surface it in that quote's missing_from_request or flags. If no expert_reference is given, rely on your own top-expert domain knowledge as before.\n\nYOUR #1 JOB is NOT to pick the cheapest, fastest, or best-rated. It is to tell the customer WHAT EACH PRICE ACTUALLY BUYS, so a tempting low price that hides a lower spec is caught. Specifically:\n- Detect when a cheaper quote is cheaper because it uses a LOWER material grade, thinner/smaller spec, weaker brand tier, or a SMALLER scope than the others. State it plainly, e.g. \"A is ~30% cheaper but quoted MDF, not the solid oak that B and C quoted - it is not the same product.\"\n- Only state a material/spec difference if it is actually written in that quote. If a key spec (wood type, thickness, brand, gauge, paint type, glass mm, etc.) is NOT stated, do NOT invent it - instead flag it to ask, e.g. \"wood type not stated - confirm before paying.\"\n- COMPARE EACH SHORTLISTED QUOTE BACK TO WHAT THE CUSTOMER ACTUALLY ASKED FOR (the job brief and the requested item list / BOQ). For every shortlisted quote, list what the customer asked for that this quote DOES NOT cover (missing_from_request), and where this quote DEVIATES from the requested specification (spec_deviation: wrong material, different size, substituted brand, reduced quantity, changed scope). If a quote fully matches, leave these arrays empty.\n- Surface anything OUT OF THE ORDINARY: a price far from the others, a missing major item the job needs, no/short warranty, odd payment terms, a very long lead time, or quotes that simply are not comparable.\n\nTOP 3 RECOMMENDATION (most important output): give the customer the ranked TOP 3 (\"top3\"), best first. Recommend primarily the quote that BEST MATCHES THE REQUESTED SPECIFICATION AT THE LOWEST PRICE. If your #1 pick has a genuine downside (e.g. long delivery, short warranty, a missing item), STILL recommend it but state the trade-off in plain words, e.g. \"Best match for your spec and AED 1,200 cheaper - the only catch is delivery is ~2 weeks longer than B.\" Each entry: rank (1/2/3), label, why (one plain sentence on why it is recommended at this rank), tradeoff (the catch, or \"\" if none). If there are only 2 quotes, give 2.\n\nCOMPLIANCE LENS: a \"compliance_reference\" listing UAE authorities/standards may be included in the input. For any REGULATED system in this job (CCTV/security/access control, fire alarm & firefighting, electrical/power, lifts & escalators, gas, HVAC fire dampers, signage permits, glazing, telecom/cabling, pools, commercial kitchens, building permit/NOC), check whether each shortlisted quote addresses the governing UAE authority/standard. If a quote ignores it, or appears to under-spec below code, add a plain WATCH-OUT, e.g. \"CCTV in Dubai must follow Dubai Police/SIRA rules - none of the quotes mention SIRA-approved cameras; ask before paying.\" If the job brief says the customer requested a non-standard/different spec, respect it and do NOT flag it. Always frame compliance as something to VERIFY - never assert a supplier is non-compliant as a fact.\n\nKeep EVERYTHING short and scannable - the customer must decide in seconds. No paragraphs, no filler, no flattery. Be impartial: help them decide, do not hard-sell one supplier.\n\nReturn STRICT JSON ONLY (no prose) with keys:\n{\n \"trade\": string,\n \"considered\": number,\n \"shortlist_reason\": string,\n \"bottom_line\": string,\n \"overview\": string,\n \"quotes\": [ {\n   \"label\": string, \"price\": number|null, \"lead_time\": string|null, \"validity\": string|null, \"warranty\": string|null, \"payment_terms\": string|null,\n   \"getting\": string,\n   \"includes\": string[],\n   \"excludes\": string[],\n   \"missing_from_request\": string[],\n   \"spec_deviation\": string[],\n   \"track_record_note\": string,\n   \"flags\": string[]\n } ],\n \"line_findings\": [ { \"item\": string, \"finding\": string } ],\n \"top3\": [ { \"rank\": number, \"label\": string, \"why\": string, \"tradeoff\": string } ],\n \"cheapest_label\": string|null,\n \"best_value_label\": string|null,\n \"best_value_reason\": string,\n \"watch_outs\": string[],\n \"advice\": string\n}\n\"track_record_note\" is one short plain sentence on that supplier's platform history and what it means for risk, or \"\" if there is nothing meaningful to say. \"line_findings\" is your line-by-line procurement read across the shortlisted quotes: each entry names the item or cost head and states the finding in one plain sentence with real numbers. Return [] when no quote is itemised. The \"quotes\" array must contain ONLY the shortlisted top 3 (or fewer if fewer exist). \"considered\" = how many quotes you evaluated in total. Be factual; never invent specs, prices or identities. All money is in AED.`;
const AR = `\n\nLANGUAGE: Write ALL human-readable text VALUES in this JSON — trade, shortlist_reason, bottom_line, overview, getting, includes, excludes, missing_from_request, spec_deviation, track_record_note, flags, line_findings.item, line_findings.finding, top3.why, top3.tradeoff, best_value_reason, watch_outs, advice — in clear, natural, professional Modern Standard Arabic. Do NOT translate the JSON keys. Keep the supplier labels exactly as \"Supplier A\", \"Supplier B\", etc. Keep all numbers and prices unchanged (AED).`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const inquiry_id = String(body.inquiry_id || '');
    const langReq = String(body.lang || '').toLowerCase();
    let isAdmin = false; let cust: any = null;
    if (body?.__secret && (await requireInternal(admin, body.__secret, 'quote_compare')).ok) isAdmin = true;
    if (!isAdmin) {
      const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      const { data: { user } } = await admin.auth.getUser(jwt);
      if (user?.email) {
        const allow = (await sec('admin_emails') || '').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean);
        if (allow.includes(user.email.toLowerCase())) isAdmin = true;
        else { const { data: c } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle(); cust = c; }
      }
    }
    if (!isAdmin && !cust) {
      if (body.__secret !== undefined) { await logRun('error', { bad_secret: 1, compared: 0 }, 'quote_compare rejected a caller presenting a wrong inbound secret (401) for inquiry ' + String(inquiry_id).slice(0, 60) + '. No quote comparison was produced, so the customer is left with raw quotes and no recommendation.'); }
      return J({ error: 'unauthorized' }, 401);
    }
    const { data: inq, error: inqErr } = await admin.from('inquiries').select('id,customer_id,summary,category,emirate,budget,raw_input,spec,boq').eq('id', inquiry_id).maybeSingle();
    if (!inq) { await logRun('error', { compared: 0, inquiry_loaded: 0 }, 'quote_compare could not load inquiry ' + String(inquiry_id).slice(0, 60) + ' (' + String(inqErr?.message || 'no such row').slice(0, 120) + '), so the customer requested a comparison of their quotes and received a not_found instead — they cannot act on the quotes they already paid attention to.'); return J({ error: 'not_found' }, 404); }
    if (!isAdmin && inq.customer_id !== cust.id) { await logRun('error', { compared: 0, ownership_violation: 1 }, 'quote_compare blocked an ownership violation (403): a signed-in customer requested the quote comparison for inquiry ' + String(inquiry_id).slice(0, 60) + ' which belongs to a different customer. Anonymised competitor pricing was NOT disclosed.'); return J({ error: 'not_your_inquiry' }, 403); }
    const MAX_COMPARE = 120;
    const MAX_ITEMS_PER_QUOTE = 40;
    const MAX_ITEMS_TOTAL = 1200;
    const { data: qsAll, error: qsErr } = await admin.from('quotes').select('id,supplier_id,quote_amount,lead_time,validity,warranty,payment_terms,scope,conditions,exclusions,notes,status,source,expires_at,quality,submittable').eq('inquiry_id', inquiry_id).order('quote_amount', { ascending: true }).limit(MAX_COMPARE + 40);
    if (qsErr) { await logRun('error', { compared: 0, quotes_query_ok: 0, quotes_seen: 0 }, 'quote_compare could not read the quotes for inquiry ' + String(inquiry_id).slice(0, 60) + ' (' + String(qsErr.message).slice(0, 120) + '). The customer will be told they need at least two quotes even though suppliers may well have quoted — a query failure presented as an absence of quotes.'); }
    const live = (qsAll || []).filter((q: any) => q.status !== 'draft');
    const qs = live.slice(0, MAX_COMPARE);
    if (!qs || qs.length < 2) { await logRun(qsErr ? 'error' : 'ok', { compared: 0, quotes_seen: qs.length, quotes_total_rows: (qsAll || []).length, need_two: 1, insufficient_genuine: qsErr ? 0 : 1, quotes_query_ok: qsErr ? 0 : 1 }, qsErr ? 'Customer asked to compare quotes and got \'need_two\' because the quotes query FAILED, not because too few suppliers quoted — real quotes may exist and are being hidden from the customer by a database error.' : ('Customer asked to compare quotes but only ' + qs.length + ' non-draft quote(s) exist for this RFQ, so no comparison was produced. This is genuine: suppliers have not returned enough quotes yet.')); return J({ ok: false, error: 'need_two', note: 'Comparison needs at least two complete quotes.' }, 200); }

    let itemsByQuote: Record<string, any[]> = {}; let itemsTotal = 0;
    try {
      const { data: rows } = await admin.from('quote_items')
        .select('quote_id,line_no,description,brand,model,specification,qty,unit,unit_price,labour,install,commissioning,amount,country_of_origin,notes')
        .in('quote_id', qs.map((q: any) => String(q.id))).order('line_no', { ascending: true }).limit(MAX_ITEMS_TOTAL);
      for (const r of (rows || [])) {
        const k = String(r.quote_id); (itemsByQuote[k] ||= []);
        if (itemsByQuote[k].length >= MAX_ITEMS_PER_QUOTE) continue;
        itemsByQuote[k].push({ line: r.line_no, description: r.description, brand: r.brand, model: r.model, specification: r.specification, qty: r.qty, unit: r.unit, unit_price: r.unit_price, labour: r.labour, install: r.install, commissioning: r.commissioning, amount: r.amount, country_of_origin: r.country_of_origin, notes: r.notes });
        itemsTotal++;
      }
    } catch (_e) { itemsByQuote = {}; }

    const trackBySupplier: Record<string, any> = {};
    try {
      const supIds = [...new Set(qs.map((q: any) => q.supplier_id).filter((x: any) => x != null))];
      if (supIds.length) {
        const yr = new Date().getFullYear();
        const { data: ls } = await admin.from('leads').select('id,rating,rating_maps,reviews,reviews_maps,app_rating,app_reviews,verified,founded_year').in('id', supIds);
        const { data: perf } = await admin.from('supplier_perf').select('supplier_id,won,win_rate').in('supplier_id', supIds);
        const perfById: Record<string, any> = {}; for (const p of (perf || [])) perfById[String(p.supplier_id)] = p;
        for (const l of (ls || [])) {
          const appN = Number(l.app_reviews || 0);
          const ratingValue = appN > 0 ? (l.app_rating != null ? Number(l.app_rating) : null) : ((l.rating ?? l.rating_maps) != null ? Number(l.rating ?? l.rating_maps) : null);
          const reviewCount = appN > 0 ? appN : Number(l.reviews ?? l.reviews_maps ?? 0);
          const pf = perfById[String(l.id)] || {};
          trackBySupplier[String(l.id)] = {
            rating: ratingValue, review_count: reviewCount,
            rating_source: appN > 0 ? 'QuotesDone jobs' : 'Google',
            verified: !!l.verified,
            years_active: l.founded_year ? Math.max(0, yr - Number(l.founded_year)) : null,
            jobs_won_on_quotesdone: pf.won ?? 0,
            win_rate: pf.win_rate ?? null };
        }
      }
    } catch (_e) { /* track record is optional */ }

    const nowTs = Date.now();
    const labelled = qs.map((q: any, i: number) => {
      const ql = (q.quality && typeof q.quality === 'object') ? q.quality : null;
      // AUDIT (4 Aug 2026). This read `m.mandatory` off `quality.missing`, which trg_quote_quality
      // writes as to_jsonb(gmiss) where gmiss is text[] — an array of plain STRINGS. A string has no
      // .mandatory, so the filter matched nothing and missing_mandatory was 0 for every quote ever
      // compared. The single deterministic input to the ranking prompt was a constant.
      // The objects that carry `mandatory` are at quality.category.missing, and the trigger has
      // already counted them into quality.category.mandatory_missing — so read the number it
      // computed instead of re-deriving it. It stays null (not 0) when the category has no spec
      // group: "we do not know" and "nothing is missing" must never collapse into one value again.
      const cq = (ql && typeof (ql as any).category === 'object' && (ql as any).category) ? (ql as any).category : null;
      const mmRaw = cq ? Number((cq as any).mandatory_missing) : Number.NaN;
      const missMandatory = Number.isFinite(mmRaw) ? mmRaw : null;
      const items = itemsByQuote[String(q.id)] || [];
      const tr = q.supplier_id != null ? trackBySupplier[String(q.supplier_id)] : null;
      return { label: 'Supplier ' + supplierLabel(i), price: q.quote_amount, lead_time: q.lead_time, validity: q.validity, warranty: q.warranty, payment_terms: q.payment_terms, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, notes: q.notes,
        items: items.length ? items : undefined,
        itemised: items.length > 0,
        expired: q.expires_at ? (new Date(q.expires_at).getTime() < nowTs) : false,
        source: q.source || 'form',
        completeness: ql ? { score: ql.score ?? null, passed: ql.pass ?? null, missing_mandatory: missMandatory } : undefined,
        track_record: tr || undefined };
    });
    const lang = (langReq === 'ar' || langReq === 'en') ? langReq : (/[؀-ۿ]/.test(String(inq.summary||'') + ' ' + String(inq.raw_input||'')) ? 'ar' : 'en');
    const qhash = await sha256hex(JSON.stringify(labelled));
    try { const { data: cached } = await admin.from('qd_compare_cache').select('analysis').eq('inquiry_id', inquiry_id).eq('quotes_hash', qhash).eq('lang', lang).maybeSingle(); if (cached?.analysis) { await logRun('ok', { compared: 1, quotes_seen: qs.length, cached: 1, lang }, 'Quote comparison for ' + qs.length + ' quotes served from cache; the customer got their recommendation with no model call.'); return J({ ok: true, analysis: cached.analysis, cached: true }); } } catch (_e) { /* */ }
    const boqItems = (inq.boq && Array.isArray((inq.boq as any).boq)) ? (inq.boq as any).boq.map((b: any) => `${b.description || ''}${b.qty ? ' ('+b.qty+' '+(b.unit||'')+')' : ''}`).slice(0, 40) : [];
    const cref = await sec('compliance_ref');
    // NEW v21: QuotesDone's own curated expertise for this trade (market prices, red flags, spec hierarchy, must-state specs).
    let expertRef = ''; let mustSpecs: string[] = [];
    try { const { data: er } = await admin.rpc('fn_category_expert_ref', { p_category: inq.category }); if (er) expertRef = String(er); } catch (_e) { /* optional */ }
    try { const { data: grp } = await admin.rpc('fn_quote_spec_group', { p_category: inq.category });
      if (grp) { const { data: specs } = await admin.from('category_quote_specs').select('label').eq('spec_group', grp).eq('mandatory', true); mustSpecs = (specs || []).map((s: any) => String(s.label)); } } catch (_e) { /* optional */ }
    const payload: Record<string, unknown> = { job: { summary: inq.summary, category: inq.category, emirate: inq.emirate, budget: inq.budget, requested_details: inq.raw_input || '', requested_spec: inq.spec || {}, requested_items: boqItems }, quotes: labelled };
    if (cref) payload.compliance_reference = cref;
    if (expertRef) payload.expert_reference = expertRef;
    if (mustSpecs.length) payload.must_state_specs = mustSpecs;
    const sys = SYS + (lang === 'ar' ? AR : '');
    const key = await sec('cred_fn_ai'); if (!key) { await logRun('error', { compared: 0, quotes_seen: qs.length, ai_key_present: 0 }, 'quote_compare aborted: the cred_fn_ai credential is missing, so ' + qs.length + ' real supplier quotes could not be compared. The customer is shown \'ai_unavailable\' at the exact moment they are trying to choose a supplier, and the RFQ stalls at the decision step.'); return J({ ok: false, error: 'ai_unavailable' }, 200); }
    let parsed: any = null; let lastDetail = '';
    let attempts = 0;
    for (let attempt = 0; attempt < 2 && !parsed; attempt++) {
      try {
        attempts++;
        const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'quote_compare', sys, input: JSON.stringify(payload), max: 4200, temperature: 0.2 }) });
        const jd = await r.json();
        const model = String(jd?.model || 'ai_gateway');
        if (!r.ok) { lastDetail = 'http' + (r.status) + ':' + model + ':' + (JSON.stringify(jd?.error||'').slice(0,140)); continue; }
        const content = jd?.content || '';
        if (!content) { lastDetail = 'empty:' + model + ':' + String(jd?.outcome || ''); continue; }
        const p = parseJson(content);
        if (p) { parsed = p; break; }
        lastDetail = 'parse:' + model;
      } catch (e) { lastDetail = 'exc:' + String((e as Error)?.message || e).slice(0, 100); }
    }
    if (!parsed) { await logRun('error', { compared: 0, quotes_seen: qs.length, ai_attempts: attempts, ai_ok: 0, lang }, 'quote_compare produced NO comparison for ' + qs.length + ' real supplier quotes because every model attempt failed or returned unparseable output (' + String(lastDetail).slice(0, 120) + '). The customer reached the decision step, was given nothing to compare, and this returns HTTP 200 so it is invisible to ordinary error monitoring.'); return J({ ok: false, error: 'parse_failed', detail: lastDetail }, 200); }
    if (Array.isArray(parsed.quotes) && parsed.quotes.length > 3) parsed.quotes = parsed.quotes.slice(0, 3);
    if (Array.isArray(parsed.top3) && parsed.top3.length > 3) parsed.top3 = parsed.top3.slice(0, 3);
    if (Array.isArray(parsed.line_findings) && parsed.line_findings.length > 14) parsed.line_findings = parsed.line_findings.slice(0, 14);
    if (typeof parsed.considered !== 'number') parsed.considered = qs.length;
    parsed.total_quotes = live.length;
    parsed.shortlisted = Math.min(3, qs.length);
    parsed.itemised_quotes = labelled.filter((q: any) => q.itemised).length;
    parsed.disclaimer = (lang === 'ar') ? DISCLAIMER_AR : DISCLAIMER_EN;
    let cacheSaved = 1;
    try { const { error: cacheErr } = await admin.from('qd_compare_cache').upsert({ inquiry_id, quotes_hash: qhash, lang, analysis: parsed, created_at: new Date().toISOString() }); if (cacheErr) cacheSaved = 0; } catch (_e) { cacheSaved = 0; }
    const _top3 = Array.isArray(parsed.top3) ? parsed.top3.length : 0;
    const _shown = Array.isArray(parsed.quotes) ? parsed.quotes.length : 0;
    const _lines = Array.isArray(parsed.line_findings) ? parsed.line_findings.length : 0;
    await logRun((_top3 > 0 && _shown > 0) ? 'ok' : 'error', { compared: 1, quotes_seen: qs.length, quotes_live: live.length, itemised: parsed.itemised_quotes, line_items_sent: itemsTotal, track_records: Object.keys(trackBySupplier).length, expert_ref: expertRef ? 1 : 0, must_specs: mustSpecs.length, line_findings: _lines, shortlisted: _shown, top3: _top3, ai_attempts: attempts, ai_ok: 1, cached: 0, cache_saved: cacheSaved, lang }, (_top3 > 0 && _shown > 0) ? ('Quote comparison delivered: ' + qs.length + ' quotes evaluated (' + parsed.itemised_quotes + ' itemised, ' + itemsTotal + ' line items, ' + Object.keys(trackBySupplier).length + ' track records, expert_ref=' + (expertRef ? 'yes' : 'no') + '), ' + _shown + ' shortlisted, ' + _top3 + ' ranked recommendation(s), ' + _lines + ' line-level finding(s).' + (cacheSaved ? '' : ' NOTE: the result could not be written to qd_compare_cache, so every re-open re-runs the model at full cost.')) : ('quote_compare returned a comparison object with an EMPTY shortlist/top3 for ' + qs.length + ' real quotes — the model responded but produced no ranked recommendation, so the customer sees a blank comparison and cannot choose a supplier, while the call reports HTTP 200 success.'));
    return J({ ok: true, analysis: parsed });
  } catch (e) { await logRun('error', { compared: 0, unhandled_exception: 1 }, 'quote_compare threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e).slice(0, 200) + ' — the customer could not compare the quotes they received and the RFQ stalls at the decision step.'); return J({ error: String((e as Error)?.message || e) }, 500); }
});
