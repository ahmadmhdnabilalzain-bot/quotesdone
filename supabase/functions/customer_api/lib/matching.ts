// customer_api — matching a posted request to suppliers and telling them, with the buyer's identity scrubbed.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { requestDelivery } from '../../_shared/deliver.ts';
import { supplierAddress } from '../../_shared/supplier_address.ts';
import { sanctionedLeads } from '../../_shared/sanctioned.ts';
import { awardedOtherBody, newInquiryBody, readOwner, type OwnerRead } from '../../supplier_api/what_a_supplier_receives.ts';
import { withoutPartnerWhy } from '../../_shared/partner_match.ts';
import { SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';
import { failedState, matcherFindingKey, rematchSchedule, type RematchState } from './rematch.ts';
import { customerFrozen, heldForComplianceReview } from './compliance_hold.ts';

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
// THE NEW-INQUIRY E-MAIL IS GATED AS THE PORTAL IS (13 Nov 2026, sales_engineer; anonymity audit A, L3). This e-mail ran
// scrubIdentity with the buyer's name only, so the project name, "Haddad Family Office", "Plot No. 373-4512", "Makani
// 12345 67890" and "Apartment 1204" reached every matched supplier's inbox while the portal withheld them. The owner is
// now read whole (name, e-mail, phone, project, and the stated site from the request's own brief) and the body is built
// by supplier_api/what_a_supplier_receives.ts newInquiryBody, the portal's gate. A failed read is resolved:false: the
// e-mail then carries the trade and the emirate only, as before.
export type BuyerRead = OwnerRead;
/** The owner as the gate needs him; one reader for every door (supplier_api/what_a_supplier_receives.ts readOwner). */
export const buyerOf = (inquiryId: string): Promise<BuyerRead> => readOwner(admin, inquiryId);
export async function notifyLosers(inquiryId: string, summary: string | null, winnerId: number | null) {
  try {
    let qb = admin.from('quotes').select('supplier_id').eq('inquiry_id', inquiryId);
    if (winnerId) qb = qb.neq('supplier_id', winnerId);
    const { data: others } = await qb;
    const ids = [...new Set((others || []).map((o: any) => Number(o.supplier_id)).filter(Boolean))];
    if (!ids.length) return;
    const { data: lsAll } = await admin.from('leads').select('id,email,claimed_by,company_name').in('id', ids);
    // founder instruction 516, 18 Sep 2026: a sanctioned party is never messaged. The trigger
    // a02_notifications_never_reach_a_sanctioned_party would refuse the row anyway and take this
    // whole fan-out down with it, so the filter is here as well as there.
    const barredLosers = await sanctionedLeads(admin, (lsAll || []).map((l: any) => l.id));
    const ls = (lsAll || []).filter((l: any) => !barredLosers.has(String(l.id)));
    // AUDIT 1.5: the losing suppliers never paid for a reveal, so this is a pre-reveal surface even
    // though it is sent after the award. If the owner could not be read we quote nothing back at
    // them - the generic phrase below is already the correct fallback.
    // 13 Nov 2026: the portal's gate, with the seeds and the stated site (what_a_supplier_receives.ts), as the new-inquiry e-mail.
    const body = awardedOtherBody(summary, await buyerOf(inquiryId));
    // the address the supplier signs in with, not the listing's (_shared/supplier_address.ts, #1909 item 4)
    const rows = (ls || []).filter((s: any) => supplierAddress(s)).map((s: any) => ({
      type: 'job_awarded_other', to_email: supplierAddress(s), to_role: 'supplier', lead_id: s.id, inquiry_id: inquiryId,
      subject: 'Update on a job you quoted — QuotesDone',
      body,
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
// `prior` is the re-match state a request carried when the matcher failed before (lib/rematch.ts); null at posting.
export async function matchAndNotify(inqId: string, opts: { category: string; emirate: string | null; summary: string; budget: string | null; extra: string }, prior: Partial<RematchState> | null = null): Promise<{ matches: number; routing: Record<string, any> }> {
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
  // A CUSTOMER WITH AN OPEN SANCTIONS HIT IS NOT MATCHED UNTIL THE CEO DECIDES (16 Nov 2026; lib/compliance_hold.ts).
  // Its own wait: no next try and never exhausted, so neither the re-match sweep nor the 14-day closer takes it; the CEO's
  // decision releases it (fn_customer_screening_decide).
  if (await customerFrozen(admin, inqId)) {
    const r = heldForComplianceReview(prior, extra, new Date());
    try { await admin.from('inquiries').update({ routing: r }).eq('id', inqId); } catch (_e) { /* the next step of the schedule writes it again */ }
    return { matches: 0, routing: r };
  }
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
      if (rj?.ok) { routerAnswered = true; routing = { matcher: 'sales_engineer.match', primary_trade: (rj.asked_for?.trades || [])[0] ?? null, trades: rj.asked_for?.trades ?? null, need: rj.asked_for?.need ?? null, policy: rj.policy ?? null, evaluated: rj.candidates ?? null, above_floor: rj.above_floor ?? null, note: rj.gap?.reason || null, gap: rj.gap || null, ...(rj.separate_offer ? { separate_offer: rj.separate_offer } : {}), at: new Date().toISOString() }; fits = (Array.isArray(rj.matched) ? rj.matched : []).map((f: any) => ({ id: Number(f?.supplier_id), company_name: f?.company_name, reason: String(f?.reason || ''), sim: sim01(f?.score, 100) })); }
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
  // NOTHING USED TO ASK AGAIN (customer-journey follow-up, 10 Nov 2026; lib/rematch.ts). The request now carries its
  // re-match schedule, the sweep in lib/rematch.ts asks again on it, and the finding is keyed per request: one fixed key
  // made every outage one row whose evidence named only the last inquiry.
  if (!routerAnswered) {
    fits = [];
    routing.matcher_unavailable = true;
    routing.waiting_for = 'sales_engineer.match';
    let schedule = rematchSchedule(null);
    try { const { data: pol } = await admin.from('decision_policy').select('value').eq('key', 'rematch_backoff_minutes').maybeSingle(); schedule = rematchSchedule(pol?.value); } catch (_e) { /* the default schedule */ }
    routing.rematch = failedState(prior, extra, new Date(), schedule);
    try {
      await admin.rpc('fn_it_engineer_finding_upsert', {
        p_issue_key: matcherFindingKey(inqId),
        p_title: 'The sales engineer matcher did not answer; an inquiry is waiting unmatched instead of being keyword-matched',
        p_where: 'customer_api.matchAndNotify -> sales_engineer {action:match}', p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { inquiry_id: inqId, error: String(routing.error ?? 'no answer'), calls_this_attempt: 2, rematch_attempts: routing.rematch.attempts,
          first_failed_at: routing.rematch.first_failed_at, next_at: routing.rematch.next_at, exhausted: routing.rematch.exhausted, at: new Date().toISOString() },
        p_raised_by: 'sales_engineer',
      });
    } catch (_e) { /* the routing record on the inquiry still carries the error */ }
  } else if (prior) routing.rematched = { attempts: (Number(prior.attempts) || 0) + 1, first_failed_at: prior.first_failed_at ?? null, at: new Date().toISOString() };
  if (routerAnswered && fits.length === 0) { routing.router_verdict = String(routing.note || (routing.needs_detail ? 'needs_detail' : 'adjudicated_no_fit')); routing.keyword_fallback_suppressed = true; }
  const fitIds = fits.map((f) => Number(f.id)).filter(Boolean);
  let supRows: Record<string, any>[] = [];
  if (fitIds.length) { const { data: ls } = await admin.from('leads').select('id,company_name,email,claimed_by').in('id', fitIds); supRows = ls || []; }
  const supById = new Map(supRows.map((s: any) => [Number(s.id), s]));
  const matchRows = fits.filter((f) => supById.has(Number(f.id))).map((f) => ({ inquiry_id: inqId, supplier_id: Number(f.id), similarity: f.sim ?? null, match_reason: withoutPartnerWhy(f.reason).slice(0, 400) }));   // never tell the customer a quote uses a partner (services/REPORT.md 3.7)
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
  // A matcher that did not answer is not "no supplier can take it on" either: the rescue would tell the customer so. The
  // request waits for the re-match (lib/rematch.ts), and goes to the rescue once the matcher has answered with nobody.
  if (!landedIds.length) {
    if (!routing.matcher_unavailable) {
      try {
        const { data: fl } = await admin.rpc('fn_stalled_inquiry_flag', { p_inquiry_id: inqId, p_by: 'customer_api.matchAndNotify' });
        routing.rescue_flagged = !!fl?.flagged;
      } catch (_e) { routing.rescue_flagged = false; }
    }
    if (!routing.matcher_unavailable) routing.coverage_gap_flagged = await flagCoverageGap(inqId, category, emirate, summary);
    return { matches: 0, routing };
  }
  // AUDIT 1.5. This is the first supplier-facing surface an inquiry ever reaches and it is entirely
  // pre-reveal. summary, budget and extra are customer free text; category and emirate are platform
  // values from a fixed list. If the owner could not be read, the free-text fields are dropped and
  // the supplier is told the trade and emirate only - enough to log in and look, nothing authored by
  // the buyer. A supplier who receives less detail can still quote; a buyer whose name was emailed
  // to eight strangers cannot be un-emailed.
  const br = await buyerOf(inqId);
  const body = newInquiryBody({ resolved: br.resolved, buyer: br.resolved ? br.buyer : { name: null }, spec: br.resolved ? br.spec : null, summary, budget, extra, category, emirate: br.resolved ? (br.emirate ?? emirate) : emirate, briefSource: br.resolved ? br.briefSource : null });
  // K05. NOTIFY THE SUPPLIERS WHOSE MATCH ACTUALLY LANDED, not the ones we tried to match. This
  // read matchRows, so a supplier the eligibility gate had just refused — banned, matching-blocked,
  // permanently closed, expired licence — was still emailed the job. landedIds is what the database
  // accepted.
  const notifs = landedIds.map((sid) => supById.get(Number(sid))).filter((s: any) => s && supplierAddress(s)).map((s: any) => ({ type: 'new_inquiry', to_email: supplierAddress(s), to_role: 'supplier', lead_id: s.id, inquiry_id: inqId, subject: 'New job request on QuotesDone', body }));
  await queueNotifications(notifs);
  return { matches: landedIds.length, routing };
}
