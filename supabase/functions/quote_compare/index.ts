import { parseJson as readModelJson } from '../_shared/model_json.ts';
import { ratingBand, reviewCountBand, yearsBand } from '../_shared/pre_reveal_bands.ts';
import { siteCors } from '../_shared/site_origins.ts';
// quote_compare v21 — adjudicates EVERY live quote with the supplier's own priced line
// items, our completeness check, expiry, source, anonymous track record, AND (new in v21)
// QuotesDone's own curated per-category EXPERT REFERENCE: UAE market price ranges + red
// flags, spec hierarchy, and what a complete quote must itemise — so the agent sanity-checks
// prices against the market and ranks technical quality authoritatively for any trade.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { isLiveQuote } from '../_shared/quote_live.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { adminCaller } from '../_shared/admin_session.ts';
import { comparedPrice, deterministicCompare, rosterOf } from './deterministic.ts';
import { observe } from '../_shared/observe.ts';
import { challengeBeforeDeciding, LARGE_SUPPLIER_CHOICE_AED } from '../_shared/high_stakes_challenge.ts';
import { registeredLocale } from '../_shared/registered_locale.ts';
import { activeFailure, failureRecord, isCachedAnalysis } from '../_shared/spend_guards.ts';
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
const DISCLAIMER_AR = "هذه توصية محايدة أعدّتها QuotesDone لتيسير قرارك: من بين جميع العروض التي تلقيتها، اخترنا العروض الثلاثة الأنسب لمشروعك من حيث المواصفات والقيمة والشروط، وقارنّا بينها بالتفصيل. ولك مطلق الحرية في الكشف عن أي مورّد من قائمة عروضك الكاملة واختياره؛ فغايتنا أن نُبرز أقوى الخيارات لنوفّر عليك عناء قراءة كل عرض سطرًا بسطر.";
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
async function sha256hex(s: string){ const b=await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,'0')).join(''); }
// The technical comparison (docs/contracts/technical_comparison.md) and the option-aware labels.
import { rendererView, technicalComparison, type TechnicalComparison } from '../_shared/line_specs/compare.ts';
import { compareItem, heldQuoteIds } from '../_shared/reveal_guard.ts';
import { requirementsOf } from '../_shared/line_specs/assess.ts';
import { labelQuotes, recordShown } from '../_shared/quote_labels.ts';
import { sanctionedLeads } from '../_shared/sanctioned.ts';
import { withheldWhileChecked } from '../_shared/quotes_being_checked.ts';
import { DATA_NOT_INSTRUCTIONS } from '../_shared/untrusted.ts';
import { chunks, differingCells } from '../_shared/routine_judgements.ts';
// 10 Nov 2026 (founder ledger 1588-1590, sales_engineer): the expert review notes per quote, and the generaliser every
// string this function returns passes through before the reveal.
import { ctxOfQuote, generaliseDeep, generaliseLine, generaliseQuoteTerms, mergeCtx, type GeneraliseCtx } from '../_shared/quote_generalise.ts';
import { requestOf, reviewNotes, type ReviewNote } from '../_shared/quote_review_notes.ts';
// 15 Nov 2026 (journey A, sales_engineer): each quote measured against what the customer asked for, from its RAW lines.
import { annotateTechnical, enforceFit, fitQuote, fitView, hiddenBrandPhrases, hideBrandForModel, hideBrandPhrases, mayRaisePoints, POINT_CODE, pointsHandoff, requestRequirements, siteVisitAsked, withAnswers, type QuoteFit } from '../_shared/request_fit.ts';
import { knownNameRe, scrubIdentityText } from '../_shared/identity_text.ts';
import { tradeOfCategory } from '../_shared/line_specs/model.ts';
// the first ```json block anywhere is the reply (kept here: no other caller reads a fence that does not wrap the whole reply)
// deno-lint-ignore no-explicit-any
function parseJson(t: string){ const s=String(t||'').trim(); const f=s.match(/```(?:json)?\s*([\s\S]*?)```/i); return readModelJson<any>(f ? f[1] : s, { wholeDecides: true }); }
const SYS = `You are the customer's personal EXPERT advisor for ONE job — think of yourself as the sharpest procurement director they could hire. Identify the trade/domain of this job (e.g. joinery/wood, steel/metal, AC/HVAC, painting, flooring, glass/aluminium, printing/signage, CCTV/security, fire/MEP, events) and analyse AS A TOP EXPERT in that exact field.\n\nAUDIENCE: assume the customer is a complete non-expert with no patience. Use plain, simple language and short sentences. Whenever you use a technical word, explain it in a few words, e.g. \"MDF (cheap engineered board, not real wood)\", \"0.5mm gauge (thin steel)\".\n\nYou compare ANONYMIZED quotes labelled \"Supplier A/B/C...\" only. NEVER reveal or guess a supplier's identity, and never speculate about which company a quote might be from.\n\nSHORTLISTING (do this FIRST): you may be given MANY quotes — sometimes dozens. Do NOT compare them all. Fairly assess EVERY quote against the customer's brief: how well it matches the requested specification and scope, completeness, price, warranty, lead time and payment terms. Then SELECT THE THREE STRONGEST OVERALL. This is a balanced value judgement, NOT simply the three cheapest — a well-specified quote at a fair price beats a rock-bottom quote that under-specs or misses scope. Build the detailed side-by-side (the \"quotes\" array) for ONLY those three shortlisted quotes, and make \"top3\" rank those same three (best first). In \"shortlist_reason\", state in one plain sentence how you chose the three (and, if you excluded cheaper ones, why). If there are three or fewer quotes, include them all. Keep each quote's original label (Supplier A, B, C...).\n\nLINE-BY-LINE (the core of your job when itemised): a quote may carry an \"items\" array — the supplier's OWN priced breakdown, with description, brand, model, specification, qty, unit, unit_price, labour, install, commissioning, amount and country_of_origin. When items are present you MUST compare AT LINE LEVEL, exactly as a procurement director would:\n- Match equivalent lines across the shortlisted quotes and name where one supplier charges materially more or less FOR THE SAME THING. Quote the real numbers, e.g. \"B charges AED 420/panel vs A at AED 265/panel for the same 12mm toughened pane.\"\n- Catch brand/model/spec/origin substitution: \"A quotes an unbranded patch fitting; C quotes a premium German brand fitting — that is why C is dearer.\" Only state a brand tier, origin or spec if it is actually written in that line. BEFORE THE REVEAL NO BRAND IS NAMED: brands, model numbers and product lines in the input are already written as \"<tier> <origin> brand\" (e.g. \"premium German brand\") and \"model stated (shown after reveal)\"; write them exactly so, never name a brand, a model number or a product line, and never try to restore one (founder ruling 1589).\n- REVIEW NOTES: a quote may carry \"review_notes\" — the QuotesDone sales engineer's own checks of that quote against what the customer asked for (requested items not priced, exclusions that cut requested scope, origin or brand-tier deviations, a lower grade, a quantity short, a lead time past the required date, a warranty shorter than asked). Treat each as an established fact: put it in that quote's missing_from_request or spec_deviation, and weigh it in cost-to-value — a quote that leaves out requested scope or downgrades the specification is not cheaper for the same thing, so it must not outrank a complete quote on price alone.\n- Catch OMITTED lines: an item the others price and this one simply does not include. That is the most common way a quote looks cheap.\n- Catch cost hidden in labour / install / commissioning rather than unit_price, and quotes where the items do not add up to the headline total.\n- If a quote has NO items array it was submitted as a lump sum: say so plainly, because a lump sum cannot be verified line by line and carries more risk.\n\nQUOTE INTEGRITY: each quote may carry \"completeness\" (our own automated check: a score, whether it passed, and how many mandatory fields are still missing), \"expired\" (the supplier's own validity has lapsed) and \"source\" (\"form\" = typed into our structured form, \"upload\" = read from the supplier's own PDF, so wording is theirs). Weigh these honestly: ALWAYS flag an expired quote, and treat a quote that fails the completeness check as riskier than its price alone suggests.\n\nTRACK RECORD (secondary, never primary): a quote may carry \"track_record\" — anonymous platform history for that supplier: rating and review_count — a rating EXISTS ONLY when QuotesDone customers rated that supplier after a job they actually gave them; when it is null the supplier is simply NOT YET RATED HERE, which is not a bad rating and must never be read or described as one — verified (we checked their trade licence), years_active, jobs_won on QuotesDone, and win_rate. Use it ONLY as a tie-breaker between otherwise comparable quotes, or as a risk note (e.g. \"lowest price but unrated and unverified on our platform — ask for references\"). It must NEVER outrank specification and price: a well-specified, fairly priced quote from a supplier with no history still beats a worse-specified quote from a long-established one. Say so plainly if that is the case. Do NOT use track record to guess who the supplier is.\n\nEXPERT REFERENCE (use it, never quote it verbatim): the input may include \"expert_reference\" — QuotesDone's OWN curated knowledge for this exact trade: UAE market price ranges, red flags, the spec/quality hierarchy (which materials, grades, brands are better and dearer), and what a complete quote must itemise. Apply it to (1) SANITY-CHECK the shortlisted prices against the UAE market range — flag any quote that is suspiciously cheap (usually a lower grade, thinner spec or missing scope) or unusually expensive, and say what a fair range looks like; (2) rank technical quality AUTHORITATIVELY (e.g. porcelain vs ceramic, solid wood vs MDF, 4MP vs 8MP, S355 vs S275, laminated-tempered vs annealed); (3) know exactly which specs a complete quote MUST state for this trade so you catch omissions even in a trade you personally know less well. The input may also include \"must_state_specs\" — the specifications a complete quote for this trade must contain; if a shortlisted quote omits any, surface it in that quote's missing_from_request or flags. If no expert_reference is given, rely on your own top-expert domain knowledge as before.\n\nYOUR #1 JOB is NOT to pick the cheapest, fastest, or best-rated. It is to tell the customer WHAT EACH PRICE ACTUALLY BUYS, so a tempting low price that hides a lower spec is caught. Specifically:\n- Detect when a cheaper quote is cheaper because it uses a LOWER material grade, thinner/smaller spec, weaker brand tier, or a SMALLER scope than the others. State it plainly, e.g. \"A is ~30% cheaper but quoted MDF, not the solid oak that B and C quoted - it is not the same product.\"\n- Only state a material/spec difference if it is actually written in that quote. If a key spec (wood type, thickness, brand, gauge, paint type, glass mm, etc.) is NOT stated, do NOT invent it - instead say it is not stated, e.g. \"wood type not stated.\" NEVER tell the customer to ask, contact or confirm anything with a supplier: before the reveal they cannot reach one, and QuotesDone asks the supplier for a missing detail itself\n- COMPARE EACH SHORTLISTED QUOTE BACK TO WHAT THE CUSTOMER ACTUALLY ASKED FOR (the job brief and the requested item list / BOQ). For every shortlisted quote, list what the customer asked for that this quote DOES NOT cover (missing_from_request), and where this quote DEVIATES from the requested specification (spec_deviation: wrong material, different size, substituted brand, reduced quantity, changed scope). If a quote fully matches, leave these arrays empty.\n- Surface anything OUT OF THE ORDINARY: a price far from the others, a missing major item the job needs, no/short warranty, odd payment terms, a very long lead time, or quotes that simply are not comparable.\n\nWHEN THE QUOTES CANNOT BE COMPARED (refuse rather than invent a basis): two quotations are comparable only when they answer the SAME job on a basis a customer could weigh - same scope of works, same deliverable, same unit basis. If the quotations in front of you answer DIFFERENT scopes (one prices supply only and another supply-and-install of a different system; one prices a different building, floor count, area or product altogether), or their units cannot be reconciled (one per m2, one a lump sum for an unstated area), then you MUST NOT rank them. Do not construct a common basis the suppliers did not quote on, and do not fall back on price alone: a cheaper number for different work is not a better quote. Set \"not_comparable\": true, put in \"not_comparable_reason\" one plain sentence naming exactly what differs (e.g. \"A prices supply only for 120 m2; B prices supply and installation for a different 300 m2 floor - these are not the same job\"), return \"top3\": [], leave \"best_value_label\" and \"cheapest_label\" null, and still fill \"quotes\" so the customer can see WHY. Refusing is the correct expert answer; ranking anyway is the error this contract exists to prevent. When the quotes ARE comparable, set \"not_comparable\": false and rank as instructed.\n\nTOP 3 RECOMMENDATION (most important output): give the customer the ranked TOP 3 (\"top3\"), best first. Recommend primarily the quote that BEST MATCHES THE REQUESTED SPECIFICATION AT THE LOWEST PRICE. If your #1 pick has a genuine downside (e.g. long delivery, short warranty, a missing item), STILL recommend it but state the trade-off in plain words, e.g. \"Best match for your spec and AED 1,200 cheaper - the only catch is delivery is ~2 weeks longer than B.\" Each entry: rank (1/2/3), label, why (one plain sentence on why it is recommended at this rank), tradeoff (the catch, or \"\" if none). If there are only 2 quotes, give 2.\n\nCOMPLIANCE LENS: a \"compliance_reference\" listing UAE authorities/standards may be included in the input. For any REGULATED system in this job (CCTV/security/access control, fire alarm & firefighting, electrical/power, lifts & escalators, gas, HVAC fire dampers, signage permits, glazing, telecom/cabling, pools, commercial kitchens, building permit/NOC), check whether each shortlisted quote addresses the governing UAE authority/standard. If a quote ignores it, or appears to under-spec below code, add a plain WATCH-OUT, e.g. \"CCTV in Dubai must follow Dubai Police/SIRA rules - none of the quotes mention SIRA-approved cameras; ask before paying.\" If the job brief says the customer requested a non-standard/different spec, respect it and do NOT flag it. Always frame compliance as something to VERIFY - never assert a supplier is non-compliant as a fact.\n\nKeep EVERYTHING short and scannable - the customer must decide in seconds. No paragraphs, no filler, no flattery. Be impartial: help them decide, do not hard-sell one supplier.\n\nReturn STRICT JSON ONLY (no prose) with keys:\n{\n \"trade\": string,\n \"considered\": number,\n \"not_comparable\": boolean,\n \"not_comparable_reason\": string,\n \"shortlist_reason\": string,\n \"bottom_line\": string,\n \"overview\": string,\n \"quotes\": [ {\n   \"label\": string, \"price\": number|null, \"lead_time\": string|null, \"validity\": string|null, \"warranty\": string|null, \"payment_terms\": string|null,\n   \"getting\": string,\n   \"includes\": string[],\n   \"excludes\": string[],\n   \"missing_from_request\": string[],\n   \"spec_deviation\": string[],\n   \"track_record_note\": string,\n   \"price_score\": number, \"delivery_score\": number, \"quality_score\": number, \"score_reason\": string,\n   \"flags\": string[]\n } ],\n \"line_findings\": [ { \"item\": string, \"finding\": string } ],\n \"top3\": [ { \"rank\": number, \"label\": string, \"why\": string, \"tradeoff\": string } ],\n \"cheapest_label\": string|null,\n \"best_value_label\": string|null,\n \"best_value_reason\": string,\n \"watch_outs\": string[],\n \"advice\": string\n}\nPER-DIMENSION SCORES: for each shortlisted quote give \"price_score\", \"delivery_score\" and \"quality_score\" as an INTEGER 1-5 (5 = best), scored RELATIVE TO THE OTHER SHORTLISTED QUOTES on this job, not against some absolute market. price_score is value for money — what the price actually buys — NOT simply the lowest number, so a cheap quote at a lower spec scores LOW. delivery_score is lead time plus how firm the commitment is. quality_score is specification, brand/material grade, warranty and completeness. If a dimension cannot be judged because the quote does not state it, score it 1 and say so in \"score_reason\" rather than guessing a middle value — an unstated warranty is a risk, not an average one. \"score_reason\" is ONE short plain sentence covering all three. \"track_record_note\" is one short plain sentence on that supplier's platform history and what it means for risk, or \"\" if there is nothing meaningful to say. \"line_findings\" is your line-by-line procurement read across the shortlisted quotes: each entry names the item or cost head and states the finding in one plain sentence with real numbers. Return [] when no quote is itemised. The \"quotes\" array must contain ONLY the shortlisted top 3 (or fewer if fewer exist). \"considered\" = how many quotes you evaluated in total. Be factual; never invent specs, prices or identities. All money is in AED. A quote may carry \"supplier_answers\": the supplier's own answers to points QuotesDone asked it to confirm; treat each as what that supplier now states for its quote. A brand written \"as the customer asked (shown after the reveal)\" is one the customer named: never guess its tier, origin or name.`;
const AR = `\n\nLANGUAGE: Write ALL human-readable text VALUES in this JSON — trade, shortlist_reason, bottom_line, overview, getting, includes, excludes, missing_from_request, spec_deviation, track_record_note, flags, line_findings.item, line_findings.finding, top3.why, top3.tradeoff, best_value_reason, watch_outs, advice — in clear, natural, professional Modern Standard Arabic. Do NOT translate the JSON keys. Keep the supplier labels exactly as \"Supplier A\", \"Supplier B\", etc. Keep all numbers and prices unchanged (AED).`;

Deno.serve(siteCors(observe('quote_compare', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const reqStart = Date.now();
  try {
    const body = await req.json().catch(() => ({} as any));
    const inquiry_id = String(body.inquiry_id || '');
    const langReq = String(body.lang || '').toLowerCase();
    let isAdmin = false; let cust: any = null;
    if (body?.__secret && (await requireInternal(admin, body.__secret, 'quote_compare')).ok) isAdmin = true;
    if (!isAdmin) {
      // The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An
      // admin whose session has one factor is answered 403 naming the step; a customer is looked up as before.
      const a = await adminCaller(admin, sec, req.headers.get('Authorization'));
      if (a.kind === 'two_step_required') return J(a.body, 403);
      if (a.kind === 'admin') isAdmin = true;
      else if (a.kind === 'not_admin') { const { data: c } = await admin.from('customers').select('id').eq('email', a.email).maybeSingle(); cust = c; }
    }
    if (!isAdmin && !cust) {
      if (body.__secret !== undefined) { await logRun('error', { bad_secret: 1, compared: 0 }, 'quote_compare rejected a caller presenting a wrong inbound secret (401) for inquiry ' + String(inquiry_id).slice(0, 60) + '. No quote comparison was produced, so the customer is left with raw quotes and no recommendation.'); }
      return J({ error: 'unauthorized' }, 401);
    }
    const { data: inq, error: inqErr } = await admin.from('inquiries').select('id,customer_id,status,summary,category,emirate,budget,raw_input,spec,boq,accepted_alternatives').eq('id', inquiry_id).maybeSingle();
    // A MALFORMED ID IS NOT A STALLED CUSTOMER (13 Aug 2026).
    //
    // This logged status='error' for ANY failure to load the inquiry and asserted, in every case,
    // that "the customer requested a comparison of their quotes and received a not_found instead —
    // they cannot act on the quotes they already paid attention to."
    //
    // In the 24 hours before this was written the only callers were the platform's own harnesses:
    // fx-1 and fx-2 at 01:59 and bbbbbbbb-2222-4bbb-8bbb-bbbbbbbbbbbb at 07:14 and 07:21. `fx-1` is
    // not a UUID, so Postgres refuses it with 22P02 before any row is looked for. There are 0
    // inquiries in the estate; there was no customer to strand. Seven error rows a day, aggregated
    // by the `it` watcher into "N agent run(s) failed in last 24h" — 459 of those incidents in 30
    // days, the single largest source of recommendations in the founder's queue.
    //
    // THE RESPONSE IS UNCHANGED — 404 not_found was always right, and the API contract is not the
    // defect. Only the run classification is. An id that cannot be a UUID is a caller mistake and
    // is recorded as such; a well-formed UUID with no row stays an error, because that one really
    // could be a customer whose inquiry has gone missing.
    if (!inq) {
      const malformed = /invalid input syntax for type uuid/i.test(String(inqErr?.message || ''));
      await logRun(malformed ? 'ok' : 'error',
        { compared: 0, inquiry_loaded: 0, ...(malformed ? { bad_request: 1 } : {}) },
        malformed
          ? ('quote_compare was called with "' + String(inquiry_id).slice(0, 60) + '", which is not a UUID, so no inquiry was looked for and 404 not_found was returned. That is a caller sending a malformed id — a harness or a stale link — and not a customer left unable to compare their quotes.')
          : ('quote_compare could not load inquiry ' + String(inquiry_id).slice(0, 60) + ' (' + String(inqErr?.message || 'no such row').slice(0, 120) + '), so the customer requested a comparison of their quotes and received a not_found instead — they cannot act on the quotes they already paid attention to.'));
      return J({ error: 'not_found' }, 404);
    }
    if (!isAdmin && inq.customer_id !== cust.id) { await logRun('error', { compared: 0, ownership_violation: 1 }, 'quote_compare blocked an ownership violation (403): a signed-in customer requested the quote comparison for inquiry ' + String(inquiry_id).slice(0, 60) + ' which belongs to a different customer. Anonymised competitor pricing was NOT disclosed.'); return J({ error: 'not_your_inquiry' }, 403); }
    // THE ANSWER'S LANGUAGE IS DECIDED BEFORE THE FIRST REFUSAL (customer-portal audit CP-03,
    // 22 Sep 2026). `need_two` used to be answered with an English `note` whatever the customer's
    // registered language, because the locale was resolved further down, after that branch.
    // No language asked for: the customer's REGISTERED language decides, never the script of the text
    // they typed (founder, 14 Sep 2026 - the registered language follows the whole workflow).
    const lang = (langReq === 'ar' || langReq === 'en') ? langReq : await registeredLocale(admin, { role: 'customer', customerId: inq.customer_id });
    const NEED_TWO = { en: 'Comparison needs at least two complete quotes.', ar: 'تحتاج المقارنة إلى عرضين مكتملين على الأقل.' };
    const MAX_COMPARE = 120;
    const MAX_ITEMS_PER_QUOTE = 40;
    const MAX_ITEMS_TOTAL = 1200;
    const { data: qsAll, error: qsErr } = await admin.from('quotes').select('id,supplier_id,option_no,quote_amount,price_ex_vat,gross_amount,discount_amount,vat_treatment,vat_amount,terms_spec,lead_time,validity,warranty,payment_terms,scope,conditions,exclusions,notes,status,source,extracted_by_model,expires_at,quality,submittable,created_at').eq('inquiry_id', inquiry_id).order('quote_amount', { ascending: true }).limit(MAX_COMPARE + 40);
    if (qsErr) { await logRun('error', { compared: 0, quotes_query_ok: 0, quotes_seen: 0 }, 'quote_compare could not read the quotes for inquiry ' + String(inquiry_id).slice(0, 60) + ' (' + String(qsErr.message).slice(0, 120) + '). The customer will be told they need at least two quotes even though suppliers may well have quoted — a query failure presented as an absence of quotes.'); }
    const live = (qsAll || []).filter((q: any) => isLiveQuote(q.status));
    // THE QUALITY CHECK (founder ledger 1018, 29 Sep 2026; scripts/sql/a_quote_is_checked_for_specs_prices_and_terms_
    // before_the_customer_sees_it.sql). A quote it holds is a draft, so it is not in `live`: it is COUNTED as on hold. A
    // quote released after its wait carries the check's flags (codes and numbers, no sentences), shown beside it in the
    // comparison until the supplier corrects them. Before the SQL is applied the table is absent and nothing is added.
    let qualityHeld = 0; let qualityHours = 24;
    // deno-lint-ignore no-explicit-any
    const qualityFlags: Record<string, any[]> = {};
    try {
      const { data: hs, error } = await admin.from('quote_quality_hold').select('quote_id,flags,held_at,release_due,released_at,release_reason,corrected_at,superseded_at').eq('inquiry_id', inquiry_id);
      if (!error) for (const h of (hs || [])) {
        const hrs = Math.round((new Date(h.release_due).getTime() - new Date(h.held_at).getTime()) / 3600000);
        if (Number.isFinite(hrs) && hrs > 0) qualityHours = hrs;
        if (!h.released_at && !h.superseded_at) qualityHeld++;   // a superseded hold is not open (supplier_api, review of #1108)
        else if (h.release_reason === 'waited_24h' && !h.corrected_at && Array.isArray(h.flags) && h.flags.length) qualityFlags[String(h.quote_id)] = h.flags;
      }
    } catch (_e) { /* no quality block */ }
    let qs = live.slice(0, MAX_COMPARE);
    if (!qs || qs.length < 2) { await logRun(qsErr ? 'error' : 'ok', { compared: 0, quotes_seen: qs.length, quotes_total_rows: (qsAll || []).length, need_two: 1, insufficient_genuine: qsErr ? 0 : 1, quotes_query_ok: qsErr ? 0 : 1 }, qsErr ? 'Customer asked to compare quotes and got \'need_two\' because the quotes query FAILED, not because too few suppliers quoted — real quotes may exist and are being hidden from the customer by a database error.' : ('Customer asked to compare quotes but only ' + qs.length + ' non-draft quote(s) exist for this RFQ, so no comparison was produced. This is genuine: suppliers have not returned enough quotes yet.')); return J({ ok: false, error: 'need_two', code: 'need_two', on_hold: qualityHeld, note: NEED_TWO[lang === 'ar' ? 'ar' : 'en'], message: NEED_TWO[lang === 'ar' ? 'ar' : 'en'] }, 409); }

    let itemsByQuote: Record<string, any[]> = {}; let itemsTotal = 0;
    const specOf: Record<string, Record<number, any>> = {};
    try {
      const { data: rows } = await admin.from('quote_items')
        .select('quote_id,line_no,description,brand,model,specification,qty,unit,unit_price,labour,install,commissioning,amount,country_of_origin,notes,spec,spec_source')
        .in('quote_id', qs.map((q: any) => String(q.id))).order('line_no', { ascending: true }).limit(MAX_ITEMS_TOTAL);
      for (const r of (rows || [])) {
        const k = String(r.quote_id); (itemsByQuote[k] ||= []);
        if (itemsByQuote[k].length >= MAX_ITEMS_PER_QUOTE) continue;
        // with spec_source: the ranking's re-check must see what the gate's reading wrote (reveal_guard.ts compareItem)
        itemsByQuote[k].push(compareItem(r));
        (specOf[k] ||= {})[r.line_no] = r.spec_source || null;
        itemsTotal++;
      }
    } catch (_e) { itemsByQuote = {}; }

    // ONLY COMPLETE QUOTES ARE RANKED (founder's hold rule, 14 Sep 2026). A quote missing a line spec,
    // a delivery date, installation or warranty where they apply, or its ex-VAT price never reaches
    // the ranking, the shortlist or either table — whatever its status column says. It is counted as
    // on hold and nothing else (line_specs/compare.ts rankable).
    // The predicate and the row mapping it needs now live in _shared/reveal_guard.ts, so this
    // ranking, my_inquiries and the reveal guard cannot drift on what "complete" means
    // (customer-portal audit CP-01, 22 Sep 2026).
    let heldAtRanking = 0;
    // The one verdict on "held" (reveal_guard.heldQuoteIds = line_specs assessQuote, what the hold desk releases on); the
    // roster below reads this set, never quotes.quality.pass (deterministic.ts rosterOf, 10 Nov 2026).
    let heldIds: Set<string> = new Set();
    {
      const held = heldQuoteIds(qs.map((q: any) => ({ quote: q, items: (itemsByQuote[String(q.id)] || []).map((it: any) => ({ ...it, line_no: it.line })) })), inq.category, inq.spec);
      heldIds = held; heldAtRanking = held.size; qs = qs.filter((q: any) => !held.has(String(q.id)));
    }
    // A SANCTIONED SUPPLIER'S QUOTE IS NEVER SHOWN (instruction 516), here as on the portal's cards (customer_api my_inquiries), so it
    // is neither ranked nor given a letter (15 Nov 2026, with the stored letters: a letter given to a quote the customer never sees
    // would leave a gap, A then C). The read fails closed: an unread ban list refuses, and the portal retries.
    try {
      const banned = await sanctionedLeads(admin, [...new Set(qs.map((q: any) => q.supplier_id).filter((x: unknown) => x != null))] as (string | number)[]);
      qs = qs.filter((q: any) => !banned.has(String(q.supplier_id)));
    } catch (e) {
      await logRun('error', { compared: 0, sanctions_unread: 1 }, 'quote_compare could not read the sanctions list (' + String((e as Error)?.message || e).slice(0, 120) + '), so no comparison was served rather than one that might show a banned supplier; the portal retries.');
      return J({ ok: false, error: 'try_again', code: 'try_again', retry: true, message: lang === 'ar' ? 'يُرجى المحاولة بعد قليل.' : 'Please try again in a moment.' }, 503);
    }
    // BEING CHECKED (review of 16 Nov 2026, hole 5 through compare; _shared/quotes_being_checked.ts). While the accountant's
    // customer_matches_supplier flag names this request, its quotes are not ranked, lettered, priced or benchmarked here, as on
    // the portal's cards, whoever asks (the customer's JWT, or customer_api for compare_pdf / compare_csv / the Arabic report):
    // they go to the same customer. A quote he already paid to reveal stays his. Unreadable: refuse, the portal retries.
    let beingChecked: Set<string> = new Set();
    try {
      beingChecked = await withheldWhileChecked(admin, inq.customer_id ? String(inq.customer_id) : null, String(inquiry_id), qs.map((q: any) => String(q.id)));
      qs = qs.filter((q: any) => !beingChecked.has(String(q.id)));
    } catch (e) {
      await logRun('error', { compared: 0, being_checked_unread: 1 }, 'quote_compare could not read whether this request\'s quotes are being checked (' + String((e as Error)?.message || e).slice(0, 120) + '), so no comparison was served rather than one that might show a rival\'s price to a supplier posing as a customer; the portal retries.');
      return J({ ok: false, error: 'try_again', code: 'try_again', retry: true, message: lang === 'ar' ? 'يُرجى المحاولة بعد قليل.' : 'Please try again in a moment.' }, 503);
    }
    if (qs.length < 2) {
      await logRun('ok', { compared: 0, quotes_seen: qs.length, held_at_ranking: heldAtRanking, being_checked: beingChecked.size, need_two: 1 }, 'Customer asked to compare quotes but only ' + qs.length + ' complete quote(s) exist for this RFQ (' + heldAtRanking + ' more are on hold for missing details, ' + beingChecked.size + ' being checked), so no comparison was produced.');
      return J({ ok: false, error: 'need_two', code: 'need_two', on_hold: heldAtRanking + qualityHeld, being_checked: beingChecked.size, note: NEED_TWO[lang === 'ar' ? 'ar' : 'en'], message: NEED_TWO[lang === 'ar' ? 'ar' : 'en'] }, 409);
    }

    const trackBySupplier: Record<string, any> = {};
    // The supplier's own name, read with its track record: never output, only searched for in its own words (ledger 1589).
    const nameBySupplier: Record<string, string> = {};
    try {
      const supIds = [...new Set(qs.map((q: any) => q.supplier_id).filter((x: any) => x != null))];
      if (supIds.length) {
        const yr = new Date().getFullYear();
        const { data: ls } = await admin.from('leads').select('id,app_rating,app_reviews,verified,founded_year,company_name').in('id', supIds);
        for (const l of (ls || [])) if (l.company_name) nameBySupplier[String(l.id)] = String(l.company_name);
        for (const l of (ls || [])) {
          const appN = Number(l.app_reviews || 0);
          // A RATING IS EARNED HERE OR IT DOES NOT EXIST (founder, 9 Sep 2026): "google review
          // shouldnt be counted". This fell back to leads.rating ?? rating_maps — the Google Maps
          // star scraped before the supplier ever registered — and fed it into the comparison
          // report the customer pays a 3% reveal fee to read. Nobody has ever been rated on
          // QuotesDone, so that scraped number WAS the track record on every report ever produced.
          const ratingValue = (appN > 0 && l.app_rating != null) ? Number(l.app_rating) : null;
          const reviewCount = appN;
          // THE COMPARISON IS READ BEFORE THE REVEAL (supplier-reviews audit, 10 Nov 2026, customer_support): the model was
          // handed the exact rating, review count and years trading, and its track_record_note is printed in the
          // comparison the customer reads before paying, "4.6 stars, 23 reviews, trading since 2011" being the fingerprint
          // customer_api already bands (_shared/pre_reveal_bands.ts). It now reads the same bands; the win rate and
          // jobs won, which customer_api withholds until a transaction exists, are withheld here too.
          trackBySupplier[String(l.id)] = {
            rating: ratingBand(ratingValue), review_count: reviewCountBand(reviewCount),
            rating_source: ratingValue != null ? 'QuotesDone jobs' : null,
            rating_note: ratingValue != null ? null : 'Not yet rated on QuotesDone',
            verified: !!l.verified,
            years_active: l.founded_year ? yearsBand(Math.max(0, yr - Number(l.founded_year))) : null };
        }
      }
    } catch (_e) { /* track record is optional */ }

    const nowTs = Date.now();
    // "Supplier A – Option 1" (founder, 14 Sep 2026: options are separate quotations of one supplier). The letters are the ones
    // STORED the first time the customer was shown each supplier (_shared/quote_labels.ts, 15 Nov 2026), so the comparison calls a
    // supplier what its quotation PDF and its portal card call it (journey A: the PDFs said A and A, this said B and A). The
    // comparison SHOWS every quote it ranks, so a supplier seen here first is lettered here. A letter that cannot be read or
    // recorded is never guessed (this fell back to arrival by created_at, review REVIEW_plain item 2): the comparison refuses and
    // the portal retries, because its labels are written into the cached analysis.
    const lettersRead = await recordShown(admin, new Map([[String(inquiry_id), qs]]), 'comparison');
    const labels = labelQuotes(qs, lettersRead?.get(String(inquiry_id)) ?? new Map(), live);
    if (!lettersRead || !qs.every((q: any) => labels.has(String(q.id)))) {
      await logRun('error', { compared: 0, letters_unread: 1, quotes_seen: qs.length, lettered: labels.size }, 'quote_compare could not read or record the supplier letters, so no comparison was served rather than one under guessed letters; the portal retries.');
      return J({ ok: false, error: 'try_again', code: 'try_again', retry: true, message: lang === 'ar' ? 'يُرجى المحاولة بعد قليل.' : 'Please try again in a moment.' }, 503);
    }
    // THE TECHNICAL COMPARISON — line by line, attribute by attribute, against what the customer
    // asked for; held quotes are counted, never shown. Rebuilt on every answer, cached or not.
    let onHold = 0;
    try { const { count } = await admin.from('quote_spec_hold').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiry_id).in('state', ['open', 'awaiting_approval']); onHold = (count || 0) + heldAtRanking + qualityHeld; } catch (_e) { onHold = heldAtRanking + qualityHeld; }
    // deno-lint-ignore no-explicit-any
    const inqSpec: any = inq.spec;
    // deno-lint-ignore no-explicit-any
    const requestLines = ((inq.boq && Array.isArray((inq.boq as any).boq)) ? (inq.boq as any).boq : []).map((b: any, i: number) => ({ line_no: i + 1, description: String(b?.description || ''), qty: b?.qty ?? null, unit: b?.unit ?? null }));
    let technical: TechnicalComparison | null = null;
    try {
      // What the customer accepted when no supplier quoted their exact spec is their request now
      // (founder_instruction #321): a quote offering it matches instead of being shown as a deviation.
      // deno-lint-ignore no-explicit-any
      const accepted = (Array.isArray((inq as any).accepted_alternatives) ? (inq as any).accepted_alternatives : []).map((x: any) => ({ line_no: Number(x?.line_no), attr: String(x?.attr || ''), accepted: String(x?.accepted || '') }));
      technical = technicalComparison({ category: inq.category, request_lines: requestLines, requirements: requirementsOf(inqSpec), on_hold: onHold, now: new Date(), accepted,
        quotes: qs.map((q: any) => { const lab = labels.get(String(q.id))!; return { quote_id: String(q.id), label_en: lab.en, label_ar: lab.ar, supplier_letter: lab.letter, option_no: lab.option_no,
          lines: (itemsByQuote[String(q.id)] || []).map((it: any) => ({ line_no: it.line, description: String(it.description || ''), brand: it.brand, model: it.model, specification: it.specification, qty: it.qty, unit: it.unit, unit_price: it.unit_price, labour: it.labour, install: it.install, amount: it.amount, notes: it.notes, spec: it.spec, spec_source: specOf[String(q.id)]?.[it.line] ?? null })),
          terms: { lead_time: q.lead_time, warranty: q.warranty, scope: q.scope, exclusions: q.exclusions, conditions: q.conditions, notes: q.notes, terms_spec: q.terms_spec, price_ex_vat: comparedPrice(q) } }; }) });
    } catch (e) { await logRun('error', { technical_comparison_failed: 1 }, 'quote_compare could not build the technical comparison (' + String((e as Error)?.message || e).slice(0, 160) + '); the ranking is served without it.'); }
    // SPEC MATCH ON THE ROUTINE CLASS (24 Sep 2026, _shared/routine_judgements.ts). Code decided which cells are not an exact match (≠);
    // whether each ≠ is a GENUINE mismatch (SS304 quoted for SS316) is judged by the routine class (google/gemini-3.8-flash). This function only
    // enqueues the cells (idempotent per quote and cell set) and reads what is already judged; resilience_ping judges
    // the queue (no per-day limit). A cell not judged yet is reported as pending, never guessed.
    // deno-lint-ignore no-explicit-any
    const specMismatches: Record<string, any> = {};
    if (technical) {
      for (const q of qs) {
        const qid = String(q.id);
        try {
          const keep: string[] = [];
          for (const cells of chunks(differingCells(technical, qid))) {
            const key = qid + ':' + (await sha256hex(JSON.stringify(cells))).slice(0, 32); keep.push(key);
            await admin.rpc('fn_routine_judgement_enqueue', { p_kind: 'quote_spec_match', p_subject_key: key, p_input: { quote_id: qid, inquiry_id, cells } });
          }
          // The cells of this run are the quote's cells now: anything older (a cell since corrected) stops counting.
          await admin.rpc('fn_routine_quote_spec_supersede', { p_quote_id: qid, p_keep: keep });
          const { data } = await admin.rpc('fn_quote_spec_mismatches', { p_quote_id: qid });
          if (data) specMismatches[qid] = data;
        } catch (_e) { /* the report is served without the judged cells; the queue retries */ }
      }
    }
    // THE SALES ENGINEER'S REVIEW (founder ledger 1588, 10 Nov 2026): each quote against what the customer asked for,
    // by code, from the RAW lines (the brand the customer named is compared with the brand quoted); and the context
    // each quote's own words are generalised with — its brand / model values and its supplier's name (ledger 1589).
    const ctxByQuote: Record<string, GeneraliseCtx> = {};
    const notesByQuote: Record<string, ReviewNote[]> = {};
    {
      const request = requestOf(inq, new Date(nowTs));
      for (const q of qs) {
        const qid = String(q.id); const items = itemsByQuote[qid] || [];
        const names = q.supplier_id != null && nameBySupplier[String(q.supplier_id)] ? [nameBySupplier[String(q.supplier_id)]] : [];
        ctxByQuote[qid] = ctxOfQuote(items, names);
        try { notesByQuote[qid] = reviewNotes({ request, quote: q, lines: items.map((it: any) => ({ ...it, line_no: it.line })), supplierNames: names }); } catch (_e) { notesByQuote[qid] = []; }
      }
    }
    const allCtx = mergeCtx(...Object.values(ctxByQuote));
    // WHAT HE ASKED FOR, QUOTE BY QUOTE (request_fit.ts): the brand each supplier quoted is compared with the brands he
    // named HERE, on the raw lines, before anything is generalised; only "one of your listed brands: yes / no" and the
    // brand's tier and origin leave. Recomputed on every answer, cached or not.
    const requirements = requestRequirements(inq);
    const fitById: Record<string, QuoteFit> = {};
    if (requirements.length) {
      const trade = tradeOfCategory(inq.category); const siteVisit = siteVisitAsked(inq.spec);
      for (const q of qs) {
        const qid = String(q.id);
        // The date cell shows the GENERALISED lead time (review item 8): the raw text can name a brand or a stock location.
        const leadShown = generaliseQuoteTerms({ lead_time: q.lead_time }, ctxByQuote[qid]).lead_time ?? null;
        try { fitById[qid] = fitQuote(requirements, { quote: { ...q, lead_time_shown: leadShown }, lines: (itemsByQuote[qid] || []).map((it: any) => ({ ...it, line_no: it.line })), now: new Date(nowTs), trade, site_visit: siteVisit }); } catch (_e) { /* the comparison is served without this quote's fit */ }
      }
      // HIS ANSWER COMES BACK (CEO, ruling 1696; final review FIX 1): what each supplier answered to a point, read from its
      // quotation conversation on every view, generalised and scrubbed of anything that names a party, joins that point.
      const asking = qs.filter((q: any) => fitById[String(q.id)]?.asks.length && q.supplier_id != null);
      if (asking.length) {
        try {
          const { data: rvs } = await admin.from('quote_reviews').select('id,supplier_id').eq('inquiry_id', inquiry_id).in('supplier_id', [...new Set(asking.map((q: any) => q.supplier_id))]);
          const reviewOf = new Map((rvs || []).map((r: any) => [String(r.supplier_id), String(r.id)]));
          const { data: pts } = reviewOf.size ? await admin.from('quote_review_request').select('review_id,key,state,answered_message_id').in('review_id', [...reviewOf.values()]).eq('code', POINT_CODE) : { data: [] };
          const msgIds = [...new Set((pts || []).filter((p: any) => p.state === 'answered' && p.answered_message_id).map((p: any) => String(p.answered_message_id)))];
          const { data: msgs } = msgIds.length ? await admin.from('quote_review_messages').select('id,role,body').in('id', msgIds) : { data: [] };
          const said = new Map((msgs || []).filter((m: any) => m.role === 'supplier').map((m: any) => [String(m.id), String(m.body ?? '')]));
          for (const q of asking) {
            const qid = String(q.id); const rid = reviewOf.get(String(q.supplier_id)); if (!rid) continue;
            const name = nameBySupplier[String(q.supplier_id)];
            const shown = (raw: string) => { let t = generaliseQuoteTerms({ notes: raw }, ctxByQuote[qid]).notes ?? ''; const re = name ? knownNameRe(name) : null; if (re) t = t.replace(re, 'the supplier'); return scrubIdentityText(t, '[removed]').trim().slice(0, 600) || null; };
            const answers: Record<string, { state: 'asked' | 'answered' | 'closed'; answer: string | null }> = {};
            for (const p of (pts || []).filter((x: any) => String(x.review_id) === rid)) {
              const body = p.answered_message_id ? said.get(String(p.answered_message_id)) : undefined;
              // superseded: the customer revealed a supplier or the request ended before an answer (COMPARE4 gap 2)
              answers[String(p.key)] = p.state === 'answered' && body ? { state: 'answered', answer: shown(body) }
                : p.state === 'superseded' ? { state: 'closed', answer: null } : { state: 'asked', answer: null };
            }
            fitById[qid] = withAnswers(fitById[qid], answers);
          }
        } catch (_e) { /* the points are served as asked; the next view reads the answers */ }
      }
      // THE OPEN POINTS GO TO THE SALES ENGINEER (CEO, ruling 1696; final review FIX 1; request_fit.ts pointsHandoff). Code
      // writes no engineer message: ONE hand-over per quote through public.fn_seat_handoff, whose handler records the points
      // in the supplier's quotation conversation in the same transaction, where the sales engineer's model turns raise them.
      // Never once a supplier is revealed on this request or the request is closed (FIX 1 iv); never twice for one quote.
      if (body.technical_only !== true && asking.length) {
        let revealedAny = false;
        try { const { data: tx } = await admin.from('transactions').select('id').eq('inquiry_id', inquiry_id).not('revealed_at', 'is', null).limit(1); revealedAny = !!(tx && tx.length); } catch (_e) { revealedAny = true; }
        if (mayRaisePoints(inq, revealedAny)) for (const q of asking) {
          const qid = String(q.id);
          const args = pointsHandoff(fitById[qid], { inquiry_id: String(inquiry_id), quote_id: qid, label: labels.get(qid)?.en ?? '' });
          if (!args) continue;
          try { await admin.rpc('fn_seat_handoff', args); } catch (_e) { /* the points stay listed; the next view files them */ }
        }
      }
    }
    const fitByLabel: Record<string, QuoteFit> = Object.fromEntries(qs.filter((q: any) => fitById[String(q.id)]).map((q: any) => [labels.get(String(q.id))?.en ?? '', fitById[String(q.id)]]));
    const labelled = qs.map((q: any) => {
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
      // What the model and the ranking read is what the customer may read: the quote's words generalised (ledger 1589).
      const qctx = ctxByQuote[String(q.id)] || {};
      const items = (itemsByQuote[String(q.id)] || []).map((it: any) => generaliseLine(it, qctx));
      const gt = generaliseQuoteTerms({ lead_time: q.lead_time, validity: q.validity, warranty: q.warranty, payment_terms: q.payment_terms, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, notes: q.notes }, qctx);
      const tr = q.supplier_id != null ? trackBySupplier[String(q.supplier_id)] : null;
      return { label: labels.get(String(q.id))!.en, price: comparedPrice(q), gross_amount: q.gross_amount ?? null, discount_amount: q.discount_amount ?? null, vat_treatment: q.vat_treatment ?? null, vat_amount: q.vat_amount ?? null, lead_time: gt.lead_time, validity: gt.validity, warranty: gt.warranty, payment_terms: gt.payment_terms, scope: gt.scope, conditions: gt.conditions, exclusions: gt.exclusions, notes: gt.notes,
        items: items.length ? items : undefined,
        review_notes: notesByQuote[String(q.id)] || [],
        fit: fitById[String(q.id)] ?? null,
        itemised: items.length > 0,
        expired: q.expires_at ? (new Date(q.expires_at).getTime() < nowTs) : false,
        source: q.source || 'form',
        completeness: ql ? { score: ql.score ?? null, passed: ql.pass ?? null, missing_mandatory: missMandatory } : undefined,
        track_record: tr || undefined };
    });
    // Every live quote with its place (see rosterOf). Recomputed on every answer, cached or not,
    // so it always reflects the quotes as they are now; it is never part of the model's input.
    // deno-lint-ignore no-explicit-any
    // UAE PRICE BENCHMARKS (founder instruction 1009, upgrade 4). Plain code in the database
    // (scripts/sql/uae_price_benchmarks_come_only_from_real_quotes.sql): each priced line is judged against
    // the median / IQR of real quotes on OTHER enquiries (>= 5 quotes, >= 3 suppliers, demo excluded), and
    // says why when it is well above or below. Until real data exists every line reads no_benchmark_yet.
    // Not applied yet -> the rpc errors and the comparison simply carries no benchmark block.
    let priceBenchmarks: any[] | null = null;
    try { const { data, error } = await admin.rpc('fn_price_benchmark_flags_for_inquiry', { p_inquiry_id: inquiry_id }); if (!error && Array.isArray(data)) priceBenchmarks = data.filter((b: any) => !beingChecked.has(String(b?.quote_id))); } catch (_e) { priceBenchmarks = null; }
    // the check's flags beside each quote released after its wait, under the label the customer sees (ledger 1018)
    const qualityCheck = { held: qualityHeld, hours: qualityHours,
      notes: qs.filter((q: any) => qualityFlags[String(q.id)]).map((q: any) => ({ quote_id: String(q.id), label: labels.get(String(q.id))?.en ?? null, label_ar: labels.get(String(q.id))?.ar ?? null, flags: qualityFlags[String(q.id)] })) };
    // THE LAST GATE BEFORE THE CUSTOMER (founder ledger 1589, 10 Nov 2026). Everything this function returns — the
    // model's prose, a cached analysis written before this rule, the technical table's cells, the judged spec cells,
    // the roster — is generalised against every quote's brand / model values and supplier names, so a brand the model
    // echoed or a model code in a cell never reaches the screen, the PDF or the CSV. The review notes are attached
    // after it: they are written generic, and they quote the customer's own request.
    // The rules ranking of the same quotes: enforceFit takes from it which quote is best within a tier, and a row for a quote it
    // pulls into the model's shortlist (review item 5). Code only, no model.
    const rulesForFit = requirements.length ? deterministicCompare(labelled as never, lang as 'en' | 'ar') : null;
    const priceByLabel: Record<string, number | null> = Object.fromEntries(labelled.map((l: any) => [String(l.label), l.price ?? null]));
    const expiredByLabel: Record<string, boolean> = Object.fromEntries(labelled.map((l: any) => [String(l.label), !!l.expired]));
    const hiddenPhrases = qs.map((q: any) => hiddenBrandPhrases(fitById[String(q.id)], (itemsByQuote[String(q.id)] || []), tradeOfCategory(inq.category)));
    const withRoster = (a: any) => { if (a && typeof a === 'object') { a.price_benchmarks = priceBenchmarks; a.technical = technical ? annotateTechnical(rendererView(technical, lang as 'en' | 'ar'), requirements, fitByLabel, technical.trade, lang as 'en' | 'ar') : null;
      a.request_fit = requirements.length ? fitView(requirements, qs.filter((q: any) => fitById[String(q.id)]).map((q: any) => ({ label: labels.get(String(q.id))?.en ?? '', quote_id: String(q.id), fit: fitById[String(q.id)] }))) : null;
      enforceFit(a, fitByLabel, lang as 'en' | 'ar', { rules: rulesForFit, prices: priceByLabel, expired: expiredByLabel }); a.technical_detail = technical; a.spec_mismatches = specMismatches; a.on_hold = onHold; a.quality_check = qualityCheck; a.all_quotes = rosterOf(labelled.map((l: any, i: number) => ({ ...l, quote_id: String(qs[i].id) })), Array.isArray(a.top3) ? a.top3 : [], heldIds); if (typeof a.total_quotes !== 'number') a.total_quotes = live.length; }
      if (!a || typeof a !== 'object') return a;
      // Ledger 1588: a listed brand whose tier and origin would name it is said nowhere in the analysis (request_fit.ts).
      const g = generaliseDeep(a, allCtx);
      g.review_notes = qs.map((q: any) => ({ quote_id: String(q.id), label: labels.get(String(q.id))?.en ?? null, label_ar: labels.get(String(q.id))?.ar ?? null,
        notes: (notesByQuote[String(q.id)] || []).map((n) => ({ code: n.code, severity: n.severity, line_no: n.line_no, text: lang === 'ar' ? n.ar : n.en, en: n.en, ar: n.ar })) }));
      // Ledger 1588, last: a listed brand whose tier and origin would name it is said nowhere in what is returned, the review
      // notes included (request_fit.ts hideBrandPhrases).
      return hideBrandPhrases(g, hiddenPhrases); };
    const qhash = await sha256hex(JSON.stringify(labelled));
    // A LARGE JOB'S TOP THREE IS A HIGH-STAKES SUPPLIER CHOICE (29 Sep 2026, founder_instruction 1009 upgrade 10): the CEO
    // reviews it on another model family before the customer sees it. While the model hold is on it is shown and the
    // review is owed; after the lift a recommendation the CEO has not agreed to is withheld (every quote stays listed).
    const largest = Math.max(0, ...qs.map((q: any) => comparedPrice(q) ?? (Number(q.quote_amount) || 0)));
    let authorModel: string | null = null;
    const gated = async (a: any, model: string | null) => {
      if (largest < LARGE_SUPPLIER_CHOICE_AED || !a || !Array.isArray(a.top3) || a.top3.length === 0) return a;
      const g = await challengeBeforeDeciding(admin, {
        kind: 'supplier_choice', seat: 'sales_engineer', subject: { table: 'inquiries', id: String(inquiry_id) + ':' + qhash.slice(0, 16) },
        question: 'Which three of these quotations should QuotesDone recommend to the customer for this job?',
        evidence: { trade: inq.category ?? null, emirate: inq.emirate ?? null, quotes: qs.length, largest_quote_aed: largest },
        proposal: { top3: a.top3, best_value: a.best_value_label ?? null, shortlist_reason: a.shortlist_reason ?? null },
        authorModel: model, authorTaskClass: model && model !== 'deterministic' ? 'quote_comparison' : null,
      });
      a.second_seat = { state: g.state, owed: g.owed ?? false, deliberation_id: g.deliberation_id ?? null };
      if (!g.proceed) {
        a.top3 = []; a.on_review = true;
        a.review_note = lang === 'ar' ? 'توصيتنا قيد المراجعة الداخلية، وتجدون جميع العروض أدناه.' : 'Our recommendation is under internal review; every quote is listed below.';
      }
      return a;
    };
    // THE SPEC SWEEP NEEDS NO MODEL (22 Sep 2026). sales_engineer's spec_offer_sweep reads only
    // technical_detail, which is computed above by code. It used to run the full model comparison
    // on every candidate, every resilience tick, to throw everything but that field away.
    if (body.technical_only === true) {
      await logRun('ok', { compared: 0, technical_only: 1, quotes_seen: qs.length, lang }, 'Technical comparison for ' + qs.length + ' quotes served by code for the no-exact-spec sweep; no model was asked.');
      return J({ ok: true, technical_only: true, analysis: withRoster({}) });
    }
    // A FAILED COMPARISON IS CACHED TOO (22 Sep 2026). The cache held successes only, "so the model
    // result wins the moment the model works again" - which also meant a failing input re-ran the
    // whole ladder on every mount of the compare card (CustomerPortal.tsx Comparison, deps
    // [inqId, lang]). A failure is now stored for this exact (inquiry, quotes hash, language) with a
    // retry-after that starts at 15 minutes and doubles per consecutive failure, capped at a day
    // (_shared/spend_guards.ts). Until then the customer is served the same deterministic ranking a
    // failure serves, at no cost; a changed quote set is a new hash and is compared at once.
    let priorFailure: unknown = null;
    try {
      const { data: cached } = await admin.from('qd_compare_cache').select('analysis').eq('inquiry_id', inquiry_id).eq('quotes_hash', qhash).eq('lang', lang).maybeSingle();
      if (isCachedAnalysis(cached?.analysis)) { await logRun('ok', { compared: 1, quotes_seen: qs.length, cached: 1, lang }, 'Quote comparison for ' + qs.length + ' quotes served from cache; the customer got their recommendation with no model call.'); return J({ ok: true, analysis: await gated(withRoster(cached!.analysis), null), cached: true }); }
      priorFailure = cached?.analysis ?? null;
      const held = activeFailure(priorFailure);
      if (held) {
        const analysis = deterministicCompare(labelled as never, lang as 'en' | 'ar');
        await logRun('ok', { compared: 1, degraded: 1, cached_failure: 1, failures: held.count, quotes_seen: qs.length, top3: analysis.top3.length, lang }, 'The model comparison for these ' + qs.length + ' quotes failed ' + held.count + ' time(s) (' + held.detail.slice(0, 80) + '); until ' + held.retry_after + ' the customer is served the deterministic ranking and no model is asked again.');
        return J({ ok: true, analysis: await gated(withRoster(analysis), 'deterministic'), degraded: true, cached_failure: true, retry_after: held.retry_after, detail: held.detail });
      }
    } catch (_e) { /* */ }
    const rememberFailure = async (detail: string) => { try { await admin.from('qd_compare_cache').upsert({ inquiry_id, quotes_hash: qhash, lang, analysis: failureRecord(priorFailure, detail), created_at: new Date().toISOString() }); } catch (_e) { /* the next view simply tries again */ } };
    const boqItems = (inq.boq && Array.isArray((inq.boq as any).boq)) ? (inq.boq as any).boq.map((b: any) => `${b.description || ''}${b.qty ? ' ('+b.qty+' '+(b.unit||'')+')' : ''}`).slice(0, 40) : [];
    const cref = await sec('compliance_ref');
    // NEW v21: QuotesDone's own curated expertise for this trade (market prices, red flags, spec hierarchy, must-state specs).
    let expertRef = ''; let mustSpecs: string[] = [];
    try { const { data: er } = await admin.rpc('fn_category_expert_ref', { p_category: inq.category }); if (er) expertRef = String(er); } catch (_e) { /* optional */ }
    try { const { data: grp } = await admin.rpc('fn_quote_spec_group', { p_category: inq.category });
      if (grp) { const { data: specs } = await admin.from('category_quote_specs').select('label').eq('spec_group', grp).eq('mandatory', true); mustSpecs = (specs || []).map((s: any) => String(s.label)); } } catch (_e) { /* optional */ }
    const payload: Record<string, unknown> = { job: { summary: inq.summary, category: inq.category, emirate: inq.emirate, budget: inq.budget, requested_details: inq.raw_input || '', requested_spec: inq.spec || {}, requested_items: boqItems },
      // Ledger 1588 (final review FIX 2b): a hidden listed brand's tier and origin are not in what the model reads.
      quotes: labelled.map(({ fit, ...l }: any, i: number) => hideBrandForModel({ ...l, review_notes: (l.review_notes || []).map((n: ReviewNote) => (lang === 'ar' ? n.ar : n.en)),
        // what he asked for, against this quote (request_fit.ts): a quote that fails one is not recommended over one that meets them all
        meets_your_request: fit ? Object.entries(fit.cells).map(([code, c]: [string, any]) => { const r = requirements.find((x) => x.code === code); return { requirement: r ? r.label[lang === 'ar' ? 'ar' : 'en'] : code, asked: r ? r.asked[lang === 'ar' ? 'ar' : 'en'] : null, hard: !!r?.hard, status: c.status, quote: c.shown[lang === 'ar' ? 'ar' : 'en'] }; }) : undefined,
        // the supplier's own answers to the points QuotesDone asked him to confirm (request_fit.ts withAnswers)
        supplier_answers: fit ? fit.asks.filter((x: any) => x.state === 'answered' && x.answer).map((x: any) => ({ point: lang === 'ar' ? x.ar : x.en, answer: x.answer })) : undefined }, hiddenPhrases[i])) };
    if (cref) payload.compliance_reference = cref;
    if (expertRef) payload.expert_reference = expertRef;
    if (mustSpecs.length) payload.must_state_specs = mustSpecs;
    // the job's own words and every quotation's text in the payload are data, never instructions (untrusted.ts, 3 Nov 2026)
    const sys = SYS + '\n\n' + DATA_NOT_INSTRUCTIONS + (lang === 'ar' ? AR : '');
    const key = await sec('cred_fn_ai'); if (!key) { await logRun('error', { compared: 0, quotes_seen: qs.length, ai_key_present: 0 }, 'quote_compare aborted: the cred_fn_ai credential is missing, so ' + qs.length + ' real supplier quotes could not be compared. The customer is shown \'ai_unavailable\' at the exact moment they are trying to choose a supplier, and the RFQ stalls at the decision step.'); return J({ ok: false, error: 'ai_unavailable', code: 'ai_unavailable' }, 503); }
    let parsed: any = null; let lastDetail = '';
    let attempts = 0;
    // 5 Aug 2026. This asked for 4200 tokens and declared no patience, so the gateway applied its
    // 55s no-declaration default. Measured against deployed staging, the real output of this
    // contract is 2643-3929 tokens and 26-90s: the 3000-token policy ceiling sat INSIDE the natural
    // output range (intermittent truncation) and the 55s wall aborted every run that generated more
    // than ~3000 tokens. Both ceilings produced the same symptom - 'parse_failed' at the customer's
    // decision step - which is why it read as model flakiness. Declare the real patience and never
    // start an attempt that cannot land inside the platform request ceiling.
    // Measured wall at the 10000-token budget: 33s (2 quotes EN) to 67s (3 quotes AR).
    const COMPARE_WALL_MS = 140000;
    // ONE GATEWAY REQUEST (22 Sep 2026). This looped twice over a gateway that itself tried two
    // attempts on each of two models - up to eight provider calls at 10,000 output tokens each for
    // one card view. The gateway now bounds a request at two paid calls across its ladder, so a
    // second loop here only multiplied that; the failure is cached instead of re-asked.
    // `subject` lets the gateway recognise our own ZZ DEMO inquiries and answer them for nothing.
    {
      // The request's own clock. T0 is module scope, so on a warm worker it is the worker's age,
      // not this request's: the wall would read as spent and the call would go out with no time.
      const leftMs = COMPARE_WALL_MS - (Date.now() - reqStart);
      // THE COMPARISON IS NEVER ON THE READER'S FAMILY (founder instruction ~891, 23 Sep 2026). quote_comparison is a
      // review class over document_extraction; its authors are the models that read these quotations. A typed quote has
      // none ('deterministic'); an upload with no recorded reader is 'unknown', and the gateway then answers "no
      // independent reviewer", so the customer gets the deterministic ranking below rather than a same-family verdict.
      const authors = [...new Set(qs.map((q: any) => typeof q.extracted_by_model === 'string' && q.extracted_by_model
        ? q.extracted_by_model : (q.source === 'upload' ? 'unknown' : 'deterministic')))].sort().join(',');
      try {
        attempts++;
        const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'quote_compare', subject: { inquiry_id, customer_id: inq.customer_id }, counterpart_model: authors, sys, input: JSON.stringify(payload), max: 10000, temperature: 0.2, client_timeout_ms: Math.min(leftMs, 100000) }) });
        const jd = await r.json().catch(() => null);
        const model = String(jd?.model || 'ai_gateway');
        if (jd?.model) authorModel = String(jd.model);
        const content = r.ok ? (jd?.content || '') : '';
        const p = content ? parseJson(content) : null;
        if (!r.ok) lastDetail = 'http' + (r.status) + ':' + model + ':' + String(jd?.outcome || '') + ':' + (JSON.stringify(jd?.error || '').slice(0, 140));
        else if (!content) lastDetail = 'empty:' + model + ':' + String(jd?.outcome || '');
        else if (p) parsed = p;
        // A cut-off reply and a badly-formatted reply are different defects with different fixes.
        // Say which one this was: 'parse:model:truncated@3000' points at model_policy, plain
        // 'parse:model' points at the prompt.
        else lastDetail = 'parse:' + model + (jd?.truncated ? ':truncated@' + jd?.max_tokens + ' (used ' + jd?.output_tokens + ')' : '');
      } catch (e) { lastDetail = 'exc:' + String((e as Error)?.message || e).slice(0, 100); }
    }
    // A REFUSAL IS A REFUSAL, AND IT FAILS CLOSED (23 Sep 2026, founder_instruction 841).
    // quote_comparison is the revenue event: the customer pays 3% of the quote he reveals, and
    // this class decides which supplier is ranked first. The model moved from sonnet-5 to
    // qwen3.8-max (841) and then to gpt-5.6-sol (854), neither measured on this estate. The failure that costs the
    // customer money is not a crash — it is a model handed two quotations whose scopes do not
    // overlap, inventing a common basis and ranking them anyway. That looks like a helpful
    // answer and is a wrong recommendation somebody pays for.
    //
    // So the contract now has a refusal (see SYS, "WHEN THE QUOTES CANNOT BE COMPARED"), and a
    // refusal is honoured here rather than in the prompt alone: the ranking keys are STRIPPED, so
    // a model that sets not_comparable AND fills top3 cannot have its ranking reach the customer.
    // Same shape as drawing_redact's NO_ANSWER set — an answer that says "I could not do this
    // safely" never becomes a published result.
    if (parsed && typeof parsed === 'object' && parsed.not_comparable === true) {
      const why = String(parsed.not_comparable_reason || '').trim();
      const ranked = Array.isArray(parsed.top3) ? parsed.top3.length : 0;
      parsed.top3 = [];
      parsed.best_value_label = null;
      parsed.cheapest_label = null;
      parsed.best_value_reason = '';
      await logRun('ok', { compared: 1, quotes_seen: qs.length, not_comparable: 1, ranking_stripped: ranked ? 1 : 0, lang },
        'The comparison refused to rank these ' + qs.length + ' quotes because they are not comparable' +
        (why ? ' (' + why.slice(0, 160) + ')' : '') +
        (ranked ? ' — and it had ranked them anyway, so the ranking was stripped before the customer saw it.'
                : '. The customer is shown why, and no top 3.'));
    }

    // MODEL-FREE FALLBACK. This used to return {ok:false,'parse_failed'} at HTTP 200 and the
    // customer, standing at the decision step, was shown nothing at all. Every model attempt
    // failing is not a rare edge: the whole company runs on ONE OpenRouter balance, so when it
    // empties this branch is the ONLY branch. A rules-only ranking off the figures the suppliers
    // actually stated is worth incomparably more than an empty screen, and it costs nothing.
    // The failure IS cached, with a short retry-after (see rememberFailure): the model result still
    // wins as soon as the model works again, without every card view paying to find out.
    const degradedBecause = (why: string) => {
      // deterministicCompare sets its own closing paragraph: DISCLAIMER_* claims a match "on
      // specification", which a rules ranking never assesses.
      const analysis = deterministicCompare(labelled as never, lang as 'en' | 'ar');
      return { analysis, why };
    };
    if (!parsed) {
      const { analysis } = degradedBecause(String(lastDetail).slice(0, 120));
      await rememberFailure(String(lastDetail));
      const t3 = analysis.top3.length;
      await logRun(t3 > 0 ? 'ok' : 'error', { compared: 1, degraded: 1, quotes_seen: qs.length, ai_attempts: attempts, ai_ok: 0, top3: t3, lang },
        'Every model attempt for quote_compare failed (' + String(lastDetail).slice(0, 120) + '), so the customer was served the DETERMINISTIC comparison instead of nothing: ' + qs.length + ' quotes ranked on stated price, completeness, lead time, warranty and payment terms, ' + t3 + ' ranked recommendation(s). It is labelled degraded to the customer; the failure is cached with a short retry-after, so card views do not re-ask the model, and the full analysis returns once it answers.');
      return J({ ok: true, analysis: await gated(withRoster(analysis), 'deterministic'), degraded: true, detail: lastDetail });
    }
    if (Array.isArray(parsed.quotes) && parsed.quotes.length > 3) parsed.quotes = parsed.quotes.slice(0, 3);
    if (Array.isArray(parsed.top3) && parsed.top3.length > 3) parsed.top3 = parsed.top3.slice(0, 3);
    if (Array.isArray(parsed.line_findings) && parsed.line_findings.length > 14) parsed.line_findings = parsed.line_findings.slice(0, 14);
    if (typeof parsed.considered !== 'number') parsed.considered = qs.length;
    parsed.total_quotes = live.length;
    parsed.shortlisted = Math.min(3, qs.length);
    parsed.itemised_quotes = labelled.filter((q: any) => q.itemised).length;
    parsed.disclaimer = (lang === 'ar') ? DISCLAIMER_AR : DISCLAIMER_EN;
    const _top3 = Array.isArray(parsed.top3) ? parsed.top3.length : 0;
    const _shown = Array.isArray(parsed.quotes) ? parsed.quotes.length : 0;
    const _lines = Array.isArray(parsed.line_findings) ? parsed.line_findings.length : 0;
    // The model answered but ranked nothing. To the customer that is the same blank screen as a
    // total failure, so it gets the same remedy — and the blank is NOT written to the cache,
    // which would have served it back on every re-open.
    if (_top3 === 0 || _shown === 0) {
      const { analysis } = degradedBecause('empty_shortlist');
      await rememberFailure('empty_shortlist');
      const t3 = analysis.top3.length;
      await logRun(t3 > 0 ? 'ok' : 'error', { compared: 1, degraded: 1, quotes_seen: qs.length, ai_attempts: attempts, ai_ok: 1, empty_shortlist: 1, top3: t3, lang },
        'The model returned a comparison object with an EMPTY shortlist for ' + qs.length + ' real quotes, which reaches the customer as a blank decision step. Served the DETERMINISTIC comparison instead: ' + t3 + ' ranked recommendation(s) from stated figures. The empty model result was not cached; the failure was, with a short retry-after.');
      return J({ ok: true, analysis: await gated(withRoster(analysis), 'deterministic'), degraded: true, detail: 'empty_shortlist' });
    }
    let cacheSaved = 1;
    try { const { error: cacheErr } = await admin.from('qd_compare_cache').upsert({ inquiry_id, quotes_hash: qhash, lang, analysis: parsed, created_at: new Date().toISOString() }); if (cacheErr) cacheSaved = 0; } catch (_e) { cacheSaved = 0; }
    await logRun((_top3 > 0 && _shown > 0) ? 'ok' : 'error', { compared: 1, quotes_seen: qs.length, quotes_live: live.length, itemised: parsed.itemised_quotes, line_items_sent: itemsTotal, track_records: Object.keys(trackBySupplier).length, expert_ref: expertRef ? 1 : 0, must_specs: mustSpecs.length, line_findings: _lines, shortlisted: _shown, top3: _top3, ai_attempts: attempts, ai_ok: 1, cached: 0, cache_saved: cacheSaved, lang }, (_top3 > 0 && _shown > 0) ? ('Quote comparison delivered: ' + qs.length + ' quotes evaluated (' + parsed.itemised_quotes + ' itemised, ' + itemsTotal + ' line items, ' + Object.keys(trackBySupplier).length + ' track records, expert_ref=' + (expertRef ? 'yes' : 'no') + '), ' + _shown + ' shortlisted, ' + _top3 + ' ranked recommendation(s), ' + _lines + ' line-level finding(s).' + (cacheSaved ? '' : ' NOTE: the result could not be written to qd_compare_cache, so every re-open re-runs the model at full cost.')) : ('quote_compare returned a comparison object with an EMPTY shortlist/top3 for ' + qs.length + ' real quotes — the model responded but produced no ranked recommendation, so the customer sees a blank comparison and cannot choose a supplier, while the call reports HTTP 200 success.'));
    return J({ ok: true, analysis: await gated(withRoster(parsed), authorModel) });
  } catch (e) { await logRun('error', { compared: 0, unhandled_exception: 1 }, 'quote_compare threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e).slice(0, 200) + ' — the customer could not compare the quotes they received and the RFQ stalls at the decision step.'); return J({ error: String((e as Error)?.message || e) }, 500); }
})));
