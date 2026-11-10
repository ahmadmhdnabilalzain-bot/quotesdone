// THE SUPPLIER OVERVIEW IN ONE ROUND TRIP (15 Sep 2026, sales_engineer).
//
// Measured from the code before this file existed: opening the dashboard fired THREE supplier_portal
// calls (overview, then — only once overview had rendered — eligibility and document_impact), each
// repeating auth.getUser and the supplier lookup. Inside overview, fn_supplier_stats (~11 ms in SQL)
// was awaited before anything else, then the five alert reads ran one after another. Serial depth:
// 2 (auth + lookup) + 1 (stats) + 5 (alerts) = 8 database round trips for the first call, and a
// second HTTP wave behind it.
//
// `dashboard` returns stats, alerts, eligibility, document impact and the notification counts from
// ONE authenticated call. Every read that does not need another's answer starts together: the alerts
// have one dependency (the open-inquiry filter needs the matched ids), so their depth is 2, and the
// whole payload's depth is 2 after the lookup. The separate `overview`, `eligibility` and
// `document_impact` actions stay for the panels and older clients that call them; they share these
// builders, so the combined answer and the single ones cannot drift.
//
// No Supabase client is created here: the caller passes its own, which is what lets
// overview.test.ts drive every builder against a fake with a fixed latency per read.
import { mandatorySixMissing, registrationChecklist } from '../_shared/supplier_registration.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
export type Supplier = { id: number; company_name: string; approval_status: string | null; registration_status: string | null; license_expiry: string | null; name_corrected_from: string | null; licence_gate_reason?: string | null; exception_due_at?: string | null; accepted_terms_at?: string | null; signed_terms_at?: string | null };

// Inquiry states in which an unquoted match is still an RFQ waiting for this supplier.
const OPEN_INQ = ['sent', 'open', 'active', 'collecting', 'live', 'quoted'];
// A hold the supplier must answer (supplier_api inbox reads the same two states).
const LIVE_HOLD = ['open', 'awaiting_approval'];

export async function buildAlerts(admin: Admin, supId: number): Promise<Row[]> {
  const [{ data: exp }, { data: matches }, { data: myq }, { count: drafts }] = await Promise.all([
    admin.rpc('fn_supplier_expiries', { p_supplier_id: supId }),
    admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', supId),
    admin.from('quotes').select('inquiry_id').eq('supplier_id', supId),
    admin.from('quotes').select('id', { count: 'exact', head: true }).eq('supplier_id', supId).eq('status', 'draft'),
  ]);
  const out: Row[] = [];
  for (const e of (exp || [])) {
    if (e.status === 'expired' || e.status === 'expiring') {
      out.push({ kind: 'doc_expiry', code: 'doc_expiry', params: { doc: e.doc, expiry: e.expiry, days_left: e.days_left, expired: e.status === 'expired' }, severity: e.status === 'expired' ? 'high' : 'medium',
        title: e.doc + (e.status === 'expired' ? ' has expired' : ' expires soon'),
        detail: 'Expiry ' + e.expiry + ' — ' + (e.days_left < 0 ? ('overdue by ' + Math.abs(e.days_left) + ' days') : (e.days_left + ' days left')) + '. Upload a renewed copy to stay eligible.',
        action: 'documents' });
    }
  }
  const mids = [...new Set((matches || []).map((m: Row) => m.inquiry_id))];
  if (mids.length) {
    const quoted = new Set((myq || []).map((x: Row) => x.inquiry_id));
    const { data: openInq } = await admin.from('inquiries').select('id').in('id', mids).in('status', OPEN_INQ);
    const openIds = (openInq || []).map((x: Row) => x.id).filter((id: unknown) => !quoted.has(id));
    if (openIds.length) out.push({ kind: 'new_rfq', code: 'new_rfq', params: { count: openIds.length, total: (openInq || []).length }, severity: 'medium', count: openIds.length, title: openIds.length + ' new RFQ' + (openIds.length > 1 ? 's' : '') + ' waiting for your quote', detail: 'Open requests matched to your capabilities that you have not quoted yet.', action: 'inbox' });
  }
  if (drafts) out.push({ kind: 'draft_quote', code: 'draft_quote', params: { count: drafts }, severity: 'low', count: drafts, title: drafts + ' draft quote' + (drafts > 1 ? 's' : '') + ' to complete', detail: 'Add the missing details so we can send them to customers.', action: 'inbox' });
  return out;
}

// Why am I not being matched?
//
// Every check below mirrors a real clause in match_suppliers_kw. Nothing here is
// advisory dressed up as a rule, and nothing that genuinely gates matching is omitted,
// because a supplier acting on this will conclude they have done everything needed.
//
// On document expiry: match_suppliers_kw itself has no expiry clause, so reading only that
// function suggests expiry is irrelevant. It is not. fn_reconcile_doc_blocks runs daily and
// sets matching_blocked with matching_block_reason when a trade licence or insurance lapses,
// and match_suppliers_kw does exclude matching_blocked. Expiry therefore genuinely stops
// matching - one indirection away - which is why it is reported as blocking below.
export async function buildEligibility(admin: Admin, supId: number): Promise<Row> {
  // Five independent reads, together. The two supplier_capabilities reads (the scope gate and the
  // proposed trades) were two queries against one row; they are one now.
  const [{ data: l }, capRes, { count: matched }, { count: quoted }, six] = await Promise.all([
    admin.from('leads')
      .select('id,company_name,sector,categories,products,services,capability_summary,emirate,service_emirates,permanently_closed,banned,matching_blocked,matching_block_reason,license_expiry,insurance_expiry,registration_submitted_at,source,approval_status,verified,licence_gate_reason,license_doc_path,phone,email,owner_phone_verified,owner_email_verified,trade_license_no,company_profile_doc_path,accepted_terms_at')
      .eq('id', supId).maybeSingle(),
    // On a read failure do not invent a green badge: an error leaves the scope unconfirmed.
    Promise.resolve(admin.from('supplier_capabilities').select('trades,proposed_trades,confirmed_at').eq('supplier_id', supId).maybeSingle())
      .catch(() => ({ data: null })),
    admin.from('inquiry_matches').select('id', { count: 'exact', head: true }).eq('supplier_id', supId),
    admin.from('quotes').select('id', { count: 'exact', head: true }).eq('supplier_id', supId),
    mandatorySixMissing(admin, supId),
  ]);
  const r = (l || {}) as Row;
  const cap = (capRes && (capRes as Row).data) || null;
  const has = (v: unknown) => !!(v != null && String(v).trim() !== '');

  const blocking: Row[] = [];
  if (r.permanently_closed === true) blocking.push({ code: 'permanently_closed', title: 'Your listing is marked permanently closed', detail: 'We will not send you requests while this is set. Contact us if this is wrong.', fix: 'contact' });
  if (r.banned === true) blocking.push({ code: 'banned', title: 'Your account is suspended', detail: 'Suspended accounts are excluded from all matching. Contact us to resolve it.', fix: 'contact' });
  if (r.matching_blocked === true) {
    // The reason matters. fn_reconcile_doc_blocks suspends automatically on an expired trade
    // licence or insurance and restores automatically on renewal, so telling that supplier the
    // block was "set manually by our team" would send them to support for something they can
    // fix themselves in two minutes - and would be false.
    const reason = String(r.matching_block_reason || '');
    if (reason === 'licence_expired') {
      blocking.push({ code: 'licence_expired', params: { date: r.license_expiry || null }, title: 'Your account is paused - trade licence expired',
        detail: 'Your trade licence expired on ' + (r.license_expiry || 'an earlier date') + '. Upload a valid copy and your account is restored automatically at our daily document check once the new licence reads as in date, so within a day. If it cannot be read, we tell you what to upload again. There is no fee.',
        fix: 'documents' });
    } else if (reason === 'insurance_expired') {
      blocking.push({ code: 'insurance_expired', params: { date: r.insurance_expiry || null }, title: 'Your account is paused - insurance expired',
        detail: 'Your insurance certificate expired on ' + (r.insurance_expiry || 'an earlier date') + '. Upload a valid copy and your account is restored automatically. There is no fee.',
        fix: 'documents' });
    } else {
      blocking.push({ code: 'matching_blocked', title: 'Matching is switched off for your account',
        detail: 'This was set by our team rather than automatically. Contact us to have it reviewed.', fix: 'contact' });
    }
  }
  const registered = !!r.registration_submitted_at || r.source === 'self_registered' || String(r.approval_status || '') === 'approved';
  if (!registered) blocking.push({ code: 'not_registered', title: 'Your registration is not submitted', detail: 'Only registered suppliers receive requests. Complete your company profile to submit it.', fix: 'profile' });

  // THE APPROVAL MATCHING ASKS (10 Nov 2026, customer_support, supplier-journey audit). fn_is_matchable takes verified AND
  // approval_status = 'approved' before anything else, and this panel never asked it: a supplier the gate held 'pending'
  // (an unread licence number, a document being read, auto-approve off) or 'action_required' with a confirmed scope read
  // "Eligible for matching" while no request could reach him. While an item of the six is missing the checklist above is
  // the answer and is not repeated; once the six are in, the hold is named with the gate's own reason.
  // Prevented by: supplier_portal/overview.test.ts ("a supplier the gate holds pending is not eligible").
  const approved = r.verified === true && String(r.approval_status || '') === 'approved';
  if (registered && !approved && (six as string[]).length === 0) {
    const reason = String(r.licence_gate_reason || '');
    blocking.push({ code: 'not_approved', params: { reason: reason || null, status: r.approval_status || null },
      title: 'Your registration is not approved yet',
      detail: 'Requests reach approved suppliers only. ' + (reason ? 'What is holding it, and what to do about it, is shown at the top of your portal.' : 'Our sales engineer is reviewing your registration and will e-mail you when it is approved.'),
      fix: reason.startsWith('licence_') || reason === 'documents_being_read' ? 'documents' : reason === 'services_unconfirmed' ? 'scope' : 'contact' });
  }

  // THE GATE THIS PANEL WAS MISSING (13 Aug 2026).
  //
  // Everything above evaluates match_suppliers_kw. The path that actually builds a shortlist is
  // fn_match_capability, and its candidate CTE opens with `where sc.confirmed_at is not null`.
  // So a supplier who had registered but not confirmed their scope was shown a green "Eligible
  // for matching" badge and an EMPTY "Stopping requests reaching you" list, while being excluded
  // from every RFQ at the first WHERE clause. Measured on 13 Aug by nulling confirmed_at for the
  // one confirmed supplier: eligibility returned {eligible:true, blocking:[]} and
  // fn_match_capability(['hvac']) returned 0 rows in the same minute.
  //
  // It is a BLOCKING item, not an improving one: this is the difference between 1 supplier an RFQ
  // can reach and 15,306.
  if (!cap?.confirmed_at) blocking.push({ code: 'scope_unconfirmed',
    title: 'Confirm what your company can quote for',
    detail: 'We never guess a supplier’s scope on their behalf, so no request is sent to you until you have confirmed it yourself. We have already filled in the trades and role we hold for your company — you only correct them and press confirm. It takes about a minute, once. It is also the last step of verification: until you confirm, your registration stays Pending.',
    fix: 'scope' });

  // Discoverability: the query matches on sector OR keywords across these four columns.
  // With all of them empty a supplier is unreachable no matter how many requests come in.
  const kwCols = ['products', 'services', 'categories', 'capability_summary'];
  const kwFilled = kwCols.filter((c) => has(r[c]));
  if (!has(r.sector) && kwFilled.length === 0) {
    blocking.push({ code: 'undiscoverable', title: 'Nothing describes what you supply', detail: 'Requests are matched on your sector, products, services and categories. All of these are empty, so no request can reach you.', fix: 'profile' });
  }

  const improving: Row[] = [];
  // ONLY FIELDS THE SUPPLIER CAN REACH (audit 21 Sep 2026, finding 20). "Set your sector", "Add your
  // categories" and "Add your capability summary" pointed at Profile, which has none of the three
  // (sector is chosen at company creation, categories are the confirmed trades, capability_summary
  // is written by profile_ai). Products lives on Profile; services on the Services tab.
  if (!has(r.products)) improving.push({ code: 'empty_products', title: 'Add your products', detail: 'Each keyword found here raises your match score. Empty fields cannot match anything.', fix: 'profile' });
  if (!has(r.services)) improving.push({ code: 'empty_services', title: 'Add your services', detail: 'Each keyword found here raises your match score. Empty fields cannot match anything.', fix: 'scope' });
  if (!has(r.emirate) && !(Array.isArray(r.service_emirates) && r.service_emirates.length)) {
    improving.push({ code: 'no_emirate', title: 'Set your home emirate', detail: 'You receive requests from the whole UAE either way. Your emirate is used only to break a tie between equally good matches.', fix: 'profile' });
  }
  if (!has(r.license_doc_path)) improving.push({ code: 'no_licence', title: 'Upload your trade licence', detail: 'Required before your account can be approved.', fix: 'documents' });
  // TRADES THE SUPPLIER'S OWN DOCUMENTS NAME THAT THEY HAVE NOT CONFIRMED (15 Sep 2026). Reads
  // supplier_capabilities.proposed_trades (_shared/supplier_doc_trades.ts). Only after the scope is
  // confirmed — before that, the blocking scope item above already sends them there.
  const held: string[] = Array.isArray(cap?.trades) ? cap.trades : [];
  const unconfirmed = cap?.confirmed_at && Array.isArray(cap.proposed_trades) ? (cap.proposed_trades as string[]).filter((c) => !held.includes(c)) : [];
  if (unconfirmed.length) {
    improving.push({ code: 'confirm_scope', params: { trades: unconfirmed }, title: 'Confirm what your company does',
      detail: `Your documents mention ${unconfirmed.length === 1 ? 'a trade' : unconfirmed.length + ' trades'} you have not confirmed: ${unconfirmed.join(', ')}. Tick ${unconfirmed.length === 1 ? 'it' : 'them'} in "What you can quote for" if your company does this work.`,
      fix: 'scope' });
  }
  // Warn while it is still fixable, not after the account has already been paused.
  for (const [col, label] of [['license_expiry', 'trade licence'], ['insurance_expiry', 'insurance certificate']] as [string, string][]) {
    const v = r[col]; if (!v) continue;
    const days = Math.round((new Date(v).getTime() - Date.now()) / 864e5);
    if (days >= 0 && days <= 30) improving.push({ code: 'expiring_' + col, params: { doc: col === 'insurance_expiry' ? 'insurance' : 'licence', days }, title: 'Your ' + label + ' expires in ' + days + ' day' + (days === 1 ? '' : 's'),
      detail: 'Once it expires your account is paused automatically and you stop receiving requests. Upload a renewed copy now to avoid that.', fix: 'documents' });
  }
  if (!has(r.phone)) improving.push({ code: 'no_phone', title: 'Add a contact number', detail: 'Customers cannot reach you after a reveal without one.', fix: 'profile' });

  return { ok: true,
    eligible: blocking.length === 0 && approved,
    blocking, improving,
    // Reach so far, measured rather than asserted.
    reach: { matched_requests: matched || 0, quotes_sent: quoted || 0, shortlist_size: 8 },
    // The mandatory six, from the one definition save_profile also enforces. The portal's
    // "Get matched" journey renders this list first, then the blocking items above.
    required_to_register: registrationChecklist(six),
    note_code: 'elig_note',
    note: 'Each request goes to a shortlist of up to 8 suppliers, ranked by how well your listing matches what the customer asked for. Suppliers anywhere in the UAE are eligible; being in the customer’s emirate only breaks a tie.' };
}

export const supplierCard = (sup: Supplier) => ({ id: sup.id, company_name: sup.company_name, approval_status: sup.approval_status, registration_status: sup.registration_status, license_expiry: sup.license_expiry || null, name_corrected: !!sup.name_corrected_from,
  // 13 Oct 2026 (ruling 1230 walk): the header renders why a registration is held and how long is left; neither field was sent, so
  // neither line ever showed. Prevented by scripts/checks/a_held_supplier_is_never_told_nothing_is_needed.test.mjs.
  licence_gate_reason: sup.licence_gate_reason ?? null, exception_due_at: sup.exception_due_at ?? null,
  // 10 Nov 2026: the signed Supplier Agreement lands asynchronously (z21_sign_supplier_on_acceptance; re-signed after 5 minutes by
  // fn_sales_engineer_resigns_unsigned_agreements). Until it lands the gate reads reg_terms, and the header said "Action required:
  // Signed supplier terms" to a supplier with nothing left to do. Prevented by
  // scripts/checks/a_supplier_agreement_that_did_not_land_is_signed_again.test.mjs.
  agreement_signing: agreementSigning(sup) });

/** Accepted, and no certificate for that acceptance yet: the agreement is being signed, nothing is asked of the supplier. */
export const agreementSigning = (sup: Pick<Supplier, 'accepted_terms_at' | 'signed_terms_at'>): boolean =>
  !!sup.accepted_terms_at && !(sup.signed_terms_at && Date.parse(sup.signed_terms_at) >= Date.parse(sup.accepted_terms_at));

// THE NOTICES THE ESTATE WROTE TO THIS SUPPLIER, AND THE TAB EACH ONE IS DEALT WITH IN (audit
// 21 Sep 2026, findings 5 and 6). Every message the company sends a supplier is a public.notifications
// row addressed to_role 'supplier' — the reveal ('quote_accepted', queued by trg_reveal_receipt), a
// new RFQ, an addendum, a customer message, an award to someone else. The bell used to know none of
// them, so a customer paying to reveal this supplier's quote changed nothing on the bell, and the
// only link a supplier ever got was the e-mail's, which points at the customer portal (/me). Here
// every notice carries the SUPPLIER portal tab it belongs to, never a URL: the portal of the
// recipient role is the one the reader is already in.
export const NOTICE_TAB: Record<string, string> = {
  quote_accepted: 'messages', new_message: 'messages', new_inquiry: 'rfqs', rfq_addendum: 'rfqs',
  job_awarded_other: 'rfqs', rfq_no_supplier: 'rfqs', doc_received: 'documents', registration_received: 'services',
  quote_spec_hold: 'quotes', quote_spec_released: 'quotes', quote_spec_regenerated: 'quotes',
};
const NOTICE_DAYS = 30;
export type Notice = { id: number; type: string; tab: string; inquiry_id: string | null; quote_id: string | null; at: string };

// The bell: counts fed by rows that already exist. unread_messages is the same count messages_api
// `threads` sums per chat (a customer message this supplier has not read, not blocked); spec_holds
// is the hold desk's live rows for this supplier's quotes; notices are the last 30 days of what the
// estate wrote to this supplier, newest first.
export async function buildNotifications(admin: Admin, supId: number) {
  const since = new Date(Date.now() - NOTICE_DAYS * 864e5).toISOString();
  const [{ count: unread }, { count: holds }, { data: rows }] = await Promise.all([
    admin.from('messages').select('id', { count: 'exact', head: true }).eq('supplier_id', supId).eq('sender', 'customer').eq('read_by_supplier', false).eq('blocked', false),
    admin.from('quote_spec_hold').select('id', { count: 'exact', head: true }).eq('supplier_id', supId).in('state', LIVE_HOLD),
    admin.from('notifications').select('id,type,inquiry_id,quote_id,created_at').eq('to_role', 'supplier').eq('lead_id', supId).gte('created_at', since).order('created_at', { ascending: false }).limit(20),
  ]);
  const notices: Notice[] = ((rows || []) as Row[])
    // A spec-hold notice (sales_engineer_*) belongs on the Quotes tab; anything unmapped is not
    // shown rather than shown with a guessed destination.
    .map((r) => ({ id: Number(r.id), type: String(r.type), tab: NOTICE_TAB[String(r.type)] || (String(r.type).startsWith('sales_engineer_') ? 'quotes' : ''), inquiry_id: r.inquiry_id || null, quote_id: r.quote_id || null, at: String(r.created_at) }))
    .filter((n) => n.tab);
  return { unread_messages: unread || 0, spec_holds: holds || 0, notices };
}

export async function buildDashboard(admin: Admin, sup: Supplier): Promise<{ status: number; body: Row }> {
  const [{ data: stats, error }, alerts, eligibility, impact, notifications] = await Promise.all([
    admin.rpc('fn_supplier_stats', { p_supplier_id: sup.id }),
    buildAlerts(admin, sup.id),
    buildEligibility(admin, sup.id),
    admin.rpc('fn_supplier_document_impact', { p_lead_id: sup.id }),
    buildNotifications(admin, sup.id),
  ]);
  if (error) return { status: 500, body: { error: error.message } };
  return { status: 200, body: { ok: true, supplier: supplierCard(sup), stats,
    // The same count the separate overview action reads; eligibility already measured it.
    active_matches: eligibility.reach.matched_requests, alerts, alerts_count: alerts.length, eligibility,
    // A failed impact read is null, and the panel says it could not load rather than showing zeros.
    document_impact: impact?.error ? null : { ok: true, ...(impact?.data || {}) },
    notifications } };
}
