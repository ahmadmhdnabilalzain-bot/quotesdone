// customer_api — matching a posted request to suppliers and telling them, with the buyer's identity scrubbed.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { requestDelivery } from '../../_shared/deliver.ts';
import { sanctionedLeads } from '../../_shared/sanctioned.ts';
import { scrubIdentity } from '../../supplier_api/identity_scrub.ts';
import { SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';

// 29 Jul 2026 - ANONYMITY. The scrubber lived only in supplier_api's portal READ path, so every
// write path out of here shipped the customer's raw words straight to suppliers: the new-inquiry
// email, its WhatsApp clone via fn_wa_fanout, and the job_awarded_other notice. A customer typing
// "villa fit-out for Ahmed Khan, call 050 123 4567" had that emailed verbatim to up to eight
// suppliers before anyone paid a reveal fee, which is the entire business model inverted. Anything
// leaving this function toward a supplier goes through scrubIdentity first.
// 3 Nov 2026: the copy that lived here is gone. It had drifted from supplier_api's (no TRN, no licence) and both
// missed the shapes the planted-identity test measured (scripts/e2e/identity_never_leaks_before_reveal.mjs), so there
// is ONE scrubber now, imported: supplier_api/identity_scrub.ts scrubIdentity, built on _shared/identity_text.ts.
async function queueNotifications(rows: Record<string, unknown>[]) { try { if (rows.length) await requestDelivery(admin, rows); } catch (_e) { /* */ } }
// AUDIT 1.5 (4 Aug 2026) -----------------------------------------------------------------------
// Both supplier-facing emails in this file passed ownName = null to scrubIdentity. companyRe(null)
// returns null, so the buyer's name pattern was never added to the loop and only ID_PATTERNS ran -
// emails, URLs, messenger links and UAE numbers. The buyer's NAME went out verbatim, pre-reveal, to
// every matched supplier. The portal has always done this correctly: supplier_api resolves
// buyerName from inquiries.customer_id -> customers.full_name and passes it into the identical
// scrubIdentity. The email was the one supplier-facing surface where the name survived.
//
// The database is not a backstop for this. mask_contacts() removes contact strings and leaves names
// - verified on production:
//   select public.mask_contacts('Villa fit-out for Ahmed Khan, call 0501234567 or a@b.com');
//     -> 'Villa fit-out for Ahmed Khan, call [hidden] or [hidden]'
//
// FAIL CLOSED. `resolved:false` means the owner lookup itself failed, which is NOT the same as "this
// inquiry has no customer name on record". We cannot scrub a name we could not read, so callers
// must drop the customer-authored text entirely rather than emit it unscrubbed. Returning null on a
// failed read would have re-created the exact defect this comment describes.
//
// The name exists only to feed the scrubber and is never placed on a response.
type BuyerName = { resolved: true; name: string | null } | { resolved: false };
export async function buyerNameOf(inquiryId: string): Promise<BuyerName> {
  try {
    const { data: inq, error: e1 } = await admin.from('inquiries').select('customer_id').eq('id', inquiryId).maybeSingle();
    if (e1) return { resolved: false };
    const cid = inq?.customer_id;
    if (!cid) return { resolved: true, name: null };   // genuinely no owner recorded - nothing to scrub
    const { data: c, error: e2 } = await admin.from('customers').select('full_name').eq('id', cid).maybeSingle();
    if (e2) return { resolved: false };
    const n = String(c?.full_name || '').trim();
    // scrubIdentity/companyRe already refuse anything under 3 characters; matching that here keeps
    // "we found a name" and "the scrubber will act on it" the same statement.
    return { resolved: true, name: n.length >= 3 ? n : null };
  } catch (_e) { return { resolved: false }; }
}
export async function notifyLosers(inquiryId: string, summary: string | null, winnerId: number | null) {
  try {
    let qb = admin.from('quotes').select('supplier_id').eq('inquiry_id', inquiryId);
    if (winnerId) qb = qb.neq('supplier_id', winnerId);
    const { data: others } = await qb;
    const ids = [...new Set((others || []).map((o: any) => Number(o.supplier_id)).filter(Boolean))];
    if (!ids.length) return;
    const { data: lsAll } = await admin.from('leads').select('id,email,company_name').in('id', ids);
    // founder instruction 516, 18 Sep 2026: a sanctioned party is never messaged. The trigger
    // a02_notifications_never_reach_a_sanctioned_party would refuse the row anyway and take this
    // whole fan-out down with it, so the filter is here as well as there.
    const barredLosers = await sanctionedLeads(admin, (lsAll || []).map((l: any) => l.id));
    const ls = (lsAll || []).filter((l: any) => !barredLosers.has(String(l.id)));
    // AUDIT 1.5: the losing suppliers never paid for a reveal, so this is a pre-reveal surface even
    // though it is sent after the award. If the owner could not be read we quote nothing back at
    // them - the generic phrase below is already the correct fallback.
    const bn = await buyerNameOf(inquiryId);
    const scrubbedJob = (bn.resolved && summary && summary.trim()) ? (scrubIdentity(summary.trim(), bn.name, []) || '') : '';
    const job = scrubbedJob ? '“' + scrubbedJob + '”' : 'a recent job you quoted';
    const rows = (ls || []).filter((s: any) => s.email && /@/.test(s.email)).map((s: any) => ({
      type: 'job_awarded_other', to_email: s.email, to_role: 'supplier', lead_id: s.id, inquiry_id: inquiryId,
      subject: 'Update on a job you quoted — QuotesDone',
      body: 'Thank you for taking the time to quote on ' + job + '. On this occasion the customer has chosen to proceed with another supplier. We genuinely appreciate the effort you put into your quote, and it was great having you compete for the work. New matching opportunities come through QuotesDone regularly — please keep an eye on your supplier inbox, and we wish you the very best of luck on the next one.'
    }));
    await queueNotifications(rows);
  } catch (_e) { /* */ }
}
// A customer request that reaches NOBODY is revenue loss and a supply-coverage gap.
// dispatch_inquiry already flags this; create_inquiry's own matching path used to return
// matches:0 silently, so the customer saw "Request sent" and waited for quotes that could
// never arrive, and nothing landed in the action queue. Both paths now behave the same.
async function flagCoverageGap(inqId: string, category: string, emirate: string | null, summary: string) {
  const label = (category || 'uncategorised') + ' / ' + (emirate || 'UAE');
  let flagged = true;
  try {
    await admin.from('agent_actions').insert({
      // sales_engineer: the founder, 14 Sep 2026 — "its always the sales agent. no other agent is
      // involved in customer or supplier portal." operations_ai is no seat; the resolver filed it as 'brief'.
      agent: 'sales_engineer', kind: 'coverage_gap', status: 'pending', risk: 'medium',
      title: 'RFQ had no matchable supplier' + (category ? (': ' + category) : ''),
      recommendation: 'A customer request (' + label + ') matched ZERO suppliers, so it reached nobody and cannot receive quotes. This is a supply-coverage gap: consider acquiring or onboarding suppliers in this trade and emirate. No supplier was contacted.',
      detail: { signal: 'coverage_gap:' + inqId, inquiry_id: inqId, category, emirate, summary: String(summary || '').slice(0, 300), path: 'create_inquiry' },
      // s36 (13 Aug 2026): what this flag takes on trust. Written here rather than left to a reader,
      // because "zero suppliers matched" reads as a fact about the market and is at least three
      // different findings wearing the same number.
      assumptions: [
        'That the matcher was asked the right question. Category and emirate are the customer\'s intake as it was recorded; a mis-categorised request manufactures a gap in a trade nobody actually asked for.',
        'That zero matches means no capable supplier. It equally means suppliers exist and none has DECLARED this capability — fn_match_capability gates on declared trades, not on what a company can do.',
        'That the supplier base was reachable at the time. A supplier suspended, unverified, or without an approved licence is invisible to the matcher and counts here as absent.',
      ],
      expected_impact: 'This request reached nobody and cannot receive a quote. It is the clearest demand signal this company gets: a customer who wanted something the marketplace could not serve.',
      cost: 'No spend to record it. Closing the gap costs invitation volume and sending reputation, which the invite ramp caps — or nothing at all, if a supplier already on file simply has not declared the trade.',
      target_table: 'inquiries', target_id: inqId });
  } catch (_e) { flagged = false; }
  // Founder ledger 1436/1447: he is an investor and is not paged. The coverage_gap above is the sales engineer's to act on;
  // 55 pages went out (30 in the last 14 days), and only 3 named an inquiry that still exists: all rehearsals.
  return flagged;
}
export async function matchAndNotify(inqId: string, opts: { category: string; emirate: string | null; summary: string; budget: string | null; extra: string }): Promise<{ matches: number; routing: Record<string, any> }> {
  const { category, emirate, summary, budget, extra } = opts;
  // THE MATCH PERCENTAGE, PERSISTED. The matcher behind this function returns a rank score and
  // this writer used to throw it away with the literal null, so inquiry_matches.similarity was null
  // on every row in every environment and the portal had no stored number to show. The score is
  // normalised against the maximum its scorer can award, so the stored value is a 0..1 fraction
  // and not a raw score on an undeclared scale: fn_match_capability's weights come from
  // decision_policy (product 40 + brand 20 + project_type 15 + track_record 15 + size_fit 10) and
  // sum to 100 by construction, so the denominator is 100.
  // NOT MEASURED STAYS NULL. route_inquiry only scores on the structured capability path; on the
  // legacy AI-adjudicator path the verdict is a binary fit/no with a free-text reason and no number
  // exists at all. Deriving a percentage from rank position or fanout size would be inventing one.
  const sim01 = (raw: unknown, max: number): number | null => {
    const n = Number(raw);
    if (!Number.isFinite(n) || max <= 0) return null;
    return Math.round(Math.min(1, Math.max(0, n / max)) * 1000) / 1000;
  };
  let fits: { id: number; company_name?: string; reason?: string; sim?: number | null }[] = [];
  let routing: Record<string, any> = {};
  let routerAnswered = false;
  // Two attempts, 1.5 s apart: a cold start or one dropped request must not leave an inquiry unmatched.
  for (let attempt = 1; !routerAnswered && attempt <= 2; attempt++) {
    if (attempt > 1) await new Promise((r) => setTimeout(r, 1500));
    try {
      // 9 Sep 2026 — MATCHING IS THE SALES ENGINEER'S (founder: "match capability is the sales
      // engineer task"). This called functions/v1/route_inquiry, which was DELETED in 182308b and
      // is deployed nowhere: the fetch 404'd, rj?.ok was falsy, routerAnswered stayed false and the
      // block below silently degraded every single inquiry to match_suppliers_kw — keyword
      // matching — with routing.fallback = true and no exception, no alert and no stuck row, while
      // decision_policy.use_capability_matching said true the whole time.
      // sales_engineer's `match` action runs public.fn_match_capability and honours
      // decision_policy's relevance floor, and invites every supplier left (no count cap: any number may quote). persist:false because
      // the write happens below, where the landed/refused split decides who is emailed.
      const secret = await getSecret('cred_fn_customer_api');
      // The Authorization header is NOT optional and its absence is what the old call looked like.
      // sales_engineer is deployed with verify_jwt = true, so a header-less POST is rejected by the
      // gateway BEFORE the function runs — a 401 that reads exactly like the 404 this replaces:
      // rj.ok falsy, silent degrade to keywords. The service key gets past the gateway; the
      // __secret in the body is what actually decides the caller inside.
      const rr = await fetch(`${SUPABASE_URL}/functions/v1/sales_engineer`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${SERVICE}`, apikey: SERVICE }, body: JSON.stringify({ __secret: secret, action: 'match', inquiry_id: inqId, persist: false }) });
      const rj = await rr.json();
      if (rj?.ok) { routerAnswered = true; routing = { matcher: 'sales_engineer.match', primary_trade: (rj.asked_for?.trades || [])[0] ?? null, trades: rj.asked_for?.trades ?? null, need: rj.asked_for?.need ?? null, policy: rj.policy ?? null, evaluated: rj.candidates ?? null, above_floor: rj.above_floor ?? null, note: rj.gap?.reason || null, gap: rj.gap || null, at: new Date().toISOString() }; fits = (Array.isArray(rj.matched) ? rj.matched : []).map((f: any) => ({ id: Number(f?.supplier_id), company_name: f?.company_name, reason: String(f?.reason || ''), sim: sim01(f?.score, 100) })); }
      else routing = { error: rj?.error || 'match_failed', at: new Date().toISOString() };
    } catch (e) { routing = { error: String((e as Error)?.message || e), at: new Date().toISOString() }; }
  }
  // ROUTE_INQUIRY OVERRIDE (27 Jul 2026). This used to fall back to match_suppliers_kw whenever
  // fits was empty, INCLUDING when route_inquiry had answered successfully with zero fits. But
  // needs_detail (brief too thin), no_capability_match and no_registered_suppliers are the
  // router's genuine verdicts, not failures — it deliberately contacts nobody. Fanning the RFQ
  // out to 8 keyword-matched suppliers anyway threw the adjudication away, spammed suppliers who
  // cannot do the job, and made every negative verdict invisible. We now fall back ONLY when the
  // router genuinely did not answer: it was not used, it errored, or the response was missing.
  // A successful zero-fit answer is respected — coverage gap path, router's reason persisted.
  //
  // EXACT OR NONE (15 Sep 2026, founder rule). The fallback above still fired when the sales
  // engineer errored, and it fanned the RFQ out by fuzzy keyword plus sector equality — the nearest
  // mapping the founder ruled out. On a matcher error the inquiry now waits unmatched, the routing
  // record on it says why, and the sales engineer's failure is raised as a finding with the inquiry
  // id.
  //
  // THE TURNKEY PATH TOO (15 Sep 2026). It skipped the sales engineer and shortlisted by keyword
  // plus a hard-coded fit-out word list, the last caller of the keyword matcher. It now asks the same
  // sales engineer route as every other request: that route reads scope_type 'turnkey' as the
  // whole_scope need and resolves the stored trades exactly. The keyword routine was then dropped
  // (scripts/sql/the_turnkey_path_asks_the_sales_engineer_and_the_keyword_matcher_is_dropped.sql).
  if (!routerAnswered) {
    fits = [];
    routing.matcher_unavailable = true;
    routing.waiting_for = 'sales_engineer.match';
    try {
      await admin.rpc('fn_it_engineer_finding_upsert', {
        p_issue_key: 'sales_engineer_match_unavailable',
        p_title: 'The sales engineer matcher did not answer; an inquiry is waiting unmatched instead of being keyword-matched',
        p_where: 'customer_api.matchAndNotify -> sales_engineer {action:match}', p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { inquiry_id: inqId, error: String(routing.error ?? 'no answer'), attempts: 2, at: new Date().toISOString() },
        p_raised_by: 'sales_engineer',
      });
    } catch (_e) { /* the routing record on the inquiry still carries the error */ }
  }
  if (routerAnswered && fits.length === 0) { routing.router_verdict = String(routing.note || (routing.needs_detail ? 'needs_detail' : 'adjudicated_no_fit')); routing.keyword_fallback_suppressed = true; }
  const fitIds = fits.map((f) => Number(f.id)).filter(Boolean);
  let supRows: Record<string, any>[] = [];
  if (fitIds.length) { const { data: ls } = await admin.from('leads').select('id,company_name,email').in('id', fitIds); supRows = ls || []; }
  const supById = new Map(supRows.map((s: any) => [Number(s.id), s]));
  const matchRows = fits.filter((f) => supById.has(Number(f.id))).map((f) => ({ inquiry_id: inqId, supplier_id: Number(f.id), similarity: f.sim ?? null, match_reason: String(f.reason || '').slice(0, 400) }));
  // K05 (23 Aug 2026). THE FANOUT WAS THE ROWS WE TRIED TO INSERT, NOT THE ROWS THAT LANDED.
  //
  // 9 SEP 2026 — THE GATES THIS PARAGRAPH NAMES ARE GONE, and asking for the rows back is kept
  // anyway. MEASURED, not read: pg_trigger holds 4 rows for public.inquiry_matches and all 4 are
  // internal referential-integrity triggers — 0 user triggers — and neither
  // a00_unsafe_match_eligibility nor gate_incomplete_match exists in pg_proc. So no BEFORE INSERT
  // gate refuses a supplier here today and `refused` below will be empty; supplier eligibility on
  // this path is now enforced solely by fn_is_matchable INSIDE fn_match_capability, upstream. The
  // landed/refused read stays because it is the only thing that would NOTICE a gate returning, and
  // because it costs one `.select()`.
  //
  // The original defect, for the record: each gate refused by returning null, which PostgREST
  // answers as 201 with no row. So `error` was null, matchRows.length was recorded as the fanout,
  // and a refused supplier counted as a contacted one. dispatch_inquiry had this exact defect and it was fixed on
  // 15 Aug 2026 by asking for the rows back; this is the same fix on the other writer.
  let landedIds: number[] = [];
  if (matchRows.length) {
    const { data: landedRows } = await admin.from('inquiry_matches').insert(matchRows).select('supplier_id');
    landedIds = (landedRows || []).map((r: { supplier_id: number }) => Number(r.supplier_id)).filter(Boolean);
  }
  const refused = matchRows.map((m) => Number(m.supplier_id)).filter((id) => !landedIds.includes(id));
  routing.outcome = landedIds.length ? 'dispatched' : 'no_fit';
  routing.fanout = landedIds.length;
  routing.attempted = matchRows.length;
  if (refused.length) routing.refused_at_assignment = refused;
  try { await admin.from('inquiries').update({ routing }).eq('id', inqId); } catch (_e) { /* */ }
  // A matcher that did not answer is not a coverage gap: it is already a finding (above), and flagging
  // it here would record "no supplier covers this" for a trade we never actually searched.
  // A REQUEST THAT REACHED NOBODY GOES TO THE STALLED-INQUIRY RESCUE AT ONCE (29 Sep 2026, sales_engineer, ledger
  // 1033): matching now skips busy and paused suppliers, so "nobody" can mean "everybody is busy until Thursday".
  // fn_stalled_inquiry_flag records it, with why, in stalled_inquiry_rescue; the sales_engineer.supplier_availability
  // duty sweeps every open inquiry every 15 minutes as well, so a failure here is caught on the next beat.
  if (!landedIds.length) {
    try {
      const { data: fl } = await admin.rpc('fn_stalled_inquiry_flag', { p_inquiry_id: inqId, p_by: 'customer_api.matchAndNotify' });
      routing.rescue_flagged = !!fl?.flagged;
    } catch (_e) { routing.rescue_flagged = false; }
    if (!routing.matcher_unavailable) routing.coverage_gap_flagged = await flagCoverageGap(inqId, category, emirate, summary);
    return { matches: 0, routing };
  }
  // AUDIT 1.5. This is the first supplier-facing surface an inquiry ever reaches and it is entirely
  // pre-reveal. summary, budget and extra are customer free text; category and emirate are platform
  // values from a fixed list. If the owner could not be read, the free-text fields are dropped and
  // the supplier is told the trade and emirate only - enough to log in and look, nothing authored by
  // the buyer. A supplier who receives less detail can still quote; a buyer whose name was emailed
  // to eight strangers cannot be un-emailed.
  const bn = await buyerNameOf(inqId);
  const cust = (t: string | null | undefined) => (bn.resolved && t) ? (scrubIdentity(String(t), bn.name, []) || '') : '';
  const headline = cust(summary) || category;
  // K05. NOTIFY THE SUPPLIERS WHOSE MATCH ACTUALLY LANDED, not the ones we tried to match. This
  // read matchRows, so a supplier the eligibility gate had just refused — banned, matching-blocked,
  // permanently closed, expired licence — was still emailed the job. landedIds is what the database
  // accepted.
  const notifs = landedIds.map((sid) => supById.get(Number(sid))).filter((s: any) => s && s.email && /@/.test(s.email)).map((s: any) => ({ type: 'new_inquiry', to_email: s.email, to_role: 'supplier', lead_id: s.id, inquiry_id: inqId, subject: 'New job request on QuotesDone', body: 'A customer is requesting quotes for: ' + headline + (emirate ? ' (' + emirate + ')' : '') + (cust(budget) ? ' — budget ' + cust(budget) : '') + '.' + cust(extra) + ' Log in to your QuotesDone supplier portal to quote.' }));
  await queueNotifications(notifs);
  return { matches: landedIds.length, routing };
}
