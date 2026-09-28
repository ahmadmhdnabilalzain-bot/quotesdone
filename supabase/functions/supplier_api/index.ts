import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD, SAFE_DOCS } from '../_shared/attachment.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { asLocale } from '../_shared/registered_locale.ts';
import { arDays } from '../_shared/ar_days.ts';
// MALWARE WATCH, 9 Sep 2026. Every file a supplier sends is hashed and looked up before it reaches
// storage; a hash VirusTotal already knows to be malicious is refused here rather than stored,
// forwarded and served back. See _shared/malware.ts for why the lookup blocks and the analysis does not.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { defaultDeps } from '../_shared/think.ts';
import { quoteTerms } from '../_shared/reasoned_suppliers.ts';
import { storedAt } from '../_shared/stored_at.ts';
import { CANONICAL_ORIGIN, siteReturnBase } from '../_shared/site_origins.ts';
import { capabilityState, capabilityConfirm } from '../_shared/supplier_capability.ts';
import { servicesState, servicesResolve, servicesRewrite, servicesSaveRewrite, transcribeServiceNote, voiceEnabled } from '../_shared/supplier_services.ts';
import { boqWithArabic } from '../_shared/boq_arabic.ts';
import { boqReadings, liveReadingStore } from '../_shared/reasoned_documents.ts';
import { arabicOf, nativeArabic } from '../_shared/reasoned_governance.ts';
import { searchResult, SEARCH_COLUMNS, type LeadHit } from './search_result.ts';
import { mandatorySixMissing, sixInWords } from '../_shared/supplier_registration.ts';
import { clientIp, currentSupplierTermsVersion, supplierTermsRecord } from '../_shared/supplier_terms.ts';
import { proposeTradesFromDocs, type DocIn } from '../_shared/supplier_doc_trades.ts';
import { licenceModelPayload, licenceNameFromModel, readExpiry, readLicenceName } from '../_shared/document_expiry.ts';
// The sales engineer's hold desk (14 Sep 2026): exact specs per line, delivery, installation,
// warranty and the ex-VAT price, or the quote is held; options are separate quotations.
import { approve, fillIn, finishArabic, formSchema, gate, pdfDoc, supabaseRepo, type Render } from '../_shared/line_specs/workflow.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { applyReading, readQuote } from '../_shared/reasoned_matching.ts';
import { assessQuote, requirementsOf } from '../_shared/line_specs/assess.ts';
import type { Attr } from '../_shared/line_specs/model.ts';
import { checklistAttrs, chooseChecklist, needsChecklist, reasonLineSpecs, unionOf, type Checklist, type ChecklistRow } from '../_shared/line_specs/reasoned_specs.ts';
import type { Line } from '../_shared/line_specs/assess.ts';
import type { Ctx } from '../_shared/line_specs/workflow.ts';
import { optionAmount, splitOptions } from '../_shared/line_specs/options.ts';
import { readVat } from '../_shared/line_specs/vat.ts';
import { findTrn } from '../_shared/identity_numbers.ts';
import { requestDelivery } from '../_shared/deliver.ts';
import { DOC_VERSION, completenessOf, inquiryDocument, itemsOfRows, quoteDocument, quoteRef, type InquiryDocRow, type Item } from '../_shared/quote_documents.ts';
import { duesLines, supplierInvoiceDocument, supplierReceiptDocument, type SupplierPayment } from '../_shared/supplier_payment_documents.ts';
import { jobAlias } from '../_shared/quote_labels.ts';
import { deriveLineFields, deriveTermsFromScope } from '../_shared/line_specs/derive.ts';
// A DRAWING PAGE THAT FAILS TO SIGN IS COUNTED, LOGGED AND RAISED - never silently dropped from the
// inbox (18 Sep 2026, sales_engineer). See _shared/drawing_pages.ts for the production measurement.
import { drawingWithheld, signRedactedDrawings } from '../_shared/drawing_pages.ts';
// Inquiries received and the quotation review with the sales engineer (15 Sep 2026).
import { inquiryDocuments, MAX_FILE, REVIEW_ACTIONS, reviewAction, safeInquiry } from './quote_review_actions.ts';
import { supabaseReviewRepo } from './quote_review_flow.ts';
import { jobNo, readWorking, reviewQuotation, sanitizeSpec, sanitizeTermsSpec } from './quote_review.ts';
import { issueAsMissing, resolvedFrom, withResolved, workingFromStoredQuote, workingFromSubmit } from './submit_review.ts';
import { SANCTIONED_REFUSAL, SANCTIONED_REGISTRATION_REFUSAL, sanctionedEmail, sanctionedLeads } from '../_shared/sanctioned.ts';
import { COMPANY_ALREADY_REGISTERED, isDuplicateCompany, type LeadWriter, registrationRefusal, updateLeadSettingAsideClashingLicence } from '../_shared/duplicate_company.ts';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
// 15 Sep 2026 (sales_engineer): trade_license_no, license_expiry and license_doc_path are NOT here. They
// are written only by the upload paths, from the stored file and what license_extract read off it; from
// this list a supplier could type their own expiry or point at a path that is not their licence.
// bank_name, bank_account_name, bank_iban and iban_doc_path left this list on 21 Sep 2026: the columns are
// being dropped/purged (scripts/sql/the_founder_removed_bank_details_from_the_estate.sql). Money moves both
// directions through Stripe, so the estate never holds a supplier's bank details — founder instruction 527.
const PROFILE_COLS = ['contact_name','signatory_name','emirates_id','phone','products','services','description','certifications','founded_year','company_type','company_size','license_authority','trn','egr_doc_path','egr_doc_name','egr_number'];
const YEAR_MS = 365 * 864e5;
const CONCLUDED = ['completed','closed','cancelled'];
// EVIDENCE FIX 19 Jul 2026 -----------------------------------------------------------------
// Terms acceptance here recorded WHEN (accepted_terms_at) and WHICH VERSION
// (accepted_terms_version) but not FROM WHERE. The leads.accepted_terms_ip column already
// existed and auth_api / kyc already populated it - supplier_api, the main registration
// surface, was the one path that did not.
//
// Why it matters: the non-response fine (3%) drives an automated collections -> legal
// escalation path. If a supplier disputes the fine, the platform must evidence that THIS
// party accepted THAT version of the terms at THAT time from THAT address. Timestamp plus
// version without an originating IP is materially weaker evidence.
//
// Same derivation as auth_api line 9 so the two paths produce comparable records.
const clip = (v: unknown, n: number) => (v == null || String(v).trim() === '') ? null : String(v).slice(0, n);
// The identity scrubbers (scrubIdentity, inboxField, inboxBoq) live in ./identity_scrub.ts.
import { inboxBoq, inboxField, scrubIdentity } from './identity_scrub.ts';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const numOrNull = (v: unknown) => { const n = Number(v); return isFinite(n) && n !== 0 ? n : (isFinite(n) && String(v).trim() !== '' ? n : null); };
// EXACT SPECS FOR A TRADE WITH NO LINE READER (23 Sep 2026). The trade's knowledge pack says what a line
// must state (fn_trade_spec_checklist); think() judges what the supplier's lines already state
// (_shared/line_specs/reasoned_specs.ts). Under the model hold nothing is judged and every required spec
// is asked, so the quote is held until it is stated. A trade with a reader, or no checklist, is unchanged.
// mode 'gate': choose the checklist (reasoned) and judge the lines — once per submission. 'stored': the
// live hold's own checklist, read back for fill-in and approval, no reasoning. 'preflight': no reasoning,
// a prediction only (one checklist, or every checklist together).
async function specChecklist(category: string | null, quoteId: string, mode: 'gate' | 'stored' | 'preflight' = 'gate'): Promise<{ checklist?: Attr[]; reason?: Ctx['reason'] }> {
  if (!category || !needsChecklist(category)) return {};
  if (mode === 'stored') {
    const { data: h } = await admin.from('quote_spec_hold').select('original_snapshot').eq('quote_id', quoteId)
      .in('state', ['open', 'awaiting_approval']).order('id', { ascending: false }).limit(1).maybeSingle();
    const rows = ((h?.original_snapshot as { checklist?: ChecklistRow[] } | null)?.checklist ?? []) as ChecklistRow[];
    return rows.length ? { checklist: checklistAttrs(rows) } : {};
  }
  const { data, error } = await admin.rpc('fn_trade_spec_checklist', { p_category: category });
  const lists = (!error && Array.isArray(data) ? data : []) as Checklist[];
  if (!lists.length) {
    // Not held on an empty list, and not silently: the missing pack is an IT finding the knowledge work closes.
    try { await admin.rpc('fn_it_engineer_finding_upsert', { p_issue_key: 'spec_checklist_missing:' + category, p_title: 'A trade with no line reader has no spec checklist, so its quotes cannot be held for missing specs',
      p_where: 'edge function supplier_api', p_blast: 'customer_facing', p_affected: 1, p_evidence: { category, quote_id: quoteId, error: error?.message ?? null }, p_ruled_out: [], p_undetermined: [], p_raised_by: 'sales_engineer' }); } catch (_e) { /* the gate goes on */ }
    return {};
  }
  if (mode === 'preflight') return { checklist: checklistAttrs(lists.length === 1 ? lists[0].specs : unionOf(lists)) };
  const deps = defaultDeps(admin, 'supplier_api');
  const { data: lineRows } = await admin.from('quote_items').select('*').eq('quote_id', quoteId).order('line_no', { ascending: true }).limit(60);
  const picked = await chooseChecklist(deps, { checklists: lists, lines: (lineRows ?? []) as Line[], trade: category, quoteId });
  const checklist = checklistAttrs(picked.rows);
  if (!checklist.length) return {};
  return { checklist, reason: (lines, cl) => reasonLineSpecs(deps, { lines, checklist: cl, trade: category, quoteId }) };
}
async function secretVal(key: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return data?.value || null; }
// A SUPPLIER ACTS ONLY ON A JOB IT WAS MATCHED TO (audit 22 Sep 2026, finding SP-N-03).
//
// `inbox` has always been scoped to public.inquiry_matches, and the quotation-review actions reach the job
// only through it — but submit_quote and extract_quote took body.inquiry_id and never asked. Any approved
// supplier could therefore price, and store a quotation file against, any enquiry in the estate whose uuid
// it held; fn_supplier_opportunities handed out those uuids for every open enquiry, its own reason line
// reading "Outside your registered trade". One row in inquiry_matches is the platform's record that this
// enquiry was sent to this company, so that row is the question both doors now ask.
//
// It answers with the id or with null, and the caller returns 404 — not 403. A 403 would confirm that the
// uuid names a real enquiry; a job this supplier was not matched to must not exist for them. It FAILS
// CLOSED: an unreadable inquiry_matches is null, which refuses, rather than an assumed match.
async function matchedInquiry(supplierId: number, raw: unknown): Promise<string | null> {
  const id = typeof raw === 'string' && UUID_RE.test(raw) ? raw.toLowerCase() : null;
  if (!id) return null;
  const { data, error } = await admin.from('inquiry_matches').select('id').eq('inquiry_id', id).eq('supplier_id', supplierId).limit(1);
  if (error || !data || !data.length) return null;
  return id;
}
// A QUOTATION FILE LIVES UNDER ITS OWN SUPPLIER'S PREFIX (audit 22 Sep 2026, finding SP-N-04). Both doors
// took original_file_path verbatim from the request and wrote it onto the quote row, so a supplier could
// attach ANY object in the quote-files bucket — another supplier's quotation — to its own quote and have
// the platform serve it back.
//
// TWO PREFIXES, BOTH MEASURED, because one would have broken the main door. extract_quote writes
// `quotes/<supplier id>/<inquiry>/…` and the quotation review writes `review/<supplier id>/<inquiry>/…`
// (quote_review_flow.ts line 270) — production on 22 Sep 2026 holds two quotes with an original file and
// BOTH are `review/126512/…`, so a rule naming only `quotes/` would have refused every quotation the
// chat submits. Either prefix, and the supplier id in it must be the caller's. '..' is refused with them
// because a stored path is later signed, not resolved.
const ownQuoteFile = (p: unknown, supplierId: number): boolean => {
  const s = String(p ?? '');
  return (s.startsWith(`quotes/${supplierId}/`) || s.startsWith(`review/${supplierId}/`)) && !s.includes('..');
};
const NOT_MY_FILE = { error: 'file_not_yours', code: 'file_not_yours', message: 'That file is not one of yours. Please attach your quotation again.' };
// THE JOB AS THE REVIEW MAY READ IT. `inbox` run in-process with the caller's own session is the one
// door onto an inquiry a supplier is allowed through: it is scoped to inquiry_matches, it applies the
// scrubbers and the reveal gate, and it withholds a BOQ or a brief it cannot prove clean. The quotation
// review reads the job through it in the chat, and now reads it through it at submit_quote and
// spec_approve too, so the three cannot disagree about what the supplier was pricing.
async function safeInquiryOf(req: Request, jwt: string, inquiryId: string) {
  const r = await handle(new Request(req.url, { method: 'POST', headers: { Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'inbox', inquiry_id: inquiryId }) }));
  const j = await r.json().catch(() => ({}));
  // deno-lint-ignore no-explicit-any
  const row = (j.inquiries || []).find((x: any) => String(x.id) === inquiryId);
  return row ? safeInquiry(row) : null;
}
// The same switch supplier_portal reads: the model may be asked about a document only when the
// founder has turned it on (22 Sep 2026, SEATS-02).
async function flagOn(key: string): Promise<boolean> { return /^(on|true|1)$/i.test(String(await secretVal(key) || '').trim()); }
function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
// AUDIT 4.2 (3 Aug 2026) ------------------------------------------------------------------
// This function used to decide the registration state itself, from registered_supplier_count()
// against pricing_config.supplier_free_count, evaluated AFTER the insert - so the test was
// "N < 1000" when N had already become 1000, and only 999 suppliers were ever free. Supplier
// #1000 came out of it simultaneously subscription_exempt=true (per fn_assign_founding_rank)
// and registration_status='due', registration_fee_due=1000. It also had no date test at all,
// so it marked suppliers 'due' - which submit_quote below refuses on - a full year before the
// contractual charging date of 1 Aug 2027. And it stamped registration_paid_at on free
// suppliers, recording a payment that never happened.
//
// The rule now lives in exactly one place: fn_supplier_registration_state(), enforced on write
// by trg_bz_supplier_registration_state on public.leads. This function no longer decides
// anything - it touches the row so the trigger derives the state, then reports what the single
// source of truth says.
// touch=false when the caller has just updated the row itself (claim): the trigger has already derived the state.
async function setRegistration(leadId: number, touch = true) {
  if (touch) await admin.from('leads').update({ portal_updated_at: new Date().toISOString() }).eq('id', leadId);
  const { data: st, error } = await admin.rpc('fn_supplier_registration_state', { p_lead_id: leadId });
  if (error || !(st as any)?.ok) return { status: 'unknown', fee_due: 0, may_quote: true, reason: 'registration_state_unavailable' };
  const s = st as any;
  return { status: String(s.status), fee_due: Number(s.fee_due || 0), may_quote: s.may_quote !== false, founding_rank: s.founding_rank ?? null, charging_starts: s.charging_starts ?? null, reason: String(s.reason || '') };
}
// profile_ai and supplier_review were deleted from the repository and from production by the
// 137-function sweep (182308b, 7 Sep 2026); on 14 Sep get_edge_function answers "Function not found".
// Their URL returns a 404 JSON body, which the old review helper returned AS IF it were a review —
// save_profile then wrote a blank ai_review_notes and "AI check: clean" into the registration mail.
// 22 SEP 2026: both calls are REMOVED rather than guarded. A call to a function that is not deployed
// is dead code that looks alive; scripts/checks/no_function_calls_an_undeployed_function.test.mjs now
// fails the build if one comes back. Both were advisory and never gated registration.
//
// EMAIL PROOF (14 Sep 2026). login_otp records proof of e-mail ownership with an UPDATE on
// leads.claimed_by — but at sign-up no lead is claimed by that address yet (create_company or claim
// runs afterwards), so owner_email_verified stayed false for every self-registered and every invited
// supplier, and the e-mail item of the mandatory six could never be ticked. The durable proof is the
// used login OTP in email_verifications; it is read once when the company becomes this account's.

// THE POST THAT BROUGHT THEM (sales_engineer with marketing, 23 Sep 2026, instruction 865). When a company
// becomes an account's (create_company or claim), the first visit's UTM the browser kept (src/lib/firstTouch.ts)
// is validated and stored by fn_marketing_first_touch_record. Attribution never blocks a registration.
async function recordFirstTouch(leadId: number, touch: unknown): Promise<void> {
  if (!touch || typeof touch !== 'object') return;
  const r = await admin.rpc('fn_marketing_first_touch_record', { p_lead_id: leadId, p_touch: touch }).then((x) => x, (e) => ({ error: { message: String(e) } }));
  if (r.error) console.error('first touch not recorded for lead ' + leadId + ': ' + r.error.message);
}
async function emailProven(email: string) {
  const { data } = await admin.from('email_verifications').select('id').eq('email', email).eq('purpose', 'login').not('used_at', 'is', null).limit(1);
  return !!(data && data.length);
}
async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await requestDelivery(admin, rows); } catch (_e) { /* */ } }

// THE COMMERCIAL ACCEPT RULE, read from the stored quote (14 Sep 2026). It lived inline in
// submit_quote; approving a regenerated quotation must clear the same bar, so both call this.
// 5 Aug 2026: completeness is a property of the QUOTE, not of the screen it arrived through — an
// uploaded quotation with priced lines, validity, warranty and lead time is as complete as a typed one.
async function acceptRule(qid: string) {
  const { data: q } = await admin.from('quotes').select('lead_time,validity,warranty').eq('id', qid).maybeSingle();
  const { data: qi } = await admin.from('quote_items').select('unit_price,amount').eq('quote_id', qid);
  // deno-lint-ignore no-explicit-any
  let score: any = null; try { const { data } = await admin.rpc('fn_quote_structured_score', { p_quote: qid }); score = data; } catch (_e) { /* */ }
  const submittable = !!(score && score.submittable);
  try { await admin.from('quotes').update({ submittable }).eq('id', qid); } catch (_e) { /* */ }
  const requireStructured = (await secretVal('require_structured_quotes')) === 'true';
  const priced = (qi || []).filter((r: { unit_price: number | null; amount: number | null }) => (Number(r.unit_price) || 0) > 0 || (Number(r.amount) || 0) > 0).length;
  const formComplete = priced >= 1 && !!q?.validity && !!q?.warranty && !!q?.lead_time;
  return { accept: submittable || formComplete || !requireStructured, submittable, formComplete, requireStructured, priced, score };
}
async function notifyNewQuote(inquiryId: string) {
  try {
    const { data: inq } = await admin.from('inquiries').select('customer_id,summary').eq('id', inquiryId).maybeSingle();
    if (!inq?.customer_id) return;
    const { data: c } = await admin.from('customers').select('email').eq('id', inq.customer_id).maybeSingle();
    if (c?.email) await notify([{ type: 'new_quote', to_email: c.email, to_role: 'customer', inquiry_id: inquiryId, subject: 'You have a new quote on QuotesDone', body: 'A supplier submitted a quote for your request' + (inq.summary ? ': ' + inq.summary : '') + '. Log in to view the full quotation and compare.' }]);
  } catch (_e) { /* */ }
}
// "WE NOTIFY DIRECTLY" (founder, 14 Sep 2026). The sales engineer's notices are delivery requests
// customer_support sends (#614). Queued rows would otherwise wait for the next outbox tick; this asks
// both of support's dispatchers to send now. Best-effort: the scheduled flush still sends if it fails.
async function kickDelivery() {
  const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return;
  await Promise.allSettled(['send_outbox', 'send_whatsapp'].map((fn) => fetch(`${SUPA_URL}/functions/v1/${fn}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret }) })));
}
/** The supplier as the hold desk addresses them: every channel on file, in their language. */
// deno-lint-ignore no-explicit-any
const supplierOf = (sup: any, email: string) => ({ id: Number(sup.id), email: email || null, phone: sup.whatsapp || sup.phone || null, locale: sup.locale || null });
/** Offer a quote that has cleared the hold gate to the accept rule; on pass it goes to the customer. */
async function acceptLive(qid: string, inquiryId: string, notifyCustomer: boolean) {
  // Quote quality is scored by structure in trg_quote_quality; the category aspects are no longer read by the
  // model (24 Sep 2026, it_engineer, quote_quality_trade_keys_and_repeat_requests_are_code_not_the_model.sql).
  const r = await acceptRule(qid);
  // deno-lint-ignore no-explicit-any
  let coaching: any = null;
  if (r.accept) {
    try { await admin.from('quotes').update({ status: 'submitted' }).eq('id', qid); } catch (_e) { /* */ }
    await admin.from('inquiries').update({ status: 'quoted' }).eq('id', inquiryId).in('status', ['sent', 'quoted']);
    if (notifyCustomer) await notifyNewQuote(inquiryId);
    if (!r.submittable) { try { const { data } = await admin.rpc('fn_quote_coach', { p_quote: qid }); coaching = data; } catch (_e) { /* */ } }
    return { accepted: true, submittable: r.submittable, score: r.score, coaching };
  }
  try { await admin.from('quotes').update({ status: 'draft' }).eq('id', qid); } catch (_e) { /* */ }
  try { const { data } = await admin.rpc('fn_quote_coach', { p_quote: qid }); coaching = data; } catch (_e) { /* */ }
  return { accepted: false, submittable: false, score: r.score, coaching };
}

// DOCUMENTS-LEAD + DOUBLE CONFIRMATION 29 Jul 2026 ---------------------------------------------
// Spec: "These documents are the PRIMARY data source. An agent extracts information from them to
// understand what the supplier does", and "the supplier is also given the option to manually write
// the services they provide (for DOUBLE CONFIRMATION against the extracted data)".
//
// Until now process_docs wrote extracted services only when the supplier had typed NOTHING
// (`&& !sup.services`), so the documents were the FALLBACK and the typed text was the source of
// truth - the exact inversion of the spec - and the two were never compared, so no mismatch could
// ever surface.
//
// Now: extracted services ALWAYS win the canonical leads.services field, the supplier's typed text
// is preserved as the DECLARED value, and the two are cross-checked on every extraction and on
// every profile save.
//
// WHERE THE DECLARED TEXT AND THE OUTCOME LIVE, AND WHY agent_actions: one row per check, kind
// 'supplier_services_crosscheck', target_table/target_id = leads/<id>, whole comparison in the
// jsonb `detail` (verdict, overlap, shared terms, extracted list, declared text, note). No
// migration is added and no other feature's column is borrowed: every leads JSONB column already
// has an owner (ai_review_flags was REWRITTEN WHOLESALE by this function's own review helper on every
// save until 22 Sep 2026, and still belongs to that review; machinery / brands_carried /
// client_references / iso_certifications / manufacturer_authorizations belong to capability
// enrichment) and supplier_capabilities is owned end to end by capability_agent, which upserts
// whole rows including review_status. agent_actions is the platform's existing durable, queryable
// review surface, it is where the spec asks conflicts to be raised anyway, and unlike a single
// column it keeps the FULL HISTORY of what the supplier declared versus what the documents said.
// Query it with: select detail->>'verdict', detail->>'declared_services' from agent_actions
// where kind = 'supplier_services_crosscheck'.
//
// A conflict NEVER blocks registration - the founder wants full automation, so we flag and carry on.
const SVC_STOP = new Set(['and','the','for','with','all','our','any','are','you','your','uae','dubai','abu','general','other','service','work','job','provide','providing','provider','company','llc','etc','type','various','including','include','solution']);
const svcStem = (w: string) => (w.length > 4 && w.endsWith('ies')) ? w.slice(0, -3) + 'y' : ((w.length > 3 && w.endsWith('s')) ? w.slice(0, -1) : w);
function svcTerms(v: unknown): string[] {
  return String(v == null ? '' : v).toLowerCase().replace(/[^a-z0-9؀-ۿ]+/g, ' ').split(/\s+/).map(svcStem).filter((w) => w.length > 2 && !SVC_STOP.has(w));
}
// Term overlap rather than string equality: the documents may say "supply and installation of VRF
// air conditioning systems" where the supplier typed "AC installation", and those two agree.
// Containment (shared / smaller set) is used rather than Jaccard so a long extracted list is not
// punished against a short typed line. 60%+ = agreement, some shared terms = partial overlap,
// nothing in common = conflict.
function crossCheckServices(extracted: string[], declared: unknown) {
  const dText = String(declared == null ? '' : declared).trim();
  const eText = extracted.join(', ');
  const eSet = new Set(svcTerms(eText));
  const dSet = new Set(svcTerms(dText));
  const q = (s: string) => '"' + s.slice(0, 300) + '"';
  if (!eSet.size) return { verdict: 'no_extraction', overlap: 0, shared: [] as string[], note: 'Nothing usable was extracted from the documents, so there was nothing to cross-check the supplier text against.' };
  if (!dSet.size) return { verdict: 'not_declared', overlap: 0, shared: [] as string[], note: 'Supplier typed no services of their own, so the document extraction ' + q(eText) + ' stands unconfirmed. Not a conflict.' };
  const shared = [...dSet].filter((w) => eSet.has(w));
  const overlap = shared.length / Math.min(eSet.size, dSet.size);
  const verdict = overlap >= 0.6 ? 'agreement' : (shared.length ? 'partial' : 'conflict');
  const head = verdict === 'agreement' ? 'Documents and supplier agree' : (verdict === 'partial' ? 'Partial overlap' : 'CONFLICT');
  return { verdict, overlap, shared, note: head + ': documents say ' + q(eText) + ', supplier typed ' + q(dText) + ' (' + Math.round(overlap * 100) + '% overlap' + (shared.length ? ', shared: ' + shared.slice(0, 8).join(', ') : ', nothing in common') + '). Documents are the source of truth; the typed text is kept as the declared value.' };
}
// The declared text has to survive the fact that leads.services now holds the EXTRACTED value -
// re-running extraction would otherwise compare the documents against themselves. The most recent
// cross-check row is the durable record of what the supplier actually typed.
async function priorCrossCheck(supplierId: number) {
  try {
    const { data } = await admin.from('agent_actions').select('detail').eq('kind', 'supplier_services_crosscheck').eq('target_id', String(supplierId)).order('id', { ascending: false }).limit(1).maybeSingle();
    if (!data) return { found: false, declared: null as unknown, extracted: [] as string[] };
    const d = (data.detail || {}) as Record<string, unknown>;
    return { found: true, declared: (d.declared_services ?? null) as unknown, extracted: Array.isArray(d.extracted_services) ? (d.extracted_services as string[]) : [] };
  } catch (_e) { return { found: false, declared: null as unknown, extracted: [] as string[] }; }
}
async function recordServicesCrossCheck(supplierId: number, companyName: unknown, extracted: string[], declared: unknown) {
  const cc = crossCheckServices(extracted, declared);
  const conflict = cc.verdict === 'conflict';
  try {
    await admin.from('agent_actions').insert({
      agent: 'sales_engineer',
      kind: 'supplier_services_crosscheck',
      status: conflict ? 'needs_review' : 'auto_done',
      risk: conflict ? 'medium' : 'low',
      title: 'Services cross-check (' + cc.verdict + ') — ' + String(companyName || ('supplier #' + supplierId)).slice(0, 120),
      recommendation: conflict ? "The documents and the supplier's own description have nothing in common. Registration was NOT blocked. Open the trade licence / company profile and correct leads.services if the extraction is wrong, or ask the supplier what they actually do." : cc.note,
      detail: { supplier_id: supplierId, verdict: cc.verdict, overlap: Math.round(cc.overlap * 100) / 100, shared_terms: cc.shared.slice(0, 20), extracted_services: extracted, declared_services: declared == null ? null : String(declared).slice(0, 2000), note: cc.note, checked_at: new Date().toISOString(), source: 'supplier_api' },
      target_table: 'leads',
      target_id: String(supplierId),
    });
  } catch (_e) { /* the cross-check is evidence, not a gate - it must never break registration */ }
  return cc;
}
/** The regenerated quotation's renderer: the standard quotation (quoteDocument via workflow.ts pdfDoc) in the
 * supplier's language, under the one alias this supplier carries on this job. An Arabic quotation whose lines are
 * not all translated by reasoning yet is not rendered: 'arabic_pending' (decision point trade_glossary_ar). */
// deno-lint-ignore no-explicit-any
function regenRender(q: any, sup: any, inqRow: any): Render {
  return async (rec) => {
    const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return null;
    const [{ data: safeInq }, { data: matches }] = await Promise.all([
      admin.from('inquiries_supplier_safe').select('emirate').eq('id', q.inquiry_id).maybeSingle(),
      admin.from('inquiry_matches').select('id,supplier_id').eq('inquiry_id', q.inquiry_id).order('id', { ascending: true }),
    ]);
    const order = [...new Set((matches || []).map((m: { supplier_id: number }) => Number(m.supplier_id)))];
    const letter = jobAlias(order, Number(sup.id)).replace(/^Supplier /, '');
    const lang: 'en' | 'ar' = String(sup.locale || '').toLowerCase().startsWith('ar') ? 'ar' : 'en';
    const d = await nativeArabic(defaultDeps(admin, 'supplier_api'), (arTexts) => pdfDoc(rec, { inquiry: { id: String(q.inquiry_id), rfq_no: inqRow?.rfq_no ?? null, category: inqRow?.category ?? null, emirate: safeInq?.emirate ?? null }, letter, lang, arTexts }), { subject: { quote_id: rec.quote_id, kind: 'regenerated_quotation' } });
    if (!d.doc) {
      // The quote waits by its own id, whoever filed the lines first; the replay renders it when they are all in.
      if (d.missing.length) await admin.rpc('fn_arabic_document_wait', { p_quote: String(rec.quote_id), p_texts: d.missing });
      return 'arabic_pending';
    }
    const r = await fetch(`${SUPA_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, ...d.doc.body, bucket: 'quote-files', folder: `quotes/${sup.id}/${q.inquiry_id}/regenerated`, name: `quotation_${String(rec.quote_id).slice(0, 8)}_option${rec.option_no}_${lang}` }) });
    const j = await r.json().catch(() => null);
    return j?.ok ? { bucket: String(j.bucket), path: String(j.path) } : null;
  };
}

/** THE REPLAY'S EFFECT (internal credential only, from _shared/reasoned_delivery.ts): a regenerated Arabic quotation
 * that waited for its reasoned translation is rendered now and its approval request sent (workflow.ts finishArabic). */
async function arabicFinish(quoteId: string): Promise<Response> {
  if (!UUID_RE.test(quoteId)) return J({ ok: false, code: 'not_found' }, 404);
  const repo = supabaseRepo(admin, { dispatch: kickDelivery });
  const q = await repo.quote(quoteId);
  if (!q) return J({ ok: false, code: 'not_found' }, 404);
  const { data: sup } = await admin.from('leads').select('id,locale,whatsapp,phone,claimed_by').eq('id', q.supplier_id).maybeSingle();
  if (!sup) return J({ ok: false, code: 'not_found' }, 404);
  const { data: inqRow } = await admin.from('inquiries').select('category,spec,rfq_no').eq('id', q.inquiry_id).maybeSingle();
  const { count: optCount } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('inquiry_id', q.inquiry_id).eq('supplier_id', sup.id);
  const ctx = { category: inqRow?.category ?? null, requirements: requirementsOf(inqRow?.spec), ref: jobNo({ id: String(q.inquiry_id), rfq_no: inqRow?.rfq_no }), multiOption: (optCount || 0) > 1 };
  const out = await finishArabic(repo, quoteId, supplierOf(sup, String(sup.claimed_by || '')), ctx, regenRender(q, sup, inqRow));
  // Done, or nothing waits any more: the waiter row goes. still_pending keeps it for the next replay.
  if (out.ok || out.code === 'not_pending' || out.code === 'not_found') await admin.from('arabic_document_waiter').delete().eq('quote_id', quoteId);
  else {
    // A render that fails is counted; after 5 it stops being replayed (fn_arabic_waiters_ready) and the sales engineer is told.
    const { data: w } = await admin.from('arabic_document_waiter').select('attempts').eq('quote_id', quoteId).maybeSingle();
    const attempts = Number(w?.attempts ?? 0) + 1;
    await admin.from('arabic_document_waiter').update({ attempts, last_tried_at: new Date().toISOString() }).eq('quote_id', quoteId);
    if (attempts >= 5) await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'arabic_quotation_render_failed', status: 'pending', risk: 'medium',
      title: 'The Arabic regenerated quotation could not be rendered after 5 tries', detail: { quote_id: quoteId, last: out }, target_table: 'quotes', target_id: quoteId });
  }
  return J(out, out.ok ? 200 : 409);
}

// Named so the quotation review can run this same function in-process with the caller's own session.
const handle = async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  // KEEP-WARM (resilience_ping; 28 Sep 2026 it_engineer, supplier journey). No auth, no DB: the isolate is
  // what needs exercising. See warmPortal() in resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    // The one internal door, before any session is asked for: the replay of a held Arabic translation.
    const peek = await req.clone().json().catch(() => ({}));
    if (peek?.__secret && peek.action === 'spec_arabic_finish') {
      const auth = await requireInternal(admin, String(peek.__secret), 'supplier_api');
      if (!auth.ok) return J({ error: 'forbidden' }, 403);
      return await arabicFinish(String(peek.quote_id || ''));
    }
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026). Above the action
    // switch, before the body is even read, because this function serves forty-odd actions and a
    // per-action guard is a list somebody will one day add to without reading. Asked of
    // public.sanctions_ban and NOT of leads.banned: a supplier banned for unpaid dues must keep
    // reaching supplier_pay to clear it.
    if (await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);
    const body = await req.json().catch(() => ({})); const action = body.action;

    // INQUIRIES RECEIVED and QUOTATIONS SUBMITTED (founder, 15 Sep 2026) — quote_review_actions.ts.
    // `self` runs this same function in-process with the caller's own session, so the conversation
    // reads the job only through `inbox` and its scrubbers, and submits only through `submit_quote`.
    if (REVIEW_ACTIONS.has(action)) {
      const self = async (b: Record<string, unknown>) => {
        const r = await handle(new Request(req.url, { method: 'POST', headers: { Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' }, body: JSON.stringify(b) }));
        return { status: r.status, json: await r.json().catch(() => ({})) };
      };
      const { data: sup } = await admin.from('leads').select('id,company_name,locale').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // The upload gate every supplier file passes: type by bytes, size, then the malware lookup.
      const scan = async (b64: string, filename: string, mime: string) => {
        const sc = await sanitizeAndScan({ input: b64, declaredMime: mime, filename, allow: SAFE_DOCS, maxBytes: MAX_FILE,
          scan: { source: 'supplier_api.quote_review', subject: String(sup.id), filename, bucket: 'quote-files' } });
        if (!sc.ok) return { ok: false as const, status: sc.status, code: String(sc.body.error || 'file_refused'), message: String(sc.body.message || 'That file cannot be accepted.') };
        return { ok: true as const, bytes: sc.result.bytes, mime: sc.result.mime, name: safeFilename(filename, sc.result.mime) };
      };
      const out = await reviewAction({ sup: { id: Number(sup.id), company_name: sup.company_name ?? null, locale: sup.locale ?? null }, email, self, body, repo: supabaseReviewRepo(admin), scan,
        readTerms: async (text: string) => (await quoteTerms(defaultDeps(admin, 'supplier_api'), { text })).value,
        // The review reads the quotation the way the hold gate will (reasoned_matching.ts readQuote); held: nothing is read, every detail is asked.
        readWorking: (inq, w) => readWorking(defaultDeps(admin, 'supplier_api'), inq, w, 'review:' + inq.id + ':' + sup.id) });
      return J(out.json, out.status);
    }

    // claimed_by is the account e-mail. Registration SHOWS it with its verification state rather
    // than asking for it — the supplier signed in with it, so a field here could only ever be
    // answered with the value we already hold.
    if (action === 'me') { const { data } = await admin.from('leads').select('id,company_name,claimed_by,emirate,sector,business_role,products,services,description,certifications,company_type,company_size,founded_year,service_emirates,claimed,verified,approval_status,ai_review_notes,registration_submitted_at,accepted_terms_at,accepted_terms_version,contact_name,signatory_name,phone,trade_license_no,license_authority,license_expiry,license_city,name_corrected_from,owner_email_verified,doc_extracted_at,trn,license_doc_path,egr_doc_path,egr_doc_name,egr_number,company_profile_doc_path,catalog_doc_paths,registration_status,registration_fee_due,registration_expires_at,app_rating,app_reviews,rating,reviews,licence_gate_reason,exception_due_at').eq('claimed_by', email).maybeSingle(); return J({ supplier: data ? { ...data, terms_current: await secretVal('terms_version') } : null }); }
    if (action === 'search') { const q = String(body.q || '').slice(0, 60); if (q.length < 2) return J({ results: [] }); const { data } = await admin.from('leads').select(SEARCH_COLUMNS).ilike('company_name', '%' + q + '%').order('reviews', { ascending: false, nullsFirst: false }).limit(8); const rows = (data || []) as LeadHit[]; /* a sanctioned party is never shown to anybody — founder instruction 516, 18 Sep 2026 */ const barred = await sanctionedLeads(admin, rows.map((r) => r.id)); return J({ results: rows.filter((r) => !barred.has(String(r.id))).map((r) => searchResult(r, email)) }); } // search_result.ts: claimed_by is read, never returned
    if (action === 'create_company') { const { data: existing } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (existing) return J({ error: 'Your account already manages a company.', code: 'company_exists' }, 409); const name = String(body.company_name || '').trim().slice(0, 160); if (name.length < 2) return J({ error: 'Enter your company name.', code: 'enter_company' }, 400); /* A COMPANY ALREADY CLAIMED IS NOT REGISTERED TWICE (24 Sep 2026, sales_engineer, ledger 993). Measured on production with two ZZ DEMO accounts: after account A claimed "ZZ DEMO Errors …", account B created a second listing with the identical name and got HTTP 200, so one company could hold two verified profiles and be matched twice. The comparison is case- and space-folded and exact; a different company with a similar name is not blocked. */ { const { data: twins } = await admin.from('leads').select('id').eq('claimed', true).ilike('company_name', name.replace(/\s+/g, ' ').replace(/[\\%_]/g, (c) => '\\' + c)).limit(1); if (twins && twins.length) return J(COMPANY_ALREADY_REGISTERED, 409); } const { data: ins, error } = await admin.from('leads').insert({ company_name: name, emirate: body.emirate || null, sector: body.category || null, business_role: body.role || 'supplier', claimed: true, claimed_by: email, email, owner_email_verified: await emailProven(email), source: 'self_registered', locale: asLocale(body.lang), scraped_at: new Date().toISOString().slice(0, 10) }).select('id').maybeSingle(); if (error) { /* The exact-name check above is not atomic and does not fold spellings; the duplicate-company indexes are the rule itself (_shared/duplicate_company.ts). */ if (isDuplicateCompany(error)) return J(COMPANY_ALREADY_REGISTERED, 409); /* a01_leads_sanctioned_identity_cannot_re_register raises this when the name, trade licence or account e-mail belongs to a confirmed sanctions ban. The trigger is the guard; this turns it into a sentence a stranger can read rather than a raw 23514 — founder instruction 516, 18 Sep 2026. */ if (String(error.message || '').includes('SANCTIONED_PARTY_BLOCKED')) return J(SANCTIONED_REGISTRATION_REFUSAL, 403); return J({ error: error.message }, 500); } const reg = await setRegistration(ins!.id); await recordFirstTouch(ins!.id, body.first_touch); return J({ ok: true, id: ins?.id, registration: reg }); }
    // TAKEOVER FIX 27 Jul 2026 -----------------------------------------------------------------
    // 'claim' resolved the listing from body.leads_id - the sequential primary key - and never
    // looked at claim_token. claim_lookup v2 was rewritten on 19 Jul 2026 to accept ONLY the
    // unguessable token precisely because ids are walkable (see claim_lookup/index.ts header:
    // walking id = 1,2,3... dumped all 20,470 leads). This endpoint left the other half of that
    // hole open: anyone with any supplier login could POST leads_id = N and take ownership of any
    // of the 20,464 unclaimed listings - name, licence, inbox and all - one id at a time. The
    // token is the proof of invitation, so the token is now the LOOKUP KEY. leads_id is accepted
    // only as a cross-check: if it is sent and disagrees with the row the token resolves to, the
    // call is rejected rather than silently trusting either one.
    if (action === 'claim') { const token = String(body.claim_token || body.token || body.t || '').trim(); if (!UUID_RE.test(token)) return J({ error: 'invalid_link', message: 'This claim link is not valid. Please use the link from your invitation, or contact management@quotesdone.com.' }, 400); /* The token's row, this account's current company and the e-mail proof are independent reads: issued together (28 Sep 2026, it_engineer — the claim was a chain of seven round trips, 3.3-4.1 s measured). */ const [{ data: row }, { data: existing }, proven] = await Promise.all([admin.from('leads').select('id,claimed,claimed_by').eq('claim_token', token).maybeSingle(), admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(), emailProven(email)]); if (!row) return J({ error: 'not found' }, 404); const id = Number(row.id); const askedId = Number(body.leads_id); if (body.leads_id != null && isFinite(askedId) && askedId !== id) return J({ error: 'invalid_link', message: 'This claim link does not match the company you selected. Please use the link from your invitation.' }, 400); if (row.claimed && row.claimed_by !== email) return J({ error: 'This company is already claimed by another account.' }, 409); if (existing && existing.id !== id) return J({ error: 'Your account already manages another company.' }, 409); const { error: claimErr } = await admin.from('leads').update({ claimed: true, claimed_by: email, portal_updated_at: new Date().toISOString(), ...(proven ? { owner_email_verified: true } : {}) }).eq('id', id); /* 24 Sep 2026 (#962): a claim the database refused (duplicate-company indexes) gets the same answer as create_company. */ if (claimErr) { console.error('claim: leads update failed —', claimErr.message); const r = registrationRefusal(claimErr); return J(r.body, r.status); } /* that update already touched the row, so the registration trigger has run: read the state, and record the first touch beside it */ const [reg] = await Promise.all([setRegistration(id, false), recordFirstTouch(id, body.first_touch)]); return J({ ok: true, id, registration: reg }); }

    // WHAT THIS COMPANY CAN QUOTE FOR (12 Aug 2026; answered here since 14 Sep 2026).
    //
    // Until 14 Sep this proxied to the capability_agent edge function, which the 7 Sep sweep deleted
    // from production; every call since returned the gateway's 404. state/confirm never needed a
    // model and now run in-process from _shared/supplier_capability.ts (see its header). The history
    // below is kept because the security argument still holds: the id comes from the caller's JWT.
    //
    // Original note — the supplier-facing side of capability_agent (12 Aug 2026).
    //
    // fn_match_capability gates on supplier_capabilities.confirmed_at ("GATE: supplier confirmed
    // their own scope") and capability_agent's `confirm` is its only writer. That endpoint had no
    // caller anywhere, so no supplier could ever be matched to anything.
    //
    // IT IS PROXIED HERE RATHER THAN CALLED FROM THE BROWSER, and that is a security decision, not
    // tidiness. capability_agent takes `supplier_id` straight from the request body and authenticates
    // only with an internal secret. Handing the browser that secret would let any signed-in supplier
    // read and CONFIRM another company's scope by changing one number - the same enumeration defect
    // claim_lookup was hardened against on 19 Jul, one layer up. Here the id is resolved from the
    // caller's own JWT via claimed_by and the client's id is never consulted.
    // A closed support case asks the supplier for its rating inside the portal (CSAT 1-5, CES 1-7; customer_support
    // #1036). The portal is the sales engineer's, so it asks here and never calls Support's widget. The party is the
    // company this session claimed, never an id from the client, and fn_support_portal_rate refuses a case that is
    // not that company's. A sanctioned session never reaches this line (refused above).
    if (action === 'support_rating_due' || action === 'support_rating') {
      const { data: mine } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (action === 'support_rating_due') {
        if (!mine) return J({ ok: true, due: [] });
        const { data, error } = await admin.rpc('fn_support_rating_due', { p_party_kind: 'supplier', p_party_id: String(mine.id) });
        return error ? J({ error: 'rating_due_failed' }, 400) : J({ ok: true, due: data || [] });
      }
      if (!mine) return J({ error: 'claim_your_company_first', code: 'no_company' }, 400);
      const { data, error } = await admin.rpc('fn_support_portal_rate', {
        p_party_kind: 'supplier', p_party_id: String(mine.id), p_case_ref: String(body.case_ref || ''),
        p_csat: body.csat == null ? null : Number(body.csat), p_ces: body.ces == null ? null : Number(body.ces),
        p_comment: body.comment ? String(body.comment).slice(0, 2000) : null });
      return error ? J({ error: 'rating_failed' }, 400) : J(data);
    }

    if (action === 'capability_state' || action === 'capability_confirm') {
      const { data: mine } = await admin.from('leads').select('id,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!mine) return J({ error: 'claim_your_company_first', code: 'no_company', message: 'Claim your company before confirming what it can quote for.' }, 400);
      if (action === 'capability_state') return J(await capabilityState(admin, Number(mine.id)));
      // Whitelisted fields only. The client cannot inject supplier_id, and there is no route to the
      // old `analyze` (a model pass) from here.
      const fwd: Record<string, unknown> = {};
      {
        for (const k of ['trades','roles','services','products','coverage_emirates','brands',
                         'project_types','exclusions','min_project_value','max_project_value']) {
          if (body[k] !== undefined) fwd[k] = body[k];
        }
        // COVERAGE 12 Aug 2026. Walked the registration end to end and the confirmed row came out
        // with coverage_emirates = {} even though the same supplier had just told the registration
        // form they serve Dubai, Sharjah and Abu Dhabi. CapabilityConfirmPanel sends
        // `cap.coverage_emirates || []`, and for anyone whose scope was never derived from a
        // scrape (every self-registered and every newly-invited supplier) `cap` is null, so it
        // posts an empty array over the answer we already hold. fn_match_capability then ranks
        // them with `why: 'coverage not stated'` - still matchable, but below an identical
        // supplier who happened to have a derived row. The emirates are not missing; they are
        // one table away. Defaulted server-side so every caller gets it, and only when the client
        // genuinely has nothing to say: an explicit non-empty list from the screen always wins.
        const sent = fwd.coverage_emirates as unknown[] | undefined;
        if (!Array.isArray(sent) || !sent.length) {
          const declared = (mine as { service_emirates?: string[] }).service_emirates;
          if (Array.isArray(declared) && declared.length) fwd.coverage_emirates = declared;
        }
      }
      const [status, out] = await capabilityConfirm(admin, Number(mine.id), fwd);
      return J(out, status);
    }

    // THE SERVICES CHECKLIST (15 Sep 2026, sales_engineer) — docs/api/supplier_portal_services.md.
    // Same rule as the capability pair above: the supplier id comes from the caller's own JWT, never
    // from the body. The confirm underneath is capabilityConfirm, so the ledger row is unchanged.
    if (action === 'services_state' || action === 'services_resolve'
        || action === 'services_rewrite' || action === 'services_save_rewrite' || action === 'transcribe_service_note') {
      const { data: mine } = await admin.from('leads').select('id,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!mine) return J({ error: 'claim_your_company_first', code: 'no_company' }, 400);
      const sid = Number(mine.id);
      const declaredEmirates = () => (Array.isArray(mine.service_emirates) ? mine.service_emirates as string[] : []);
      if (action === 'services_state') return J(await servicesState(admin, sid));
      if (action === 'services_resolve') { const [s, o] = await servicesResolve(admin, body); return J(o, s); }
      // THE SALES ENGINEER'S REWRITE (instruction 438). Preview writes nothing; the save is the
      // supplier's confirmation of what it was shown.
      if (action === 'services_rewrite') { const [s, o] = await servicesRewrite(admin, sid, body); return J(o, s); }
      if (action === 'services_save_rewrite') { const [s, o] = await servicesSaveRewrite(admin, sid, body, declaredEmirates()); return J(o, s); }
      // Voice goes to the existing transcribe function with the caller's own token, so it keeps its
      // own sign-in check, byte sniffing and malware scan. Nothing reaches it while the flag is off.
      const [s, o] = await transcribeServiceNote(sid, body, {
        enabled: () => voiceEnabled(admin),
        recentCount: async (id) => {
          const { count } = await admin.from('supplier_voice_note').select('id', { count: 'exact', head: true })
            .eq('supplier_id', id).gte('created_at', new Date(Date.now() - 3600e3).toISOString())
            .not('outcome', 'in', '(flag_off,rate_limited)');
          return count || 0;
        },
        audit: async (row) => { const { error } = await admin.from('supplier_voice_note').insert(row); if (error) console.error('supplier_voice_note insert failed', error.message); },
        start: async (row) => {
          const { data, error } = await admin.from('supplier_voice_note').insert(row).select('id').single();
          if (error) console.error('supplier_voice_note insert failed', error.message);
          return async (patch) => { if (data?.id) await admin.from('supplier_voice_note').update(patch).eq('id', data.id); };
        },
        transcribe: async (b64, mime) => {
          try {
            const r = await fetch(`${SUPA_URL}/functions/v1/transcribe`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: req.headers.get('Authorization') || '' }, body: JSON.stringify({ audio_b64: b64, mime }) });
            const j = await r.json().catch(() => ({}));
            return r.ok && j && j.ok && typeof j.text === 'string' ? { ok: true, text: j.text } : { ok: false, error: String(j?.error || r.status) };
          } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
        },
      });
      return J(o, s);
    }

    if (action === 'process_docs') {
      const { data: sup } = await admin.from('leads').select('id,company_name,services,products,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const secret = await secretVal('cred_fn_supplier_api');
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const out: Record<string, unknown> = {};
      // Every stored licence, profile and catalogue is also READ BY CODE into a trade proposal the
      // supplier confirms (15 Sep 2026, _shared/supplier_doc_trades.ts). The model calls below still
      // run and still refuse under the OpenRouter hold; nothing here waits on them.
      const readQueue: DocIn[] = [];
      const lic = body.license || {};
      // 14 Sep 2026 (sales_engineer): a path is recorded only when it is this supplier's own and
      // storage holds the object - otherwise the supplier sees success for a file that is not there
      // and the backup queues a document it can never copy.
      const own = async (p: unknown, folder: string) => { const s = String(p); return s.startsWith(`${folder}/${sup.id}/`) && !s.includes('..') && await storedAt(admin, 'supplier-docs', s); };
      const notStored = (what: string) => J({ error: 'document_not_found', code: 'document_not_found', message: `We could not find your ${what} in our records. Please upload it again.` }, 400);
      if (lic.path) { if (!(await own(lic.path, 'licenses'))) return notStored('trade licence'); upd.license_doc_path = String(lic.path); readQueue.push({ path: String(lic.path), name: String(lic.path).split('/').pop() || 'licence', kind: 'licence' }); }
      // AUDIT 9.1 (3 Aug 2026). The trade licence upload. Three defects in one line:
      //   * no type check at all - the bytes went to storage as whatever the caller declared,
      //     defaulting to application/octet-stream, so an HTML document or an executable stored
      //     cleanly as a supplier's trade licence and was later served back to an admin reviewer;
      //   * the filename was only character-filtered, so the stored extension could disagree with
      //     the content ("licence.pdf" holding HTML);
      //   * the whole thing sat in try/catch with an empty handler, so a failed upload was
      //     SILENT - the supplier saw success, license_doc_path was never set, and the document
      //     review queue simply never saw a licence.
      else if (lic.original_b64) {
        const sc = await sanitizeAndScan({ input: String(lic.original_b64), declaredMime: lic.mime, filename: lic.filename || 'license', allow: SAFE_UPLOAD,
                                           scan: { source: 'supplier_api.license', subject: String(sup.id), filename: lic.filename, bucket: 'supplier-docs' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'That licence file cannot be accepted. Please upload a PDF or a clear photo (JPEG or PNG) of your trade licence.' }, sc.status);
        const s = sc.result;
        const p = `licenses/${sup.id}/${Date.now()}_${safeFilename(lic.filename || 'license', s.mime)}`;
        const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error || !(await storedAt(admin, 'supplier-docs', p))) return J({ error: 'upload_failed', code: 'upload_failed', detail: up.error?.message || 'storage does not hold the object after upload', message: 'We could not store your trade licence. Please try again.' }, 502);
        upd.license_doc_path = p;
        readQueue.push({ path: p, name: String(lic.filename || 'licence'), kind: 'licence', bytes: s.bytes, mime: s.mime });
      }
      const licImgs = Array.isArray(lic.images) ? lic.images : [];
      // CODE READS THE EXPIRY FIRST (22 Sep 2026, SEATS-02; founder instruction 524). This block
      // went straight to license_extract, which runs through ai_gateway — under the founder's
      // OpenRouter hold that is a 502 on every registration, so a licence uploaded here never got
      // an expiry date at all while supplier_portal's Documents tab read the same document by code.
      // Same reader, same rule as the portal: a date only counts when an expiry keyword stands
      // beside it, and a scan (no text layer) returns nothing rather than a guess.
      const licBytes = readQueue.find((d) => d.kind === 'licence' && d.bytes)
        || (upd.license_doc_path ? await (async () => {
             try {
               const dl = await admin.storage.from('supplier-docs').download(String(upd.license_doc_path));
               if (!dl.data) return null;
               return { bytes: new Uint8Array(await dl.data.arrayBuffer()), mime: dl.data.type || 'application/pdf' } as { bytes: Uint8Array; mime: string };
             } catch (_e) { return null; }
           })() : null);
      // What CODE measured off the document. The model below may add what code cannot read
      // (licence number, authority, legal name) but must never overwrite this date.
      let codeExpiry: string | null = null;
      // The licence's printed company name, read by code (24 Sep 2026). The sales engineer's review
      // compares it with the registered name (fn_supplier_licence_name_mismatch); null = not read.
      let codeName: string | null = null;
      if (licBytes?.bytes) { try { codeName = await readLicenceName(licBytes.bytes, licBytes.mime || 'application/pdf'); } catch (_e) { codeName = null; } }
      // A NEW licence replaces the old name even when nothing is read: a stale name must never match for a new
      // document. null = not read, and the review then holds the registration (licence_name_unread).
      if (licBytes?.bytes) upd.licence_legal_name = codeName;
      // The supplier reads this note in the portal, so it is written in both languages the
      // registration speaks (the estate's rule: a document message is English and fully Arabic).
      const noteBoth = (en: string, ar: string) => { out.license_expiry_note = en; out.license_expiry_note_ar = ar; };
      if (licBytes?.bytes) {
        try {
          const docRead = await readExpiry(licBytes.bytes, licBytes.mime || 'application/pdf');
          if (docRead) {
            codeExpiry = docRead.expiry;
            upd.license_expiry = docRead.expiry;
            upd.doc_extracted_at = new Date().toISOString();
            out.license = { expiry: docRead.expiry, source: 'text', keyword: docRead.keyword, read_by: 'code', licence_name: codeName };
          } else {
            noteBoth('We could not read an expiry date from your trade licence — it may be a scan, or it may not print a date beside an expiry label. Nothing was guessed.',
                     'لم نتمكن من قراءة تاريخ انتهاء رخصتكم التجارية. قد يكون الملف صورة ممسوحة ضوئياً، أو لا يذكر تاريخاً بجانب كلمة الانتهاء. ولم نخمّن أي تاريخ.');
          }
        } catch (e) {
          noteBoth('We could not read your trade licence file (' + String((e as Error)?.message || e).slice(0, 120) + '). Nothing was guessed.',
                   'تعذّرت قراءة ملف رخصتكم التجارية. ولم نخمّن أي تاريخ.');
        }
      }
      // The model path — legal name, licence number, authority, emirate, TRN — is behind the same
      // flag the portal uses (app_secrets.document_expiry_ai). With the flag off nothing is asked
      // of a gateway that cannot answer, and nothing above depends on it.
      // A scan the code could not name is sent from storage when the portal did not resend it (24 Sep 2026).
      const modelDoc = licenceModelPayload({ ...lic, images: licImgs }, licBytes?.bytes ? { bytes: licBytes.bytes, mime: licBytes.mime || 'application/pdf' } : null, codeName);
      if (modelDoc && await flagOn('document_expiry_ai')) {
        try { const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, subject: { supplier_id: sup.id, email }, mode: 'license', ...modelDoc }) }); const jd = await r.json();
          if (jd?.ok && jd.doc) { const d = jd.doc;
            if (d.license_number) upd.trade_license_no = d.license_number;
            if (d.license_authority) upd.license_authority = d.license_authority;
            if (d.city) upd.license_city = d.city;
            // CODE FIRST, AND THE MODEL DOES NOT OVERRULE IT (founder: "code first, LLM only where
            // code can't"). When the document itself printed a date beside an expiry keyword, that
            // reading stands; the model's date is only recorded beside it, and a disagreement is
            // returned so a human can see the two rather than being silently resolved.
            if (d.expiry_date) {
              if (codeExpiry) {
                if (String(d.expiry_date) !== codeExpiry) out.license_expiry_model_differs = { code: codeExpiry, model: d.expiry_date };
              } else upd.license_expiry = d.expiry_date;
            }
            if (d.emirate) upd.emirate = d.emirate;
            if (d.trn) upd.trn = d.trn;
            upd.doc_extracted_at = new Date().toISOString();
            // 24 Sep 2026: the licence name is RECORDED, never copied over the registered name. Copying it
            // made the name check the founder asked for always pass; the review now compares the two
            // (fn_supplier_licence_name_mismatch) and a mismatch is action_required. Code's reading wins.
            const legal = String(d.legal_name || '').trim();
            const modelName = licenceNameFromModel(d);
            if (modelName && !codeName) upd.licence_legal_name = modelName;
            // Merged, never replaced (main): out.license may already carry the expiry code measured,
            // and overwriting it would lose the reading that is actually written to the row.
            // `trn` is SP-C-09 of #858: process_docs read the TRN off the licence and wrote it to the
            // row (upd.trn above) but never returned it, though the form reads out.license.trn.
            out.license = { ...(out.license as Record<string, unknown> || {}),
              legal_name: legal, license_number: d.license_number, authority: d.license_authority, city: d.city,
              expiry: codeExpiry || d.expiry_date, model_expiry: d.expiry_date, emirate: d.emirate, trn: d.trn,
              licence_name: upd.licence_legal_name ?? null, confidence: d.confidence };
          } else out.license_error = jd?.error || 'extract_failed';
        } catch (e) { out.license_error = String((e as Error)?.message || e); }
      }
      const profImgs: any[] = [];
      // Extracted services for THIS run, kept aside so they can be cross-checked against the
      // supplier's own typed text once the row has been written (see the 29 Jul 2026 header).
      let xServices: string[] = [];
      const prof = body.company_profile || {};
      if (prof.path) { if (!(await own(prof.path, 'profiles'))) return notStored('company profile'); upd.company_profile_doc_path = String(prof.path); readQueue.push({ path: String(prof.path), name: String(prof.path).split('/').pop() || 'profile', kind: 'profile' }); }
      // AUDIT 9.1. Company profile document - same treatment as the trade licence above.
      else if (prof.original_b64) {
        const sc = await sanitizeAndScan({ input: String(prof.original_b64), declaredMime: prof.mime, filename: prof.filename || 'profile', allow: SAFE_UPLOAD,
                                           scan: { source: 'supplier_api.company_profile', subject: String(sup.id), filename: prof.filename, bucket: 'supplier-docs' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'That company profile cannot be accepted. Please upload a PDF or an image (JPEG or PNG).' }, sc.status);
        const s = sc.result;
        const p = `profiles/${sup.id}/${Date.now()}_${safeFilename(prof.filename || 'profile', s.mime)}`;
        const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error || !(await storedAt(admin, 'supplier-docs', p))) return J({ error: 'upload_failed', code: 'upload_failed', detail: up.error?.message || 'storage does not hold the object after upload', message: 'We could not store your company profile. Please try again.' }, 502);
        upd.company_profile_doc_path = p;
        readQueue.push({ path: p, name: String(prof.filename || 'profile'), kind: 'profile', bytes: s.bytes, mime: s.mime });
      }
      if (Array.isArray(prof.images)) profImgs.push(...prof.images);
      const cats = Array.isArray(body.catalogs) ? body.catalogs.slice(0, 5) : []; const catPaths: string[] = [];
      // AUDIT 9.1. Catalogues. A rejected catalogue is refused outright rather than skipped,
      // because silently dropping one is how a supplier ends up believing a document is on file.
      for (const c of cats) {
        if (c?.path) { if (!(await own(c.path, 'catalogs'))) return notStored('catalogue'); catPaths.push(String(c.path)); readQueue.push({ path: String(c.path), name: String(c.path).split('/').pop() || 'catalogue', kind: 'catalogue' }); }
        else if (c?.original_b64) {
          const sc = await sanitizeAndScan({ input: String(c.original_b64), declaredMime: c.mime, filename: c.filename || 'catalog', allow: SAFE_UPLOAD,
                                             scan: { source: 'supplier_api.catalog', subject: String(sup.id), filename: c.filename, bucket: 'supplier-docs' } });
          if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'One of your catalogue files cannot be accepted. Please upload PDFs or images (JPEG or PNG).' }, sc.status);
          const s = sc.result;
          const p = `catalogs/${sup.id}/${Date.now()}_${safeFilename(c.filename || 'catalog', s.mime)}`;
          const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
          if (up.error || !(await storedAt(admin, 'supplier-docs', p))) return J({ error: 'upload_failed', code: 'upload_failed', detail: up.error?.message || 'storage does not hold the object after upload', message: 'We could not store one of your catalogue files. Please try again.' }, 502);
          catPaths.push(p);
          readQueue.push({ path: p, name: String(c.filename || 'catalogue'), kind: 'catalogue', bytes: s.bytes, mime: s.mime });
        }
        if (Array.isArray(c?.images)) profImgs.push(...c.images);
      }
      // Append, never replace. Assigning catPaths wholesale wiped every catalogue the supplier
      // had already uploaded the moment they added one more - silent data loss, no warning, no
      // undo. supplier_portal.save_documents already appends; this is the registration path
      // catching up to it. Same 20-file ceiling so the two paths agree.
      if (catPaths.length) {
        const { data: curCat } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const existingCat: string[] = Array.isArray(curCat?.catalog_doc_paths) ? (curCat!.catalog_doc_paths as string[]) : [];
        upd.catalog_doc_paths = [...existingCat, ...catPaths.filter((p) => !existingCat.includes(p))].slice(0, 20);
      }
      if (profImgs.length) {
        try { const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, subject: { supplier_id: sup.id, email }, mode: 'profile', images: profImgs.slice(0, 10) }) }); const jd = await r.json();
          if (jd?.ok && jd.profile) { const pf = jd.profile;
            if (pf.summary) upd.capability_summary = pf.summary;
            // DOCUMENTS LEAD (spec, 29 Jul 2026). This line used to read
            //   if (Array.isArray(pf.services) && pf.services.length && !sup.services) ...
            // so the trade licence / company profile / catalogue only got to speak when the
            // supplier had typed nothing at all. The documents are the PRIMARY data source, so
            // what the agent extracts from them now ALWAYS becomes the canonical leads.services.
            // The supplier's own words are not lost - they are preserved as the declared value
            // and cross-checked immediately below.
            if (Array.isArray(pf.services) && pf.services.length) { xServices = pf.services.map((s: unknown) => String(s).trim()).filter(Boolean).slice(0, 40); upd.services = xServices.join(', '); }
            if (Array.isArray(pf.products) && pf.products.length && !sup.products) upd.products = pf.products.join(', ');
            if (Array.isArray(pf.emirates) && pf.emirates.length && !(Array.isArray(sup.service_emirates) && sup.service_emirates.length)) upd.service_emirates = pf.emirates;
            out.profile = { summary: pf.summary, sectors: pf.sectors, confidence: pf.confidence };
          } else out.profile_error = jd?.error || 'extract_failed';
        } catch (e) { out.profile_error = String((e as Error)?.message || e); }
      }
      // 5 Aug 2026. This is the ONLY database write in process_docs, and it carries the storage
      // path, every extracted licence field and the company-name correction. Its result was
      // discarded, so a failed write returned `{ok:true, extracted:{…}}` — a complete, plausible
      // payload describing a licence that was never saved. The supplier is told their trade licence
      // is on file when it is not, and the document review queue never sees it. The storage uploads
      // twenty lines above already check `up.error` and return 502; this now matches them.
      // Found by verify_supplier_docs.mjs, which asserts the ROW rather than the response.
      // A licence number another claimed company holds is set aside (the rest of the row is still
      // written) and handed to a human: _shared/duplicate_company.ts.
      const { error: updErr, licenceSetAside } = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, sup.id, upd, 'supplier_api.process_docs');
      if (licenceSetAside) {
        const lic = out.license as Record<string, unknown> | undefined;
        if (lic) delete lic.license_number;   // never fill the form with a number the row does not hold
        out.licence_set_aside = true;
        out.licence_notice = COMPANY_ALREADY_REGISTERED;
      }
      if (updErr) {
        console.error('process_docs: leads update failed —', updErr.message);
        return J({ error: 'save_failed', code: 'save_failed', message: 'We read your documents but could not save them to your profile. Please try again.' }, 502);
      }
      // After the row write, so only documents now on the supplier's row are read. A reading failure
      // is reported beside the result and never fails the upload the supplier just made.
      if (readQueue.length) out.documents_read = await proposeTradesFromDocs(admin, Number(sup.id), readQueue);
      // DOUBLE CONFIRMATION (spec, 29 Jul 2026). The typed services box exists so the supplier's
      // own description can be checked AGAINST the documents; until now the two were never
      // compared, so no mismatch could ever be flagged. Compare them, record the outcome in
      // agent_actions, and raise a review item when they conflict. Registration is never blocked.
      // The declared text comes from the last cross-check record when one exists, because
      // leads.services now holds the EXTRACTED value and comparing it to itself proves nothing.
      if (xServices.length) {
        const prior = await priorCrossCheck(sup.id);
        const declared = prior.found ? prior.declared : (sup.services ?? null);
        const cc = await recordServicesCrossCheck(sup.id, sup.company_name, xServices, declared);
        out.services_crosscheck = { verdict: cc.verdict, overlap: Math.round(cc.overlap * 100) / 100, note: cc.note, extracted_services: xServices, declared_services: declared == null ? null : String(declared) };
      }
      return J({ ok: true, extracted: out });
    }

    // ROW #5 §24 — SETTINGS. Language and notification preferences, on their own narrow allowlist.
    //
    // These are deliberately NOT added to PROFILE_COLS. That list carries the emirates ID, the
    // trade licence number and the licence expiry — fields whose writes are what
    // the licence gate and the approval flow are built around. Letting a preferences screen post
    // into the same allowlist would mean a change of interface language travelled through the same
    // door as a change of trade licence number. Three columns, named here, and nothing else is settable.
    if (action === 'save_settings') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      if (body.locale !== undefined) {
        const loc = String(body.locale);
        if (!['en', 'ar'].includes(loc)) return J({ error: 'locale must be en or ar' }, 400);
        upd.locale = loc;
      }
      if (body.email_shared !== undefined) upd.email_shared = !!body.email_shared;
      const { error } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, saved: Object.keys(upd).filter((k) => k !== 'portal_updated_at') });
    }

    // RE-ACCEPTANCE OF A NEW AGREEMENT VERSION (14 Sep 2026, agent: sales_engineer). The founder approved
    // Supplier Agreement v11; clause 23 asks a supplier to re-confirm acceptance of a material change, and
    // the portal now asks on the next sign-in (SupplierPortal ReacceptTerms). This records exactly what
    // save_profile's accept_terms records — when, WHICH version (read server-side from terms_version, never
    // from the browser), the client IP, and the SHA-256 of the exact text accepted (null, never the wrong
    // hash, while the live version is not the one supplier_agreement.ts was exported for).
    if (action === 'accept_terms') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const rec = await supplierTermsRecord(secretVal, clientIp(req), req.headers.get('user-agent') || '');
      if (!rec) return J({ error: 'the current agreement version is not set', code: 'no_terms_version' }, 500);
      const { error } = await admin.from('leads').update(rec).eq('id', sup.id);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, accepted_terms_version: rec.accepted_terms_version, text_hash_stored: !!rec.accepted_terms_sha256 });
    }

    if (action === 'settings') {
      const { data: sup } = await admin.from('leads')
        .select('id,company_name,locale,email_shared,claimed_by,phone,approval_status,registration_status,owner_email_verified,owner_phone_verified,accepted_terms_at,accepted_terms_version,license_expiry')
        .eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      return J({ ok: true, settings: sup });
    }

    if (action === 'save_profile') {
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,approval_status,registration_submitted_at,locale,accepted_terms_at,accepted_terms_version').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      for (const c of PROFILE_COLS) if (body[c] !== undefined) upd[c] = body[c];
      if (Array.isArray(body.service_emirates)) upd.service_emirates = body.service_emirates;
      // THE HOME EMIRATE COMES FROM THE CHIPS (15 Sep 2026, sales_engineer). Since #695 sign-up asks the
      // emirate once, as service-emirate chips, so leads.emirate stopped being filled and nothing here
      // could set it; eligibility, the tie-break and the founder's registration mail all read it. The
      // first chosen emirate becomes the home emirate when none is on file, or when the one on file is
      // no longer among the emirates the supplier says it serves.
      // Only one of the seven emirates, as the chips send them (the same list supplier_onboard and
      // license_extract use): an arbitrary string in the body must not become the home emirate.
      const UAE = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
      const firstEmirate = Array.isArray(body.service_emirates) ? body.service_emirates.find((e: unknown) => typeof e === 'string' && UAE.includes(e)) : null;
      if (firstEmirate && (!sup.emirate || !(body.service_emirates as unknown[]).includes(sup.emirate))) upd.emirate = firstEmirate;
      // THE SUPPLIER'S OWN WORDS STAND (15 Sep 2026, sales_engineer). Since 29 Jul this replaced the
      // typed services with the last extraction whenever one existed, so a supplier correcting what their
      // documents were read as could never make the correction stick. The typed text is written as typed;
      // the extraction is still compared with it and the comparison recorded, which is what the double
      // confirmation asked for.
      let servicesCheck: Record<string, unknown> | null = null;
      if (upd.services !== undefined) {
        const prior = await priorCrossCheck(sup.id);
        if (prior.extracted.length) {
          const declared = clip(upd.services, 2000);
          const cc = await recordServicesCrossCheck(sup.id, sup.company_name, prior.extracted, declared);
          servicesCheck = { verdict: cc.verdict, overlap: Math.round(cc.overlap * 100) / 100, note: cc.note, extracted_services: prior.extracted, declared_services: declared };
        }
      }
      // TERMS ARE ACCEPTED ONLY WHEN THE FLAG IS EXACTLY TRUE (15 Sep 2026). A bare truthiness test on the
      // flag took any truthy value — "false" as a string, 1, {} — as a legal acceptance. The record (version read
      // server-side, IP, SHA-256 of the exact text) is built in _shared/supplier_terms.ts, the same row
      // accept_terms below and kyc write. Accepting asks compliance_archive for the signed certificate
      // (z21_sign_supplier_on_acceptance); the certificate is the signed-terms item of the six.
      // A save repeating an acceptance already on file for the current version records nothing new: a second
      // record would move the acceptance time and ask for a second certificate (kyc's rule too).
      const accepting = body.accept_terms === true
        && !(sup.accepted_terms_at && sup.accepted_terms_version === await currentSupplierTermsVersion(secretVal));
      if (accepting) {
        const rec = await supplierTermsRecord(secretVal, clientIp(req), req.headers.get('user-agent') || '');
        if (!rec) return J({ error: 'the current agreement version is not set', code: 'no_terms_version' }, 500);
        Object.assign(upd, rec);
      }
      const wasApproved = String(sup.approval_status || '') === 'approved';
      // The WhatsApp question is answered in sign-up (founder, 15 Sep 2026). Checked beside the six, not
      // added to them, and before anything is written, as it was. Read on its own so a read error cannot
      // null `sup` above (kyc's rule for these columns).
      if (!wasApproved) {
        const { data: wa } = await admin.from('leads').select('whatsapp_opt').eq('id', sup.id).maybeSingle();
        if (!wa?.whatsapp_opt) {
          let six: string[];
          try { six = (await mandatorySixMissing(admin, sup.id)).filter((c) => !(accepting && c === 'reg_terms')); }
          catch (e) { console.error('save_profile:', (e as Error).message); return J({ error: 'check_failed', code: 'check_failed', message: 'We could not check your registration. Please try again.' }, 502); }
          const missing = [...six];
          missing.push('reg_whatsapp');
          return J({ error: 'missing_required', code: 'missing_required', params: { missing }, message: 'Still needed to register: ' + missing.join(', ') + '.' }, 400);
        }
      }
      const firstSubmit = !sup.registration_submitted_at;
      if (firstSubmit) upd.registration_submitted_at = new Date().toISOString();
      // 5 Aug 2026: this write's result was once discarded and a failed save reported success.
      const { error: updErr } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (updErr) {
        console.error('save_profile: leads update failed —', updErr.message);
        return J({ error: 'save_failed', code: 'save_failed', detail: updErr.message, message: 'We could not save your profile. Please try again.' }, 502);
      }
      // The certificate is rendered by compliance_archive after the trigger above posts to it. Give it a
      // few seconds so a supplier who accepts and submits in one go is verified on the signed copy; if it
      // is slower, z20_leads_mandatory_item_landed_reverifies verifies them the moment it lands.
      let certificatePending = false;
      if (accepting) {
        certificatePending = true;
        for (let i = 0; i < 6 && certificatePending; i++) {
          await new Promise((r) => setTimeout(r, 750));
          const { data: s } = await admin.from('leads').select('signed_terms_at').eq('id', sup.id).maybeSingle();
          certificatePending = !(s?.signed_terms_at && String(s.signed_terms_at) >= String(upd.accepted_terms_at));
        }
      }
      // THE SALES ENGINEER VERIFIES (15 Sep 2026). The approval used to be decided here, from the licence
      // alone; public.fn_sales_engineer_verifies_supplier now decides from the six plus the licence expiry,
      // records the decision, and a trigger refuses any approval the six do not support. pricing_config.
      // auto_approve_suppliers keeps its meaning: off leaves a complete supplier pending for the sales engineer.
      const { data: vd, error: vErr } = await admin.rpc('fn_sales_engineer_verifies_supplier', { p_lead_id: sup.id, p_source: 'save_profile' });
      if (vErr || !(vd as { ok?: boolean })?.ok) {
        console.error('save_profile: verification failed —', vErr?.message || JSON.stringify(vd));
        return J({ error: 'verification_failed', code: 'verification_failed', detail: vErr?.message || null, message: 'Your profile was saved, but we could not check your registration. Please try again.' }, 502);
      }
      const v = vd as { approval_status: string; missing: string[]; reason: string | null; licence_expired: boolean };
      const decision = String(v.approval_status || 'pending');
      // A certificate on its way is not something the supplier still has to do.
      const stillNeeded = (v.missing || []).filter((c) => !(certificatePending && c === 'reg_terms'));
      if (v.licence_expired && !stillNeeded.length && decision === 'action_required') stillNeeded.push('licence_expired');
      const { data: full } = await admin.from('leads').select('*').eq('id', sup.id).maybeSingle();
      if (firstSubmit) {
        const name = full?.company_name || sup.company_name;
        const ar = (full?.locale || sup.locale) === 'ar';
        const mgmt = (await secretVal('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
        const licInfo = full?.trade_license_no ? ` Licence ${full.trade_license_no}${full.license_city ? ', ' + full.license_city : ''}${full.license_expiry ? ', expires ' + full.license_expiry : ''}.` : '';
        const needEn = sixInWords(stillNeeded.filter((c) => c !== 'licence_expired'), 'en') + (stillNeeded.includes('licence_expired') ? (stillNeeded.length > 1 ? ', ' : '') + 'a trade licence that is in date' : '');
        const needAr = sixInWords(stillNeeded.filter((c) => c !== 'licence_expired'), 'ar') + (stillNeeded.includes('licence_expired') ? (stillNeeded.length > 1 ? '، ' : '') + 'رخصة تجارية سارية المفعول' : '');
        const days = 14;
        const supplierMail = decision === 'approved'
          ? (ar ? { subject: 'أصبح حسابكم على QuotesDone مفعّلًا', body: `فُعِّل حساب ${name} لدى QuotesDone، وبإمكانكم الآن استلام الطلبات وتقديم عروض الأسعار.` }
                : { subject: 'Your QuotesDone supplier account is active', body: `Your account for ${name} is active — you can now receive inquiries and submit quotes.` })
          : decision === 'pending'
          ? (ar ? { subject: 'استلمنا طلب تسجيلكم لدى QuotesDone', body: `نشكركم على تسجيل ${name}. اكتملت البنود الستة المطلوبة، ويتولّى مهندس المبيعات مراجعة طلب التسجيل حاليًا، وسنوافيكم برسالة فور اعتماده.` }
                : { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name}. All six required items are in, and our sales engineer is reviewing your registration now. We will e-mail you as soon as it is approved.` })
          : !stillNeeded.length
          // Only the certificate is outstanding and it is on its way: nothing is asked of the supplier.
          ? (ar ? { subject: 'استلمنا طلب تسجيلكم لدى QuotesDone', body: `نشكركم على تسجيل ${name}. نعمل حاليًا على إصدار شهادة موافقتكم الموقّعة على شروط المورّد، وسيُفعَّل حسابكم تلقائيًا فور صدورها، دون أن يلزمكم أي إجراء.` }
                : { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name}. We are issuing the signed certificate of your acceptance of the supplier terms; your account activates automatically as soon as it is ready. Nothing is needed from you.` })
          : (ar ? { subject: 'استلمنا طلب تسجيلكم لدى QuotesDone', body: `نشكركم على تسجيل ${name} لدى QuotesDone.\n\nلم يُفعَّل حسابكم بعد، إذ لا يزال ينقصه ما يلي: ${needAr}.\n\nيُرجى تسجيل الدخول إلى بوابة المورّد واستكمال ذلك، وسيُفعَّل حسابكم تلقائيًا فور اكتمال البنود الستة، دون قائمة انتظار أو مراجعة يدوية.\n\nنرجو استكمال ذلك خلال ${arDays(days)}؛ إذ يُغلق طلب التسجيل بعدها تلقائيًا، ويسعدنا تسجيلكم من جديد في أي وقت.` }
                : { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name} with QuotesDone.\n\nYour account is not active yet because it still needs: ${needEn}.\n\nPlease sign in to your supplier portal and complete it. Your account activates automatically as soon as all six required items are in — there is no waiting list and no manual queue.\n\nPlease do this within ${days} days. After that this registration closes automatically, and you are welcome to start again at any time.` });
        await notify([
          { type: 'supplier_registered', to_email: mgmt, to_role: 'admin', lead_id: sup.id,
            subject: decision === 'approved' ? 'New supplier approved by the sales engineer' : decision === 'pending' ? 'New supplier waiting for approval (auto-approve is off)' : 'Supplier registration incomplete',
            body: `New supplier "${name}"${full?.emirate ? ' (' + full.emirate + ')' : ''} registered. Decision: ${decision}${stillNeeded.length ? ' — still needs: ' + needEn : (certificatePending ? ' — the signed terms certificate is being issued' : '')}. No action needed; this is a record.${licInfo}` },
          { type: 'registration_received', to_email: email, to_role: 'supplier', lead_id: sup.id, lang: ar ? 'ar' : 'en', ...supplierMail },
        ]);
      }
      if (!wasApproved && decision !== 'approved' && stillNeeded.length) {
        return J({ error: 'missing_required', code: 'missing_required', saved: true, approval_status: decision, params: { missing: stillNeeded }, message: 'Saved. Still needed to register: ' + stillNeeded.join(', ') + '.', services_crosscheck: servicesCheck }, 400);
      }
      return J({ ok: true, approval_status: decision, terms_certificate: certificatePending ? 'pending' : undefined, services_crosscheck: servicesCheck });
    }
    // Registration fee - creates a Stripe Checkout Session and nothing else.
    //
    // This endpoint previously wrote registration_status:'paid' and registration_fee_due:0
    // directly, with no payment taken, no Stripe call and no webhook. Any supplier holding a
    // valid JWT could clear their own AED 1,000 fee with a single POST. It is dormant today
    // only because every supplier is inside the free tier; it would have become a live revenue
    // hole the day the 1,000th supplier registered.
    //
    // supplier_pay already carried the correct discipline for supplier_dues - "this endpoint
    // only CREATES a Checkout Session, it never marks anything paid". Registration was the one
    // money path that never got it. registration_status is now written solely by stripe_webhook
    // on a signature-verified checkout.session.completed event.
    // PAYMENTS ARE THE ACCOUNTANT'S (founder, 14 Sep 2026). The registration checkout that lived here
    // moved to supplier_pay, which the accountant owns; this action is a pass-through with the
    // supplier's own session token so an older portal build keeps working. It creates nothing itself.
    if (action === 'pay_registration') {
      const pr = await fetch(`${SUPA_URL}/functions/v1/supplier_pay`, { method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: req.headers.get('Authorization') || '' },
        body: JSON.stringify({ action: 'registration', return_url: body.return_url }) });
      return new Response(await pr.text(), { status: pr.status, headers: cors });
    }
    // A SUPPLIER DISPUTES A CHARGE. The portal is the sales engineer's voice, the figures are the
    // accountant's: the dispute is handed over (charge.disputed), the accountant recomputes the charge
    // from the refund record, and the answer comes back to the supplier in the sales engineer's words.
    if (action === 'dispute_charge') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const { data: due } = await admin.from('supplier_dues').select('id,supplier_id').eq('id', Number(body.due_id)).maybeSingle();
      if (!due || Number(due.supplier_id) !== Number(sup.id)) return J({ error: 'not_found' }, 404);
      const { data: hid, error: hErr } = await admin.rpc('fn_seat_handoff', {
        p_from: 'sales_engineer', p_to: 'accountant', p_type: 'charge.disputed', p_subject_table: 'supplier_dues',
        p_subject_id: String(due.id) + ':' + Date.now(),
        p_payload: { supplier_id: sup.id, due_id: due.id, reason: String(body.reason || '').slice(0, 1000) } });
      if (hErr) return J({ error: 'dispute_not_recorded', detail: hErr.message }, 503);
      return J({ ok: true, handoff_id: hid, message: 'We have your query. We are checking the charge against the payment record and will write back to you.' });
    }
    if (action === 'inbox') {
      const { data: sup } = await admin.from('leads').select('id,approval_status').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // `inquiry_id` narrows the inbox to one job (the inquiry detail and the review read one); it only
      // ever narrows the caller's own matches, never widens them.
      const only = typeof body.inquiry_id === 'string' && UUID_RE.test(body.inquiry_id) ? body.inquiry_id.toLowerCase() : null;
      const { data: matches } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sup.id); const ids = (matches || []).map((m) => m.inquiry_id).filter((x) => !only || String(x).toLowerCase() === only);
      if (!ids.length) return J({ inquiries: [], approval_status: sup.approval_status });
      // SUPPLIER-SAFE PROJECTION (independent audit 9.3). The supplier inbox used to read the raw
      // inquiries row and redact on the way out, which meant every present and future
      // supplier-facing endpoint had to remember to do the same. public.inquiries_supplier_safe is
      // the single supplier-facing projection: it serves the *_masked columns under their normal
      // names and does not expose customer_id at all, so a buyer cannot be correlated across RFQs.
      // Write-time masking was hardened first (migration harden_inquiry_masking_for_supplier_safe_view)
      // so this is not a downgrade - before that it missed UAE landlines, bare domains and the
      // buyer's own name, all of which the retrieval-time scrub did catch.
      // scrubIdentity below is deliberately kept as a second, independent layer.
      const { data: inq } = await admin.from('inquiries_supplier_safe').select('id,category,emirate,summary,spec,created_at,budget,scope_type,brief_source,boq,boq_confidence,drawing_redacted_paths,status,outcome,hired_supplier_id').in('id', ids).order('created_at', { ascending: false }).limit(25);
      const { data: myq } = await admin.from('quotes').select('id,inquiry_id,option_no,quote_amount,price_ex_vat,amount_as_stated,vat_treatment,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,source,original_file_name,submittable').eq('supplier_id', sup.id).in('inquiry_id', ids);
      // A DRAFT COULD NOT BE REOPENED (14 Sep 2026). The portal only ever offered the quote form on an
      // RFQ with no quote, so a quote the accept rule held as a draft sat there with "Complete it"
      // leading back to a card with no form, and nothing said what was missing. The inbox now carries
      // the quote's own lines (so the form reopens with them) and, for a draft, the codes
      // fn_quote_structured_score reports missing — the same codes the preflight and the coaching mail
      // use, so the three cannot disagree. The scorer is STABLE: this is a read.
      const qIds = (myq || []).map((x) => x.id).filter(Boolean);
      const itemsOf: Record<string, any[]> = {};
      if (qIds.length) {
        const { data: qi } = await admin.from('quote_items').select('quote_id,line_no,description,qty,unit,unit_price').in('quote_id', qIds).order('line_no', { ascending: true });
        for (const r of (qi || [])) (itemsOf[String(r.quote_id)] ||= []).push({ description: r.description, qty: r.qty, unit: r.unit, unit_price: r.unit_price });
      }
      // A live hold (the sales engineer's, 14 Sep 2026) rides on its quote, so the card can say which
      // line and which detail is missing and offer the two ways out.
      const holdOf: Record<string, any> = {};
      if (qIds.length) {
        const { data: hs } = await admin.from('quote_spec_hold').select('quote_id,state,missing,opened_at').in('quote_id', qIds).in('state', ['open', 'awaiting_approval']);
        for (const h of (hs || [])) holdOf[String(h.quote_id)] = { state: h.state, missing: h.missing, opened_at: h.opened_at };
      }
      // Every option is its own quote; an RFQ card lists them all, option 1 first.
      const qmap: Record<string, any[]> = {};
      const optsOf = (inqId: unknown) => (qmap[String(inqId)] || []).slice().sort((a, b) => (Number(a.option_no) || 1) - (Number(b.option_no) || 1));
      for (const x of (myq || [])) {
        let missing: string[] | null = null;
        if (x.status === 'draft') { try { const { data: sc } = await admin.rpc('fn_quote_structured_score', { p_quote: String(x.id) }); missing = Array.isArray((sc as any)?.missing) ? (sc as any).missing : null; } catch (_e) { /* the list is advice; the form still opens */ } }
        (qmap[String(x.inquiry_id)] ||= []).push({ ...x, items: itemsOf[String(x.id)] || [], missing, spec_hold: holdOf[String(x.id)] || null });
      }
      // Reveal gate for the scrub below. customer_api treats the mere existence of a transactions
      // row as "revealed" (line ~430: every tx row for the customer goes into revealedQ with no
      // further filter), and this function's own `projects` action already treats a supplier's
      // transactions rows as its paid-for jobs. Reusing that exact definition rather than
      // inventing a new one is what keeps post-reveal behaviour identical.
      const { data: txs } = await admin.from('transactions').select('inquiry_id').eq('supplier_id', sup.id).in('inquiry_id', ids);
      const revealedInq = new Set((txs || []).map((t) => String(t.inquiry_id)));
      // customer_id is selected ONLY to look up the buyer's own name for scrubIdentity. It is
      // never placed on the response - it is a stable id that would let a supplier correlate a
      // buyer across RFQs.
      // REGRESSION FIX 3 Aug 2026. When this select moved from `inquiries` to
      // `inquiries_supplier_safe` (audit 2.x), the safe view stopped exposing customer_id - which
      // is correct, a supplier must never receive it. But this block still read r.customer_id off
      // the view's rows, so custIds was ALWAYS empty, custName was ALWAYS empty, and buyerName was
      // ALWAYS null. scrubIdentity therefore lost its "buyer's own name" input entirely: the second
      // independent layer had been silently switched off, leaving only the write-time masking.
      // deno check caught it as a type error; the runtime effect was invisible.
      //
      // The owner is now read from the raw table under the service role, keyed by inquiry id. It
      // exists only inside this function to feed the scrubber and is never placed on the response.
      // AUDIT 1.5 EXTENSION (4 Aug 2026). FAIL CLOSED, the way customer_api already does.
      //
      // Both lookups below dropped their `error`. On a failed read ownerOf/custName stayed empty,
      // buyerName came out null, and scrubIdentity(text, null, hits) silently skips the name
      // pattern and RETURNS THE TEXT ANYWAY — so the buyer's name would go out in summary, spec,
      // boq and budget to every matched supplier pre-reveal, with no 503, no drop and no log.
      // The customer→supplier direction got a {resolved} discriminator on 3 Aug; this inbox, the
      // surface that actually serves buyer free text pre-reveal, had no such concept.
      //
      // The database is not a backstop: mask_contacts() strips contacts and leaves names —
      // 'Villa fit-out for Ahmed Khan, call [hidden] or [hidden]', verified on production.
      //
      // Note the asymmetry `ownerResolved` encodes. An inquiry with no customer_id is RESOLVED
      // with nothing to scrub; a lookup that ERRORED is not resolved, and its free text must be
      // dropped. A supplier who receives less detail can still quote; a buyer whose name reached
      // eight strangers cannot be un-sent. This is a batch read, so a single error drops the whole
      // page's free text — coarser than customer_api's per-inquiry check, deliberately so.
      let ownerResolved = true;
      const ownerOf: Record<string, string> = {};
      const projectOf: Record<string, string> = {};
      // rfq_no rides on the owner read: the ONE job number (audit 21 Sep 2026, finding 7), read from the
      // table because the supplier-safe projection does not carry it and a sequence number identifies nobody.
      const rfqOf: Record<string, number | null> = {};
      // WITHHELD, SAID OUT LOUD (22 Sep 2026, sales_engineer). A customer's file that could not be shared
      // without identifying them (a held drawing, any CAD file) left the supplier with no drawing and no
      // word that one existed. Only the FACT is read here — the path never leaves this function.
      const hasOriginal = new Set<string>();
      { const { data: owners, error: eOwners } = await admin.from('inquiries').select('id,customer_id,project_id,rfq_no,drawing_file_path').in('id', ids);
        if (eOwners) ownerResolved = false;
        else for (const o of (owners || [])) { rfqOf[String(o.id)] = o?.rfq_no ?? null; if (o?.drawing_file_path) hasOriginal.add(String(o.id)); if (o?.customer_id) ownerOf[String(o.id)] = String(o.customer_id); if (o?.project_id) projectOf[String(o.id)] = String(o.project_id); } }
      const custIds = Array.from(new Set(Object.values(ownerOf)));
      const custName: Record<string, string> = {};
      // 14 Sep 2026 (founder: nothing that identifies the customer may reach a supplier). The buyer's
      // email, phone and PROJECT NAME are read too: they are the seed list _shared/anonymise removes
      // wherever it appears, because the leak audit measured project names reaching suppliers inside
      // BOQ lines that no pattern could recognise.
      const custRow: Record<string, any> = {};
      if (ownerResolved && custIds.length) { const { data: cs, error: eCust } = await admin.from('customers').select('id,full_name,email,phone').in('id', custIds); if (eCust) ownerResolved = false; else for (const c of (cs || [])) { custRow[String(c.id)] = c; if (c.full_name) custName[String(c.id)] = String(c.full_name); } }
      const projName: Record<string, string> = {};
      { const pids = Array.from(new Set(Object.values(projectOf)));
        if (ownerResolved && pids.length) { const { data: ps, error: eP } = await admin.from('projects').select('id,name').in('id', pids); if (eP) ownerResolved = false; else for (const p of (ps || [])) if (p.name) projName[String(p.id)] = String(p.name); } }
      if (!ownerResolved) {
        // Say so. The worst property of the previous behaviour was not that it failed open — it
        // was that it failed open in silence, so the failure had no observable consequence at all.
        try {
          await admin.from('agent_runs').insert({
            agent: 'supplier_api', status: 'error', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
            counts: { signal: 'buyer_identity_unresolved', inquiries: ids.length },
            note: ('supplier inbox: the inquiry owner could not be read, so customer-authored text was dropped from '
              + ids.length + ' pre-reveal inquiry row(s) rather than emitted unscrubbed.').slice(0, 500),
          });
        } catch (_e) { /* never let the trail block the response */ }
      }
      // Sign every redacted drawing page for the whole inbox page at once. A page that cannot be signed
      // is counted and raised rather than dropped in silence; the pages that did sign are still served.
      const pagesOf = await signRedactedDrawings(admin, (inq || []).map((i) => ({ id: i.id, paths: i.drawing_redacted_paths })));
      const out: any[] = [];
      const gatedBoqs: unknown[] = [];
      for (const i of (inq || [])) {
        const dp = pagesOf[String(i.id)] || { urls: [], expected: 0, served: 0, failed: 0 };
        const pages: string[] = dp.urls;
        const concluded = CONCLUDED.includes(String(i.status));
        const youWon = i.hired_supplier_id != null && Number(i.hired_supplier_id) === Number(sup.id);
        // Pre-reveal, the buyer's own free text is scrubbed on the way out. Once this supplier
        // has a transactions row for this inquiry the reveal has been paid for, and summary /
        // spec / boq are served byte-identically to before this change.
        const revealed = revealedInq.has(String(i.id));
        const hits: string[] = [];
        const buyerName = custName[ownerOf[String(i.id)] || ''] || null;
        // ownerResolved === false means we could not READ the owner, which is not the same as
        // "this inquiry has no owner". We cannot scrub a name we could not read, so the buyer's
        // own text is withheld rather than emitted unscrubbed. Category, emirate, status, quote
        // and the redacted drawings still go out — enough to log in and quote.
        const owner = custRow[ownerOf[String(i.id)] || ''] || {};
        const seeds = seedTerms({ name: buyerName || '', email: owner.email || '', phone: owner.phone || '', project: projName[projectOf[String(i.id)] || ''] || '' });
        // THE SAME GATE FOR THE SUMMARY (re-review of #854). It had redactText and nothing after it, so
        // it kept the glued forms the residual scan exists to catch: measured, "Fit-out for MarsaHeights
        // Villa 7" came out as "Fit-out for MarsaHeights █" and "re:MarsaHeights enquiry" came out
        // unchanged. Of the four customer-authored fields this is the one that is always populated and
        // always on the card, so it was the widest of the three leaks, not the narrowest.
        const summaryGate = revealed || !ownerResolved ? null : inboxField<string>(i.summary ?? null, buyerName, seeds, hits);
        const sSummary = revealed ? i.summary : (summaryGate ? summaryGate.boq : null);
        const summaryWithheld = summaryGate ? summaryGate.withheld : false;
        // THE BOQ'S OWN GATE, APPLIED TO THE STRUCTURED BRIEF (audit 22 Sep 2026, finding SP-F-04).
        // spec ran scrubDeep alone, so the customer's PROJECT NAME — which no pattern recognises — left
        // the estate inside the brief. inboxField is redactBoq: seed redaction, then the residual scan
        // that catches the glued forms word-boundary redaction cannot, and it WITHHOLDS rather than
        // serving a field it cannot prove clean.
        const specGate = revealed || !ownerResolved ? null : inboxField(i.spec, buyerName, seeds, hits);
        const sSpec = revealed ? i.spec : (specGate ? specGate.boq : null);
        const specWithheld = specGate ? specGate.withheld : false;
        // THE LAST GATE before a supplier sees a BOQ. redactBoq removes the buyer's seed terms and the
        // generic identifiers, then residual-scans; anything still identifying HOLDS the BOQ (null,
        // boq_withheld:true). It never fails open: a BOQ we cannot prove clean is not shown.
        // One function (identity_scrub.ts inboxBoq) so drawing_boq/drawing_chain.test.ts runs this gate.
        const gated = revealed || !ownerResolved ? null : inboxBoq(i.boq, buyerName, seeds, hits);
        const boqWithheld = gated ? gated.withheld : false;
        const sBoq = revealed ? i.boq : (gated ? gated.boq : null);
        const sBoqAr = sBoq || null;   // its Arabic headings are added after the loop
        if (gated?.boq) gatedBoqs.push(gated.boq);   // only a gated BOQ's headings may be reasoned over
        // The scope in Arabic is the REASONED translation of the (already scrubbed) summary, filled in after the
        // loop in one batch (decision point trade_glossary_ar); until it exists — under the model hold — it stays
        // null and the portal shows the customer's own words, never a partial or word-by-word reading.
        const sSummaryAr: string | null = null;
        // ANONYMITY FIX 29 Jul 2026. budget is an 80-char FREE-TEXT box, not a number ("around
        // 250k, call Ahmad on 050 123 4567"), and it was the one customer-authored field on this
        // response still emitted verbatim while summary / spec / boq were scrubbed. It now goes
        // through the same scrubIdentity as summary, behind the same reveal gate.
        // 22 Sep 2026 (finding SP-F-04): and through the same gate, for the same reason. "around 250k for
        // the Marsa Heights villa" named the project in the one box a customer types freely.
        const budgetGate = revealed || !ownerResolved ? null : inboxField<string>(i.budget ?? null, buyerName, seeds, hits);
        const sBudget = revealed ? i.budget : (budgetGate ? budgetGate.boq : null);
        const budgetWithheld = budgetGate ? budgetGate.withheld : false;
        out.push({ id: i.id, rfq_no: rfqOf[String(i.id)] ?? null, job_no: jobNo({ id: String(i.id), rfq_no: rfqOf[String(i.id)] }), category: i.category, emirate: i.emirate, summary: sSummary, summary_withheld: summaryWithheld, summary_ar: sSummaryAr, spec: sSpec, spec_withheld: specWithheld, created_at: i.created_at, budget: sBudget || null, budget_withheld: budgetWithheld, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: sBoqAr || null, boq_withheld: boqWithheld, boq_confidence: i.boq_confidence || null, drawing_file_name: null, drawing_file_url: null, drawing_pages: pages, drawing_pages_expected: dp.expected, drawing_pages_served: dp.served, drawing_pages_failed: dp.failed, drawing_withheld: drawingWithheld(hasOriginal.has(String(i.id)), dp.expected), status: i.status, concluded, you_won: youWon, revealed, quote: optsOf(i.id)[0] || null, quotes: optsOf(i.id) });
      }
      // The BOQ read in Arabic (audit 21 Sep 2026, findings 26/27). Which Arabic heading a section means is
      // reasoned (decision point documents.boq_arabic) over the GATED BOQs only — a revealed BOQ is the customer's
      // unscrubbed text, so it only looks up readings already remembered and never adds a heading of its own.
      // Under the hold an unread heading keeps its original words.
      const served = out.filter((o) => o.boq);
      if (served.length) {
        const readings = await boqReadings(defaultDeps(admin, 'supplier_api'), liveReadingStore(admin), gatedBoqs, served.map((o) => o.boq)).catch(() => ({} as Record<string, string>));
        for (const o of served) o.boq = boqWithArabic(o.boq, readings);
      }
      const summaries = out.map((o) => o.summary).filter((x): x is string => typeof x === 'string' && !!x.trim());
      if (summaries.length) {
        try {
          const ar = await arabicOf(defaultDeps(admin, 'supplier_api'), { texts: summaries, fileOnly: true });   // a list never waits on a model
          for (const o of out) if (typeof o.summary === 'string' && ar.map[o.summary.trim()]) o.summary_ar = ar.map[o.summary.trim()];
        } catch (_e) { /* the portal shows the customer's own words */ }
      }
      return J({ inquiries: out, approval_status: sup.approval_status });
    }
    // A SUPPLIER'S OWN DOCUMENTS AS PDF (15 Sep 2026, sales_engineer). The customer could download every
    // quotation (customer_api quote_pdf); the supplier who wrote it could not, and had no receipt for a
    // charge it had paid. quote_pdf prints the SAME standardised quotation the customer receives
    // (_shared/quote_documents.ts quoteDocument), for this supplier's own quote only; receipts and
    // receipt_pdf list and print the dues this supplier has paid. pdf_native is reached with this
    // function's own scoped credential — fn.supplier_api's scope already holds pdf_native (measured
    // 15 Sep 2026 in internal_credential), so no credential or database change is needed.
    if (action === 'quote_pdf' || action === 'inquiry_pdf' || action === 'receipts' || action === 'receipt_pdf') {
      const { data: sup } = await admin.from('leads').select('id,company_name').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const lang: 'en' | 'ar' = body.lang === 'ar' ? 'ar' : 'en';
      const print = async (doc: Record<string, unknown>) => {
        const secret = await secretVal('cred_fn_supplier_api');
        if (!secret) return null;
        const r = await fetch(`${SUPA_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...doc, folder: 'supplier/' + sup.id, __secret: secret }) });
        const j = await r.json().catch(() => null);
        return j?.ok && j.url ? { url: String(j.url), bucket: String(j.bucket || 'agent-docs'), path: String(j.path || '') } : null;
      };
      // CACHED LIKE quote_pdf (21 Sep 2026, sales_engineer). The customer's quotation is cached in
      // quote_pdf_cache keyed on (quote_id, lang) and invalidated by quotes.updated_at. The supplier's
      // two documents cannot share that key (the same quote prints differently for each side: letter
      // 'S', no request text) and the inquiry has no updated_at at all, so public.supplier_document_cache
      // keys on (kind, subject, supplier, lang) and carries a hash of the INPUT that produced the file
      // (scripts/sql/the_inquiry_and_the_suppliers_own_quotation_are_cached_as_documents.sql). An edited
      // inquiry or quote changes the hash and is printed again; a reveal changes what the inbox serves
      // and so changes the hash too. The cache row is never read for anything but the file's location.
      const hashOf = async (input: unknown) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(input))))).map((b) => b.toString(16).padStart(2, '0')).join('');
      const sign = async (b: string, p: string) => { try { const { data } = await admin.storage.from(b).createSignedUrl(p, 3600); return data?.signedUrl || null; } catch (_e) { return null; } };
      // An Arabic document with a line not yet translated by reasoning (the founder's model hold): held, not half-printed.
      const ARABIC_HELD_REPLY = { ok: false, held: true, code: 'arabic_held',
        message: 'The Arabic version is being prepared by our sales engineer and will be ready shortly. The English version is available now.',
        message_ar: 'يُعدّ مهندس المبيعات لدينا النسخة العربية وستكون جاهزة قريبًا. النسخة الإنجليزية متاحة الآن.' };
      const served = async (kind: 'inquiry' | 'quotation', subject: string, hash: string, build: () => Promise<{ doc: Record<string, unknown>; ref: string } | null>) => {
        const { data: hit } = await admin.from('supplier_document_cache').select('bucket,path,content_hash').eq('kind', kind).eq('subject_id', subject).eq('supplier_id', sup.id).eq('lang', lang).maybeSingle();
        if (hit && hit.content_hash === hash) { const url = await sign(hit.bucket, hit.path); if (url) return { url, cached: true }; }
        // The same per-hour ceiling customer_api holds (PDF_LIMIT_PER_HOUR = 40): a supplier who
        // regenerates in a loop is told so rather than served a queue of renders.
        const { count } = await admin.from('supplier_document_cache').select('kind', { count: 'exact', head: true }).eq('supplier_id', sup.id).gte('created_at', new Date(Date.now() - 3600e3).toISOString());
        if ((count || 0) >= 40) return { error: 'rate_limited' as const };
        const built = await build(); if (!built) return null;
        const out = await print(built.doc); if (!out) return null;
        try { await admin.from('supplier_document_cache').upsert({ kind, subject_id: subject, supplier_id: sup.id, lang, content_hash: hash, bucket: out.bucket, path: out.path, created_at: new Date().toISOString() }, { onConflict: 'kind,subject_id,supplier_id,lang' }); } catch (_e) { /* the file is served either way */ }
        return { url: out.url, cached: false, ref: built.ref };
      };

      if (action === 'quote_pdf') {
        const { data: q } = await admin.from('quotes').select('*').eq('id', String(body.quote_id || '')).eq('supplier_id', sup.id).maybeSingle();
        if (!q) return J({ error: 'Quote not found', code: 'not_found' }, 404);
        const [{ data: inq }, { data: qi }, { data: spec }, { data: matches }] = await Promise.all([
          admin.from('inquiries_supplier_safe').select('id,category,emirate').eq('id', q.inquiry_id).maybeSingle(),
          admin.from('quote_items').select('*').eq('quote_id', String(q.id)).order('line_no', { ascending: true }).limit(60),
          // the customer's intake answers decide what the completeness checks require (assess.ts); read
          // here for the checks only, never printed; rfq_no is the one job number (audit 21 Sep 2026, finding 7)
          admin.from('inquiries').select('spec,rfq_no').eq('id', q.inquiry_id).maybeSingle(),
          admin.from('inquiry_matches').select('id,supplier_id').eq('inquiry_id', q.inquiry_id).order('id', { ascending: true }),
        ]);
        // The completeness checks and each line's specs come from the hold desk's own reader
        // (_shared/quote_documents.ts completenessOf — audit 21 Sep 2026, finding 4).
        const done = completenessOf(q as any, itemsOfRows(qi), inq?.category ?? null, spec?.spec ?? null);
        const items: Item[] = done.items;
        // The customer's request text is NOT printed (summary: null): pre-reveal it reaches a supplier only
        // through the inbox's scrubbers, and this document must not become a second, unscrubbed door.
        // ONE ALIAS PER SUPPLIER PER JOB (audit 21 Sep 2026, finding 29: "Supplier A" in the question
        // thread, "Supplier S" on the quotation). The supplier's letter is its place in the job's match
        // order — the rule messages_api already uses for the question thread — never the customer's
        // price-rank letter, which a supplier must not learn.
        const order = [...new Set((matches || []).map((m: { supplier_id: number }) => Number(m.supplier_id)))];
        const letter = jobAlias(order, Number(sup.id)).replace(/^Supplier /, '');
        const inquiry = { id: String(q.inquiry_id), rfq_no: spec?.rfq_no ?? null, category: inq?.category ?? null, emirate: inq?.emirate ?? null, summary: null };
        const ref = quoteRef(inquiry, letter);
        // The supplier's own words in Arabic are reasoned; a line not yet translated holds the Arabic document.
        let heldAr = false;
        const r = await served('quotation', String(q.id), await hashOf({ q, items, inquiry, letter, checks: done.quote, layout: DOC_VERSION }), async () => {
          const d = await nativeArabic(defaultDeps(admin, 'supplier_api'), (arTexts) => quoteDocument({ quote: done.quote, inquiry, items, letter, lang, arTexts }), { subject: { quote_id: q.id } });
          if (!d.doc) { heldAr = true; return null; }
          return { doc: d.doc.body as Record<string, unknown>, ref };
        });
        if (heldAr) return J(ARABIC_HELD_REPLY, 202);
        if (r && 'error' in r) return J({ error: 'You have generated many PDFs recently. Please try again shortly.', code: 'rate_limited' }, 429);
        return r ? J({ ok: true, url: r.url, ref, lang, cached: r.cached }) : J({ error: 'pdf_failed', code: 'pdf_failed' }, 502);
      }

      // THE INQUIRY AS A DOCUMENT (21 Sep 2026, sales_engineer; founder instruction 435). The job is read
      // through this function's own `inbox`, in-process with the caller's session, so the document holds
      // only what the inbox's scrubbers and its reveal gate let this supplier see — and a job this
      // supplier is not matched to does not exist for them. The attachments it lists are the ones
      // inquiry_documents offers, from the same list.
      if (action === 'inquiry_pdf') {
        const iid = typeof body.inquiry_id === 'string' && UUID_RE.test(body.inquiry_id) ? body.inquiry_id.toLowerCase() : null;
        if (!iid) return J({ error: 'not_found', code: 'not_found' }, 404);
        const r0 = await handle(new Request(req.url, { method: 'POST', headers: { Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'inbox', inquiry_id: iid }) }));
        const j0 = await r0.json().catch(() => ({}));
        const i = (j0.inquiries || []).find((x: any) => String(x.id) === iid);
        if (!i) return J({ error: 'not_found', code: 'not_found' }, 404);
        const d = inquiryDocuments(i);
        const row: InquiryDocRow = { id: String(i.id), rfq_no: i.rfq_no ?? null, category: i.category ?? null, emirate: i.emirate ?? null, summary: i.summary ?? null, budget: i.budget ?? null,
          scope_type: i.scope_type ?? null, created_at: i.created_at ?? null, spec: i.spec ?? null, boq: i.boq ?? null, boq_withheld: !!i.boq_withheld,
          documents: d.documents.map((x: any) => ({ kind: x.kind, name: x.name, lines: x.lines })), drawing_pages_failed: d.drawing_pages_failed };
        const ref = quoteRef(row, 'RFQ');
        // The signed drawing URLs are not on the row, so the hash is stable across signings.
        let heldAr = false;
        const r = await served('inquiry', iid, await hashOf({ row, layout: DOC_VERSION }), async () => {
          const d = await nativeArabic(defaultDeps(admin, 'supplier_api'), (arTexts) => inquiryDocument({ inquiry: row, lang, portalUrl: CANONICAL_ORIGIN + (lang === 'ar' ? '/ar/portal' : '/portal'), arTexts }), { subject: { inquiry_id: iid } });
          if (!d.doc) { heldAr = true; return null; }
          return { doc: d.doc.body as Record<string, unknown>, ref };
        });
        if (heldAr) return J(ARABIC_HELD_REPLY, 202);
        if (r && 'error' in r) return J({ error: 'You have generated many PDFs recently. Please try again shortly.', code: 'rate_limited' }, 429);
        return r ? J({ ok: true, url: r.url, ref, job_no: d.job, lang, cached: r.cached }) : J({ error: 'pdf_failed', code: 'pdf_failed' }, 502);
      }

      // A paid due: stripe_webhook is the one writer of paid_at, so a row with it is a payment we recorded.
      const PAID = ['paid', 'settled'];
      const total = (d: any) => Math.round((Number(d.amount_due || 0) + Number(d.admin_fee || 0) + Number(d.interest_amount || 0) + Number(d.fine_amount || 0)) * 100) / 100;
      if (action === 'receipts') {
        const { data, error } = await admin.from('supplier_dues').select('id,amount_due,admin_fee,interest_amount,fine_amount,currency,paid_at')
          .eq('supplier_id', sup.id).in('status', PAID).not('paid_at', 'is', null).order('paid_at', { ascending: false }).limit(50);
        if (error) return J({ error: 'temporarily_unavailable', code: 'temporarily_unavailable' }, 503);
        const { data: reg } = await admin.from('leads').select('registration_paid_at,registration_amount_aed').eq('id', sup.id).maybeSingle();
        const regRow = reg?.registration_paid_at && Number(reg.registration_amount_aed) > 0 ? [{ id: null, kind: 'registration', paid_at: reg.registration_paid_at, total: Number(reg.registration_amount_aed), currency: 'AED' }] : [];
        return J({ ok: true, receipts: [...regRow, ...(data || []).map((d: any) => ({ id: d.id, kind: 'dues', paid_at: d.paid_at, total: total(d), currency: d.currency || 'AED' }))] });
      }

      // OUR invoice and receipt for a payment to QuotesDone, on the template (audit 22 Sep 2026, finding 2):
      // _shared/supplier_payment_documents.ts. doc 'invoice' | 'receipt' (default receipt); kind
      // 'registration' prints the annual listing fee, otherwise the settled charges of one payment.
      const docKind: 'invoice' | 'receipt' = body.doc === 'invoice' ? 'invoice' : 'receipt';
      const build = docKind === 'invoice' ? supplierInvoiceDocument : supplierReceiptDocument;
      const { data: lead } = await admin.from('leads').select('email,registration_paid_at,subscription_paid_until,registration_payment_ref,registration_amount_aed').eq('id', sup.id).maybeSingle();
      let pay: SupplierPayment;
      if (body.kind === 'registration') {
        if (!lead?.registration_paid_at || !(Number(lead.registration_amount_aed) > 0)) return J({ error: 'Receipt not found', code: 'receipt_not_found' }, 404);
        const at = String(lead.registration_paid_at);
        pay = { kind: 'registration', ref: `QD-REG-${sup.id}-${at.slice(0, 4)}`, paid_at: at, payment_ref: String(lead.registration_payment_ref || '—'),
          supplier: { name: String(sup.company_name || '—'), email: lead.email ?? null },
          period: lead.subscription_paid_until ? { from: at.slice(0, 10), to: String(lead.subscription_paid_until) } : null,
          lines: [{ en: 'Annual supplier Subscription Fee', ar: 'رسوم الاشتراك السنوية للمورّد', amount: Number(lead.registration_amount_aed) }], total: Number(lead.registration_amount_aed) };
      } else {
        const { data: d } = await admin.from('supplier_dues').select('id,amount_due,admin_fee,interest_amount,fine_amount,paid_at,payment_ref')
          .eq('id', Number(body.due_id) || 0).eq('supplier_id', sup.id).in('status', PAID).not('paid_at', 'is', null).maybeSingle();
        if (!d) return J({ error: 'Receipt not found', code: 'receipt_not_found' }, 404);
        // One payment settles every due in its checkout (stripe_webhook writes the same payment_ref on
        // each), so the document covers the whole payment and its total is what the card was charged.
        const { data: all } = await admin.from('supplier_dues').select('id,amount_due,admin_fee,interest_amount,fine_amount,paid_at,payment_ref')
          .eq('supplier_id', sup.id).in('status', PAID).eq('payment_ref', String(d.payment_ref || '')).order('id', { ascending: true });
        const rowsPaid = d.payment_ref && all?.length ? all : [d];
        const lines = duesLines(rowsPaid);
        pay = { kind: 'dues', ref: 'QD-DU-' + String(rowsPaid[0].id), paid_at: String(rowsPaid[0].paid_at), payment_ref: String(d.payment_ref || '—'),
          supplier: { name: String(sup.company_name || '—'), email: lead?.email ?? null }, lines, total: Math.round(lines.reduce((a, l) => a + l.amount, 0) * 100) / 100 };
      }
      const doc = build(pay, lang);
      const url = await print(doc as unknown as Record<string, unknown>);
      return url ? J({ ok: true, url: url.url, ref: pay.ref, doc: docKind, lang }) : J({ error: 'pdf_failed', code: 'pdf_failed' }, 502);
    }

    if (action === 'projects') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // A REVEALED JOB WITH NO WAY TO REACH THE CUSTOMER (14 Sep 2026). A transactions row is the
      // reveal — the customer paid to know this supplier — and the signed Supplier Agreement (v9, cl.
      // 11 and 33) then obliges the supplier to respond within 5 working days, chased at 3. The tab
      // listed category, amount and date only: no customer name or number, no deadline, and no way to
      // say "done". The contact is served HERE and only here, keyed on the supplier's own transactions
      // rows, so it cannot reach a supplier before a reveal. Deadlines come from fn_add_working_days,
      // the one working-day calendar refund_flow and the nudges use.
      const { data: projs } = await admin.from('transactions').select('id,inquiry_id,customer_id,revealed_at,quote_amount,refund_deadline,supplier_ack_at,refund_status,inquiries(category,emirate,summary)').eq('supplier_id', sup.id).not('revealed_at', 'is', null).order('revealed_at', { ascending: false }).limit(50);
      const custIds = Array.from(new Set((projs || []).map((p: any) => p.customer_id).filter(Boolean)));
      const cust: Record<string, any> = {};
      if (custIds.length) { const { data: cs } = await admin.from('customers').select('id,full_name,email,phone').in('id', custIds); for (const c of (cs || [])) cust[String(c.id)] = c; }
      const wd = async (from: string, n: number) => { try { const { data } = await admin.rpc('fn_add_working_days', { p_from: from, p_days: n }); return (data as string) || null; } catch (_e) { return null; } };
      const out: any[] = [];
      for (const p of (projs || []) as any[]) {
        const c = cust[String(p.customer_id)] || {};
        out.push({ id: p.id, inquiry_id: p.inquiry_id, category: p.inquiries?.category || null, emirate: p.inquiries?.emirate || null, summary: p.inquiries?.summary || null,
          revealed_at: p.revealed_at, amount: p.quote_amount, acknowledged_at: p.supplier_ack_at || null, refund_status: p.refund_status || null,
          chase_at: await wd(p.revealed_at, 3), respond_by: p.refund_deadline || await wd(p.revealed_at, 5),
          customer: { name: c.full_name || null, email: c.email || null, phone: c.phone || null } });
      }
      return J({ ok: true, projects: out });
    }
    // "I have contacted the customer" from inside the portal. supplier_ack does the same from the
    // reminder e-mail's one-click link (by ack_token); this is the signed-in door to the same column,
    // scoped to the caller's own transaction, and it stops the nudges the same way.
    if (action === 'ack_contact') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const txId = String(body.transaction_id || ''); if (!UUID_RE.test(txId)) return J({ error: 'invalid transaction', code: 'invalid_transaction' }, 400);
      const { data: t } = await admin.from('transactions').select('id,supplier_id,supplier_ack_at').eq('id', txId).maybeSingle();
      if (!t || Number(t.supplier_id) !== Number(sup.id)) return J({ error: 'not found', code: 'not_found' }, 404);
      if (t.supplier_ack_at) return J({ ok: true, acknowledged_at: t.supplier_ack_at });
      const now = new Date().toISOString();
      const { error } = await admin.from('transactions').update({ supplier_ack_at: now }).eq('id', txId).is('supplier_ack_at', null);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, acknowledged_at: now });
    }
    if (action === 'extract_quote') {
      const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,accepted_terms_at').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // The enquiry must be one this supplier was matched to (finding SP-N-03). This also makes
      // inquiry_id a validated uuid before it is put into the storage path below, which it was not.
      const inquiry_id = await matchedInquiry(Number(sup.id), body.inquiry_id);
      if (!inquiry_id) return J({ error: 'not_found', code: 'not_found' }, 404);
      const images = Array.isArray(body.images) ? body.images : [];
      const orig = body.original || {};
      // 14 Sep 2026: a Word, Excel, email or zip quotation has no page images, but quote_extract can
      // now read the original itself (doc_read, no model). Only a request with neither is unreadable.
      if (!images.length && !orig.b64) return J({ error: 'Could not read the file pages. Please attach a clear PDF or photo.', code: 'quote_no_pages' }, 400);
      let original_file_path: string | null = null, original_file_name: string | null = null;
      // AUDIT 9.1 (3 Aug 2026). The supplier's original quotation document. It is stored and later
      // served back to admins and, on some paths, referenced to the customer. It had no type check
      // and defaulted to application/octet-stream, and the failure was swallowed - so a rejected or
      // failed upload silently produced a quote with no attached document.
      if (orig.path) {
        // Finding SP-N-04: a path the caller supplies is accepted only under this supplier's own prefix.
        if (!ownQuoteFile(orig.path, Number(sup.id))) return J(NOT_MY_FILE, 400);
        original_file_path = String(orig.path);
        original_file_name = safeFilename(orig.filename || 'quotation', 'application/pdf');
      } else if (orig.b64) {
        const sc = await sanitizeAndScan({ input: String(orig.b64), declaredMime: orig.mime, filename: orig.filename || 'quotation', allow: SAFE_DOCS,
                                           scan: { source: 'supplier_api.quotation', subject: String(sup.id), filename: orig.filename, bucket: 'quote-files' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'That quotation file cannot be accepted. Please attach a PDF, photo, Word, Excel or email file.' }, sc.status);
        const s = sc.result;
        original_file_name = safeFilename(orig.filename || 'quotation', s.mime);
        original_file_path = `quotes/${sup.id}/${inquiry_id}/${Date.now()}_${original_file_name}`;
        const up = await admin.storage.from('quote-files').upload(original_file_path, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error) return J({ error: 'upload_failed', code: 'upload_failed', message: 'We could not store your quotation file. Please try again.' }, 502);
      }
      const { data: inq } = await admin.from('inquiries').select('category,summary').eq('id', inquiry_id).maybeSingle();
      const secret = await secretVal('cred_fn_supplier_api');
      let jd: any = {};
      try { const r = await fetch(`${SUPA_URL}/functions/v1/quote_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, subject: { supplier_id: (sup as any).id, email }, images, inquiry: inq || {}, ...(orig.b64 ? { file_b64: String(orig.b64), mime: String(orig.mime || ''), filename: String(orig.filename || 'quotation') } : {}), supplier_terms: [String((sup as any).company_name || '')].filter(Boolean) }) }); jd = await r.json(); } catch (e) { return J({ error: 'Reading failed, please try again or fill the form.', code: 'quote_read_failed', detail: String((e as Error)?.message || e) }, 502); }
      // Under the OpenRouter hold quote_extract has no model to call, so this is the expected path:
      // the code tells the portal to say "fill in the form", which is a complete way to quote.
      if (!jd?.ok) return J({ error: jd?.error || 'Could not read the quotation. Please fill the form instead.', code: 'quote_read_failed', detail: jd?.detail || null }, 502);
      // WHO READ IT (founder instruction ~891). The model quote_extract read this quotation with, kept per supplier and
      // inquiry so the quote submitted from it carries its author and quote_compare can be routed to another family.
      const readBy = typeof jd.extracted_by_model === 'string' && jd.extracted_by_model ? jd.extracted_by_model : 'unknown';
      const { error: xmErr } = await admin.from('quote_extraction_model').upsert({ subject_key: `${sup.id}:${inquiry_id}`, model: readBy, extracted_at: new Date().toISOString() });
      if (xmErr) console.error('quote_extraction_model: ' + xmErr.message);
      return J({ ok: true, proposal: jd.proposal, original_file_path, original_file_name });
    }
    // THE TWO WAYS OUT OF A HOLD (founder, 14 Sep 2026). (a) fill in the missing details here: the
    // sales engineer regenerates the standardised quotation and the supplier approves it, and only
    // then is it released; (b) upload a revised quote, which is submit_quote again and supersedes the
    // hold. Every step is the sales_engineer seat's (_shared/line_specs/workflow.ts).
    if (action === 'spec_hold' || action === 'spec_fill' || action === 'spec_approve') {
      const { data: sup } = await admin.from('leads').select('id,locale,whatsapp,phone').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const qid = String(body.quote_id || '');
      if (!UUID_RE.test(qid)) return J({ error: 'not found', code: 'not_found' }, 404);
      const repo = supabaseRepo(admin, { dispatch: kickDelivery });
      const q = await repo.quote(qid);
      if (!q || Number(q.supplier_id) !== Number(sup.id)) return J({ error: 'not found', code: 'not_found' }, 404);
      const { data: inqRow } = await admin.from('inquiries').select('category,spec,rfq_no').eq('id', q.inquiry_id).maybeSingle();
      const { count: optCount } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('inquiry_id', q.inquiry_id).eq('supplier_id', sup.id);
      // deno-lint-ignore no-explicit-any
      const spec: any = inqRow?.spec;
      const ctx = { category: inqRow?.category ?? null, requirements: requirementsOf(spec), ref: jobNo({ id: String(q.inquiry_id), rfq_no: inqRow?.rfq_no }), multiOption: (optCount || 0) > 1,
                    ...(await specChecklist(inqRow?.category ?? null, String(q.id), 'stored')) };
      const signed = async (b?: string | null, p?: string | null) => { if (!b || !p) return null; try { const { data } = await admin.storage.from(b).createSignedUrl(p, 3600); return data?.signedUrl || null; } catch (_e) { return null; } };
      if (action === 'spec_hold') {
        const { data: hs } = await admin.from('quote_spec_hold').select('id,state,missing,note_en,note_ar,regenerated,regenerated_at,pdf_bucket,pdf_path,opened_at,approved_at,released_at').eq('quote_id', qid).order('id', { ascending: false }).limit(1);
        const hold = hs?.[0] || null;
        const lines = await repo.lines(qid);
        const a = assessQuote({ category: ctx.category, lines, terms: q, requirements: ctx.requirements, checklist: ctx.checklist });
        return J({ ok: true, quote_id: qid, option_no: q.option_no, hold: hold ? { ...hold, pdf_url: await signed(hold.pdf_bucket, hold.pdf_path) } : null, schema: formSchema(a, lines) });
      }
      if (action === 'spec_fill') {
        // The regenerated quotation is the standard quotation (quoteDocument, via workflow.ts pdfBody) in
        // the supplier's own language, under the one alias this supplier carries on this job (the rule
        // quote_pdf above uses). Audit 22 Sep 2026, finding 1: it was a blank page.
        const render = regenRender(q, sup, inqRow);
        const out = await fillIn(repo, qid, supplierOf(sup, email), body.values && typeof body.values === 'object' ? body.values : {}, ctx, render);
        if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 400);
        if (out.complete) return J({ ...out, pdf_url: await signed(out.pdf?.bucket, out.pdf?.path) });
        return J(out);
      }
      // THE THIRD DOOR (review of #854, finding SP-F-02). spec_approve RELEASES a held quote to the
      // customer through approve() -> acceptLive(), so "the review runs at the one door" was not true
      // while this one skipped it: a quote held for missing specs, filled in through spec_fill and
      // approved here, went out with rules 1-7 never asked. The release now depends on the review of the
      // STORED quote — by then the row, not any request, is the quotation — read through the same
      // scrubbed inbox and with the same engineer-recorded explanations.
      // IT RUNS AS THE PRECHECK, NOT INSIDE accept (re-review of #854). approve() marks the hold
      // released before it calls accept, and liveHold() reads only 'open' and 'awaiting_approval', so
      // a refusal from inside accept left the quote unsent AND the hold desk shut: spec_fill and
      // spec_approve both answered not_awaiting_approval and the supplier was told only that the quote
      // "still waits on its commercial terms", naming nothing to do. As a precheck the hold goes back
      // to 'open' carrying the review's own issues, in the shape the hold surface already renders.
      const out = await approve(repo, qid, supplierOf(sup, email), email, body.confirm, ctx,
        async (row) => (await acceptLive(String(row.id), String(row.inquiry_id), true)).accepted,
        async (row) => {
          const inqSafe = await safeInquiryOf(req, jwt, String(row.inquiry_id));
          // A transient inbox failure is NOT an approval and NOT a silent stranding: the desk stays
          // open with something the supplier can act on (try again), rather than closing on them.
          if (!inqSafe) return { missing: [{ scope: 'quote' as const, line_no: null, description: null, attr: 'review_unavailable', type: 'text' as const,
            label_en: 'We could not read this job just now, so we have not sent your quotation. Please confirm your approval again in a moment.',
            label_ar: 'تعذّر علينا قراءة هذا الطلب الآن، ولذلك لم نرسل عرضكم. يُرجى تأكيد الموافقة مرة أخرى بعد قليل.' }] };
          const rrow = await supabaseReviewRepo(admin).review(String(row.inquiry_id), Number(sup.id)).catch(() => null);
          // Read as the hold gate reads it (reasoned_matching.ts); held: nothing is read and every detail is asked.
          const rvw = reviewQuotation(inqSafe, await readWorking(defaultDeps(admin, 'supplier_api'), inqSafe, withResolved(workingFromStoredQuote(row, await repo.lines(String(row.id))), resolvedFrom(rrow?.working)), 'review:' + inqSafe.id + ':' + sup.id));
          if (rvw.approved) return null;
          return { missing: rvw.issues.map(issueAsMissing), issues: rvw.issues };
        });
      if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 409);
      return J(out);
    }
    if (action === 'submit_quote') {
      const { data: sup } = await admin.from('leads').select('id,company_name,locale,whatsapp,phone,accepted_terms_at,registration_status,approval_status,licence_gate_reason,rejection_reason').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // FIRST, AND BEFORE ANYTHING ELSE IS SAID ABOUT THIS ACCOUNT: is this enquiry one we sent them?
      // (finding SP-N-03 — this door never asked.) Every read below is keyed on this id, not on the body's.
      const inquiryId = await matchedInquiry(Number(sup.id), body.inquiry_id);
      if (!inquiryId) return J({ error: 'not_found', code: 'not_found' }, 404);
      if (!sup.accepted_terms_at) return J({ error: 'accept the supplier terms first', code: 'terms_not_accepted' }, 400);
      // 3 SEP 2026 (MASTER_PLAN #11): there is no admin queue and never was - approval is the automatic
      // licence gate on save. Say what actually blocked it and what unblocks it, instead of promising a
      // human decision "within 3 working days" that nobody would ever make.
      if (sup.approval_status !== 'approved') {
        const why = String(sup.licence_gate_reason || sup.rejection_reason || '').trim();
        return J({ error: 'Your registration is not verified yet' + (why ? ': ' + why : '') + '. Upload a clear, in-date trade licence from your Profile tab - it is re-checked automatically the moment it is saved, with no admin step.', code: 'not_verified', params: { reason: why || null }, reason: why || null }, 403);
      }
      // AUDIT 4.2. This gate used to read the stored registration_status, which setRegistration()
      // set to 'due' on every supplier past the (off-by-one) free count regardless of the date -
      // blocking suppliers from quoting a year before the fee is contractually charged. It now
      // asks the single source of truth, and fails CLOSED on an unavailable answer rather than
      // silently opening the paywall.
      {
        const { data: regSt, error: regErr } = await admin.rpc('fn_supplier_registration_state', { p_lead_id: sup.id });
        const reg = regSt as any;
        if (regErr || !reg?.ok) return J({ error: 'registration_state_unavailable', code: 'registration_state_unavailable', detail: regErr?.message || 'lead_not_found', hint: 'We could not confirm your registration status. Please try again shortly.' }, 503);
        if (reg.may_quote === false) return J({ error: 'Your ' + String(reg.currency || 'AED') + ' ' + Number(reg.fee_due || 0) + ' annual Subscription Fee is due. Please pay it in Billing to send quotes.', code: 'registration_due', params: { fee: Number(reg.fee_due || 0), currency: String(reg.currency || 'AED') }, registration: { status: reg.status, fee_due: reg.fee_due, currency: reg.currency, reason: reg.reason } }, 402);
      }
      const { data: inqStat } = await admin.from('inquiries').select('status').eq('id', inquiryId).maybeSingle();
      if (inqStat && CONCLUDED.includes(String(inqStat.status))) return J({ error: 'This request has been concluded — the customer has already selected a supplier. Thank you for your interest, and best of luck on the next one.', code: 'inquiry_concluded' }, 409);
      const amt = Number(body.amount); if (!(amt > 0)) return J({ error: 'invalid amount', code: 'invalid_amount' }, 400);
      const isUpload = body.source === 'upload';
      const items = Array.isArray(body.items) ? body.items : [];
      // Free text the supplier typed. On the FORM path it goes through scrubIdentity (see the
      // helper's note, 27 Jul 2026) before it is ever stored, because these four columns are read
      // straight back out to the buyer pre-payment. The UPLOAD path is left as-is: quote_extract
      // already anonymised it and supplies its own masked_terms, so scrubbing twice would only
      // mangle text a model has already cleaned.
      // 15 Sep 2026 (security review): the UPLOAD path is scrubbed too. submit_quote is callable
      // directly, so "source: upload" was a way past scrubIdentity for text typed by hand, and under the
      // model hold the quotation review sends every upload down this path. scrubIdentity leaves text
      // that is already clean unchanged, so a quotation quote_extract anonymised is unaffected.
      const maskHits: string[] = [];
      const scrub = (v: unknown, n: number) => scrubIdentity(clip(v, n), sup.company_name, maskHits);
      // What the scope itself states is read into its columns (line_specs/derive.ts — audit 21 Sep
      // 2026, finding 15): "Exclusions: …" typed inside the scope, and "installation included".
      const fromScope = deriveTermsFromScope(body.scope, body.exclusions);
      const sNotes = scrub(body.notes, 1000), sScope = scrub(body.scope, 2000), sCond = scrub(body.conditions, 2000), sExcl = scrub(body.exclusions || fromScope.exclusions || '', 2000);
      const priorMasked: string[] = Array.isArray(body.masked_terms) ? body.masked_terms.map((x: unknown) => String(x)) : [];
      const allMasked = [...priorMasked, ...maskHits.filter((h) => !priorMasked.includes(h))];
      const { data: inqRow } = await admin.from('inquiries').select('category,spec,rfq_no').eq('id', inquiryId).maybeSingle();
      // deno-lint-ignore no-explicit-any
      const requirements = requirementsOf(inqRow?.spec);
      const category = inqRow?.category ?? null;

      // VAT (founder, 14 Sep 2026: supplier VAT details are hidden from the customer). The price the
      // customer compares and the 3% is taken on is the price EXCLUDING VAT; the supplier's VAT
      // treatment, VAT amount and TRN are kept on the quote for the record only (vat.ts).
      const vatText = [body.notes, body.scope, body.conditions, body.exclusions, body.payment_terms, body.vat_note, ...items.map((it: any) => it?.description)].filter(Boolean).map(String).join('\n');
      const trn = findTrn(vatText) || (/^100\d{12}$/.test(String(body.trn || '')) ? String(body.trn) : null);

      // OPTIONS (founder, 14 Sep 2026: "if a supplier wanted to share 2 options on his quote, they will
      // be considered two different quotations ... each will have its own ID in the system"). A
      // submission whose lines carry option headings becomes one quote row per option, sharing the
      // submission's commercial terms; a single-option submission targets option_no (1, the one it
      // is editing, or a new one when the supplier adds another option).
      const normItems = items.map((it: any) => ({ ...it, description: String(it?.description ?? ''), amount: numOrNull(it?.amount) ?? (((numOrNull(it?.qty) || 0) * (numOrNull(it?.unit_price) || 0)) || null) }));
      const opts = splitOptions(normItems, body.option_totals && typeof body.option_totals === 'object' ? body.option_totals : {});
      const multi = opts.length > 1;
      const { data: mine } = await admin.from('quotes').select('id,option_no,status').eq('inquiry_id', inquiryId).eq('supplier_id', sup.id);
      const maxOpt = Math.max(0, ...(mine || []).map((r: any) => Number(r.option_no) || 1));
      const single = Number(body.option_no) >= 1 ? Math.floor(Number(body.option_no)) : (body.new_option === true ? maxOpt + 1 : 1);
      const plan = multi ? opts.map((o) => ({ option_no: o.option_no, lines: o.lines, amount: optionAmount(o) })) : [{ option_no: single, lines: opts[0]?.lines ?? normItems, amount: amt as number | null }];
      if (plan.some((p) => p.option_no > 20)) return J({ error: 'A quote can carry at most 20 options.', code: 'too_many_options' }, 400);
      const noTotal = plan.find((p) => !(Number(p.amount) > 0));
      if (noTotal) return J({ error: 'Enter the total for option ' + noTotal.option_no + '.', code: 'option_total_missing', params: { option: noTotal.option_no } }, 400);
      // Finding SP-N-04: the attached quotation file must be one of this supplier's own objects.
      const origPath = body.original_file_path == null || String(body.original_file_path) === '' ? null : String(body.original_file_path);
      if (origPath && !ownQuoteFile(origPath, Number(sup.id))) return J(NOT_MY_FILE, 400);

      // ── THE QUOTATION REVIEW RUNS AT EVERY DOOR (audit 22 Sep 2026, finding SP-F-02) ────────────
      // The founder, 15 Sep 2026: the review is "the most important part in the whole supplier portal".
      // Its rules live in quote_review.ts reviewQuotation — every BOQ line priced, quantities and units
      // matching the BOQ, prices in AED, the VAT basis stated, the lines adding up to the total, a
      // concrete validity, and the hold desk's own exact-specs assessment — and until now they ran ONLY
      // inside the chat. Two portal doors post to submit_quote directly (InquiriesTab -> QuoteForm, and
      // the Quote Builder's one-click accept), so a quotation that failed any of rules 1-7 reached the
      // customer through them.
      //
      // IT IS A HOLD, NOT A REFUSAL, and that correction matters (review of #854): a hard 400 would have
      // taken both quoting doors offline, because neither form has a field for several of the details
      // the review asks for. The quote is still written and still recoverable — exactly what the hold
      // desk already does — it simply never reaches the customer until the review passes. QuoteForm
      // already renders `held`, and the two ways out (spec_fill here, or a revised quotation through the
      // chat) are unchanged.
      //
      // WHAT THE SUPPLIER ALREADY EXPLAINED STILL COUNTS. A BOQ line the chat recorded as excluded, or a
      // quantity the supplier explained, lives in quote_reviews.working — written by the engineer, not by
      // the caller — so it is read from the row and never from the request body. A supplier posting
      // straight to this endpoint has no such row, and every rule applies to them in full.
      const confirmedTerms = sanitizeTermsSpec(body.terms_spec);
      const reviewRow = await supabaseReviewRepo(admin).review(inquiryId, Number(sup.id)).catch(() => null);
      const safeInq = await safeInquiryOf(req, jwt, inquiryId);
      if (!safeInq) return J({ error: 'not_found', code: 'not_found' }, 404);
      // Read as the hold gate reads it (reasoned_matching.ts); held: nothing is read and every detail is asked.
      const rv = reviewQuotation(safeInq, await readWorking(defaultDeps(admin, 'supplier_api'), safeInq, withResolved(
        workingFromSubmit(body, { notes: String(sNotes ?? ''), scope: String(sScope ?? ''), conditions: String(sCond ?? ''), exclusions: String(sExcl ?? '') }, confirmedTerms || {}, allMasked, trn),
        resolvedFrom(reviewRow?.working)), 'review:' + safeInq.id + ':' + sup.id));
      const lang: 'en' | 'ar' = String(sup.locale || '').toLowerCase().startsWith('ar') ? 'ar' : 'en';
      const reviewIssues = rv.approved ? null : rv.issues.map((i) => ({ code: i.code, kind: i.kind, line_no: i.line_no, boq_line: i.boq_line, attr: i.attr, en: i.en, ar: i.ar }));
      const reviewMissing = rv.approved ? [] : rv.issues.map(issueAsMissing);
      const reviewMessage = reviewIssues ? rv.issues.slice(0, 3).map((i) => (lang === 'ar' ? i.ar : i.en)).join(' ') : null;

      // The quote's author for quote_compare's independence routing: a typed quote has no model author; an uploaded one
      // carries the model quote_extract read it with (recorded at 'extract'), or 'unknown', which fails closed.
      // body.source is the client's word, so it never decides this (#880 review, item 2): the server's own extraction
      // record does. A record => its model; an upload with no record => 'unknown' (fails closed); otherwise typed by a person.
      const { data: xm } = await admin.from('quote_extraction_model').select('model').eq('subject_key', `${sup.id}:${inquiryId}`).maybeSingle();
      const quoteAuthor = typeof xm?.model === 'string' && xm.model ? xm.model : (isUpload ? 'unknown' : 'deterministic');
      const submission_id = crypto.randomUUID();
      const repo = supabaseRepo(admin, { dispatch: kickDelivery });
      const supplier = supplierOf(sup, email);
      const ref = jobNo({ id: String(inquiryId), rfq_no: inqRow?.rfq_no });
      const multiOption = multi || single > 1 || (mine || []).length > 1;
      const results: any[] = [];
      let anyAccepted = false;
      for (const p of plan) {
        const vat = readVat({ amount: p.amount, subtotal: multi ? null : numOrNull(body.subtotal), vat_amount: multi ? null : numOrNull(body.vat_amount), text: vatText,
          stated: body.vat_treatment ? String(body.vat_treatment) : null, price_ex_vat: multi ? null : numOrNull(body.price_ex_vat) });
        const det = { inquiry_id: inquiryId, supplier_id: sup.id, option_no: p.option_no, submission_id, quote_amount: vat.price_ex_vat ?? p.amount, price_ex_vat: vat.price_ex_vat, vat_treatment: vat.treatment, vat_amount: vat.vat_amount, supplier_trn: trn, amount_as_stated: p.amount,
          notes: sNotes, lead_time: clip(body.lead_time, 200), validity: clip(body.validity, 200), payment_terms: clip(body.payment_terms, 400), warranty: clip(body.warranty, 200), scope: sScope, conditions: sCond, exclusions: sExcl, source: isUpload ? 'upload' : 'form', extracted_by_model: quoteAuthor, anonymized: true, original_file_path: origPath, original_file_name: body.original_file_name || null, masked_terms: allMasked.length ? allMasked : null, structured: p.lines.length > 0 };
        // Delivery / installation / warranty the supplier confirmed in the quotation review, cleaned
        // (quote_review.ts) — the hold gate reads them exactly as it reads the portal's fill-in.
        if (confirmedTerms) (det as Record<string, unknown>).terms_spec = confirmedTerms;
        // Capture the status BEFORE the write. A new row is created as a draft, never in the
        // 'submitted' column default: a dry_run preflight or a held quote must not be visible to the
        // customer even for a moment (caught by a demo walkthrough on 21 Jul 2026).
        const prior = (mine || []).find((r: any) => (Number(r.option_no) || 1) === p.option_no) || null;
        // A DRY RUN LEAVES THE ESTATE AS IT FOUND IT (audit 22 Sep 2026, finding SP-C-02). "Check before
        // sending" reached the dry-run branch AFTER the writes below: it updated the prior quote row with
        // whatever was on screen, deleted its lines and re-inserted the new ones, and then restored only
        // `status`. A check run on a reopened quote that had already been sent therefore REWROTE the sent
        // quotation — amount, terms and every line — and a check on a new option left a draft behind. The
        // scorer, the accept rule and the hold assessment all read the row by id, so the row must exist
        // while they run; what must not survive is the change. The row and its lines are snapshotted here
        // and put back below, and a snapshot we could not take refuses the check rather than risking it.
        const dryRun = body.dry_run === true;
        const snapCols = [...Object.keys(det), 'status', 'submittable'].join(',');
        let snapRow: Record<string, unknown> | null = null;
        let snapLines: Record<string, unknown>[] = [];
        if (dryRun && prior) {
          const [{ data: sr, error: se }, { data: sl, error: sle }] = await Promise.all([
            admin.from('quotes').select(snapCols).eq('id', prior.id).maybeSingle(),
            admin.from('quote_items').select('*').eq('quote_id', prior.id),
          ]);
          if (se || sle || !sr) return J({ error: 'preflight_unavailable', code: 'preflight_unavailable', message: 'We could not run the check just now. Please try again in a moment.' }, 503);
          snapRow = sr as unknown as Record<string, unknown>; snapLines = (sl || []) as unknown as Record<string, unknown>[];
        }
        let qid: string;
        if (prior) { const { error } = await admin.from('quotes').update(det).eq('id', prior.id); if (error) return J({ error: error.message }, 500); qid = String(prior.id); }
        else { const { data: ins, error } = await admin.from('quotes').insert({ ...det, status: 'draft' }).select('id').single(); if (error) return J({ error: error.message }, 500); qid = String(ins.id); }
        try {
          await admin.from('quote_items').delete().eq('quote_id', qid);
          // A line's own words fill brand / model / specification where the caller sent none; a scope
          // that says installation is included, with no line carrying a labour or install figure, marks
          // the first line install = 0 — "included in the rate" — so the scorer's labour-or-installation
          // count reads what the supplier wrote (derive.ts, finding 15).
          const anyInstall = p.lines.some((it: any) => numOrNull(it.labour) != null || numOrNull(it.install) != null);
          const rows = p.lines.slice(0, 80).map((it: any, i: number) => { const dv = deriveLineFields(it); return { quote_id: qid, line_no: i + 1, description: clip(it.description, 300), brand: clip(it.brand || dv.brand, 120), model: clip(it.model || dv.model, 120), specification: clip(it.specification || dv.specification, 800), qty: numOrNull(it.qty), unit: clip(it.unit, 40), unit_price: numOrNull(it.unit_price), labour: numOrNull(it.labour), install: numOrNull(it.install) ?? (i === 0 && !anyInstall && fromScope.installation_included ? 0 : null), commissioning: numOrNull(it.commissioning), amount: numOrNull(it.amount) ?? ((numOrNull(it.qty) || 0) * (numOrNull(it.unit_price) || 0) || null), country_of_origin: clip(it.country_of_origin, 80), notes: clip(it.notes, 300), ...(() => { const s = sanitizeSpec(it.spec); return Object.keys(s.spec).length ? { spec: s.spec, spec_source: s.source } : {}; })() }; });
          // A line item with no description is dropped, not stored blank - a quote line the buyer
          // cannot read is worse than one that is absent.
          const clean = rows.filter((r: { description: string | null }) => r.description);
          if (clean.length) await admin.from('quote_items').insert(clean);
        } catch (_e) { /* */ }
        // Preflight (dry_run). Runs the real scorer, the real accept rule and the real hold gate's
        // assessment, then stops: the status is put back as it was, nothing is notified, no hold opens.
        if (dryRun) {
          const acc = await acceptRule(qid);
          // The same reading the real submission's gate does (reasoned_matching.ts), so the preflight and the gate agree.
          const dq = (await repo.quote(qid))!; const dl = await repo.lines(qid);
          const rd = applyReading(dl, dq.terms_spec, await readQuote(defaultDeps(admin, 'supplier_api'), { quoteId: qid, category, lines: dl, terms: dq, requirements }));
          const a = assessQuote({ category, lines: rd.lines, terms: { ...dq, terms_spec: rd.terms_spec }, requirements, checklist: (await specChecklist(category, qid, 'preflight')).checklist });
          // Put it back exactly as it was: the snapshotted columns and the snapshotted lines (with their
          // own ids, so anything that references a line still does). A row this check CREATED is removed.
          let restored = true;
          try {
            if (prior && snapRow) {
              const u = await admin.from('quotes').update(snapRow).eq('id', qid);
              const d = await admin.from('quote_items').delete().eq('quote_id', qid);
              const i2 = snapLines.length ? await admin.from('quote_items').insert(snapLines) : { error: null };
              restored = !u.error && !d.error && !i2.error;
            } else {
              const d = await admin.from('quote_items').delete().eq('quote_id', qid);
              const dq = await admin.from('quotes').delete().eq('id', qid);
              restored = !d.error && !dq.error;
            }
          } catch (_e) { restored = false; }
          // A FAILED RESTORE IS AN INCIDENT, NOT A FIELD ON A 200 (review of #854). Until this line it
          // answered ok:true with restored:false and a console line nobody reads, so a SENT quotation
          // could be left with its lines deleted and its terms overwritten and nothing would page. It
          // now writes an agent_runs error row — observe() pages those — and answers 500.
          if (!restored) {
            console.error('submit_quote dry_run: could not restore quote', qid);
            try {
              await admin.from('agent_runs').insert({ agent: 'supplier_api', status: 'error', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
                counts: { signal: 'dry_run_restore_failed', quote_id: qid, supplier_id: sup.id, inquiry_id: inquiryId, had_prior: !!prior, lines: snapLines.length },
                note: ('submit_quote dry_run could not restore quote ' + qid + ' after the preflight. The row may hold the checked figures instead of the ones the supplier sent. Restore it from this row.').slice(0, 500) });
            } catch (_e) { /* the page must not be what breaks the response */ }
            return J({ error: 'preflight_restore_failed', code: 'preflight_restore_failed', quote_id: qid, message: 'The check could not be undone cleanly and we have raised it. Please do not resend until we confirm.' }, 500);
          }
          results.push({ quote_id: qid, option_no: p.option_no, dry_run: true, accepted: false, restored, submittable: acc.submittable, would_accept: acc.accept && !a.held && !reviewIssues, review_issues: reviewIssues, status_after: prior?.status ?? null,
            accept_via: acc.submittable ? 'structured_score' : (acc.formComplete ? 'form_complete' : (!acc.requireStructured ? 'structured_not_required' : null)),
            require_structured: acc.requireStructured, priced_items: acc.priced, total_items: p.lines.length, score: acc.score,
            // The preflight card reads spec_missing, so the review's own issues belong in it for the
            // same reason (re-review of #854) — otherwise "Check before sending" calls a quote that
            // will be held a complete one.
            spec_missing: [...a.missing, ...reviewMissing], would_hold: a.held || !!reviewIssues });
          continue;
        }
        // THE HOLD GATE (founder, 14 Sep 2026). The sales engineer holds a quote that does not state
        // every required detail exactly, records which line and which detail, and tells the supplier.
        const g = await gate(repo, qid, supplier, { category, requirements, ref, multiOption, ...(await specChecklist(category, qid)),
          // His quotation is READ by reasoning before the check (decision points 29-30); held: nothing is read and he is asked.
          read: (qr, ls) => readQuote(defaultDeps(admin, 'supplier_api'), { quoteId: qid, category, lines: ls, terms: qr, requirements }) });
        if (g.held) { results.push({ quote_id: qid, option_no: p.option_no, accepted: false, held: true, missing: g.missing, code: 'spec_hold' }); continue; }
        // THE REVIEW'S OWN RULES, held the same way (finding SP-F-02). The gate above is the exact-specs
        // assessment; these are rules 1-7 — the BOQ priced line by line, quantities and units, prices in
        // AED, the VAT basis, the lines adding up, a concrete validity — which no door but the chat ran.
        // The quote stays a draft the supplier can complete or replace; it does not reach the customer.
        if (reviewIssues) {
          try { await admin.from('quotes').update({ status: 'draft' }).eq('id', qid); } catch (_e) { /* the result below already says it was not accepted */ }
          // THE CARD ALREADY KNOWS HOW TO SHOW THIS (re-review of #854). The portal renders a held
          // quote from `missing` / `spec_missing` — assess.ts MissingItem — and a review hold carried
          // neither, so QuoteCheck printed "Nothing missing — this is a complete quote." over a quote
          // that had just been held. The issues now go out in BOTH shapes: `missing` for every surface
          // that already reads it, `review_issues` for a client that wants the codes.
          results.push({ quote_id: qid, option_no: p.option_no, accepted: false, held: true, code: 'quote_review_changes', missing: reviewMissing, review_issues: reviewIssues, message: reviewMessage });
          continue;
        }
        const live = await acceptLive(qid, String(inquiryId), false);
        if (live.accepted) anyAccepted = true;
        results.push({ quote_id: qid, option_no: p.option_no, held: false, ...live });
      }
      if (anyAccepted) await notifyNewQuote(String(inquiryId));
      if (multi) return J({ ok: true, options: results, submission_id, accepted: results.some((r) => r.accepted), held: results.some((r) => r.held), dry_run: body.dry_run === true, code: 'options_split', params: { count: results.length } });
      const r0 = results[0];
      const q = { id: r0.quote_id, option_no: r0.option_no, status: r0.accepted ? 'submitted' : 'draft' };
      if (body.dry_run === true) return J({ ok: true, ...r0 });
      if (r0.held) return J({ ok: true, quote: q, accepted: false, held: true, missing: r0.missing ?? null, review_issues: r0.review_issues ?? null, code: r0.code || 'spec_hold',
        message: r0.message || 'Your quote is on hold until the exact details listed are stated. Fill them in here or upload a revised quote.' });
      if (r0.accepted) return J({ ok: true, quote: q, submittable: r0.submittable, accepted: true, coaching: r0.coaching, score: r0.score });
      return J({ ok: true, quote: q, submittable: false, accepted: false, coaching: r0.coaching, score: r0.score, code: 'draft_saved', message: 'Your quote was saved as a draft. Add the missing details so we can send it to the customer.' });
    }
    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String(e) }, 500);
  }
};
Deno.serve(observe('supplier_api', handle));
