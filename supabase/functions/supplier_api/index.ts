import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD, SAFE_DOCS } from '../_shared/attachment.ts';
import { seedTerms, redactBoq, redactText } from '../_shared/anonymise.ts';
import { asLocale } from '../_shared/registered_locale.ts';
// MALWARE WATCH, 9 Sep 2026. Every file a supplier sends is hashed and looked up before it reaches
// storage; a hash VirusTotal already knows to be malicious is refused here rather than stored,
// forwarded and served back. See _shared/malware.ts for why the lookup blocks and the analysis does not.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { storedAt } from '../_shared/stored_at.ts';
import { siteReturnBase } from '../_shared/site_origins.ts';
import { capabilityState, capabilityConfirm } from '../_shared/supplier_capability.ts';
import { registrationMissing } from '../_shared/supplier_registration.ts';
import { SUPPLIER_AGREEMENT_VERSION, SUPPLIER_AGREEMENT_EN, SUPPLIER_AGREEMENT_AR } from '../_shared/supplier_agreement.ts';
// The sales engineer's hold desk (14 Sep 2026): exact specs per line, delivery, installation,
// warranty and the ex-VAT price, or the quote is held; options are separate quotations.
import { approve, fillIn, formSchema, gate, pdfBody, supabaseRepo, type Render } from '../_shared/line_specs/workflow.ts';
import { assessQuote, requirementsOf } from '../_shared/line_specs/assess.ts';
import { optionAmount, splitOptions } from '../_shared/line_specs/options.ts';
import { readVat } from '../_shared/line_specs/vat.ts';
import { findTrn, LICENCE_NO, TRN_BARE, TRN_LABELLED } from '../_shared/identity_numbers.ts';
const agreementSha256 = async () => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(SUPPLIER_AGREEMENT_EN + '\n' + SUPPLIER_AGREEMENT_AR)))).map((b) => b.toString(16).padStart(2, '0')).join('');
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const PROFILE_COLS = ['contact_name','signatory_name','emirates_id','phone','products','services','description','certifications','founded_year','company_type','company_size','trade_license_no','license_authority','license_expiry','trn','bank_name','bank_account_name','bank_iban','license_doc_path','iban_doc_path','egr_doc_path','egr_doc_name','egr_number'];
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
function clientIp(req: Request): string { return (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') || ''; }
const clip = (v: unknown, n: number) => (v == null || String(v).trim() === '') ? null : String(v).slice(0, n);
// ANONYMITY FIX 27 Jul 2026 -------------------------------------------------------------------
// submit_quote stored the supplier's typed scope / conditions / exclusions / notes with nothing
// but a length clip, and set anonymized = (source === 'upload'). The UPLOAD path is scrubbed by
// quote_extract's model prompt; the FORM path was never scrubbed at all, so every typed quote was
// served to the buyer verbatim BEFORE the reveal is paid for. One supplier typing "call Ahmed on
// 050 123 4567, Al Noor Trading LLC, www.alnoor.ae" into scope hands the buyer everything the 3%
// reveal fee is charged for, and the platform is cut out of its own transaction.
//
// scrubIdentity redacts, case-insensitively: the supplier's OWN company_name (loaded from leads
// for this supplier_id) with the usual LLC / L.L.C / Trading / Contracting / Est suffix variants,
// email addresses, URLs and bare domains, and UAE phone numbers (+971, 00971, and 0 followed by
// 8-9 digits, which covers 05x mobiles and 02/03/04/06/07/09 landlines). Each hit becomes
// '[removed]' and the original string is collected into quotes.masked_terms - the same audit
// shape quote_extract already writes for the upload path, so both paths are reviewable the
// same way. It deliberately over-redacts: a false positive costs a line of scope text, a false
// negative costs the whole commission.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)';
const ID_PATTERNS: RegExp[] = [
  // A TRN or a licence number finds the company on a public register (founder, 14 Sep 2026). First,
  // so the phone patterns below cannot take a 15-digit TRN apart and leave its label behind.
  TRN_LABELLED, TRN_BARE, LICENCE_NO,
  /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g,
  /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi,
  /\b[A-Za-z0-9-]{2,}\.(?:ae|com|net|org|co|io|me|biz|info)(?:\.[A-Za-z]{2})?\b/gi,
  /\+\s?971[\s.-]?\d(?:[\s.-]?\d){6,10}/g,
  /\b00\s?971[\s.-]?\d(?:[\s.-]?\d){6,10}/g,
  /\b0\d(?:[\s.-]?\d){7,8}\b/g,
];
const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function companyRe(name: unknown): RegExp | null {
  const base = String(name || '').replace(new RegExp('\\b' + CO_SUFFIX, 'gi'), ' ').replace(/[^A-Za-z0-9؀-ۿ ]+/g, ' ').trim();
  const words = base.split(/\s+/).filter((w) => w.length > 1).map(rxEsc);
  if (!words.length || base.replace(/\s+/g, '').length < 3) return null;
  try { return new RegExp('\\b' + words.join('[\\s.,_-]*') + '(?:[\\s.,_-]*' + CO_SUFFIX + ')*', 'gi'); } catch (_e) { return null; }
}
function scrubIdentity(text: string | null, ownName: unknown, hits: string[]): string | null {
  if (text == null) return text;
  let out = String(text);
  const nameRe = companyRe(ownName);
  // Contact patterns run BEFORE the company-name pattern on purpose: "www.alnoor.ae" must be
  // taken out whole as a URL, otherwise the name pattern eats "alnoor" first and leaves a
  // half-redacted "www.[removed].ae" that still points at the supplier.
  for (const re of (nameRe ? [...ID_PATTERNS, nameRe] : ID_PATTERNS)) {
    out = out.replace(re, (m: string) => { const t = String(m).trim(); if (t.length < 3) return m; if (!hits.includes(t)) hits.push(t); return '[removed]'; });
  }
  return out;
}
// ANONYMITY FIX 27 Jul 2026 (customer -> supplier direction) ----------------------------------
// scrubIdentity above protects the SUPPLIER's identity in the text a supplier types. The same
// leak exists in the opposite direction and is worth more money: inbox serves the buyer's own
// free text (summary / spec / boq) to every matched supplier BEFORE the 3% reveal fee is paid.
// A brief reading "villa fit-out for Ahmed Khan, call 050 123 4567" hands the supplier
// everything the reveal fee is charged for, and the platform is cut out of its own transaction.
//
// inquiry_ai's prompt already tells the model not to put identity into summary/spec, but that is
// a soft control the customer can bypass entirely: customer_api's create_inquiry inserts a
// client-supplied summary/spec/raw_input, and edit_inquiry patches summary/spec/boq with no
// scrub at all. This is the deterministic server-side backstop for both paths.
//
// scrubDeep walks JSONB (spec, boq) and applies the EXISTING scrubIdentity to every string it
// finds, so emails, URLs, bare domains and UAE phone numbers are redacted by exactly the same
// patterns already trusted on the supplier side. Numbers are returned untouched, so BOQ
// quantities and prices are unaffected. `ownName` is the buyer's own full_name, which lets
// companyRe redact the buyer by name the same way it redacts a supplier by company name.
function scrubDeep(v: unknown, ownName: unknown, hits: string[]): unknown {
  if (typeof v === 'string') return scrubIdentity(v, ownName, hits);
  if (Array.isArray(v)) return v.map((x) => scrubDeep(x, ownName, hits));
  if (v && typeof v === 'object') { const o: Record<string, unknown> = {}; for (const k of Object.keys(v as Record<string, unknown>)) o[k] = scrubDeep((v as Record<string, unknown>)[k], ownName, hits); return o; }
  return v;
}
const numOrNull = (v: unknown) => { const n = Number(v); return isFinite(n) && n !== 0 ? n : (isFinite(n) && String(v).trim() !== '' ? n : null); };
async function secretVal(key: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return data?.value || null; }
function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
async function signedRedacted(path: string){ try { const { data } = await admin.storage.from('drawing-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
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
async function setRegistration(leadId: number) {
  await admin.from('leads').update({ portal_updated_at: new Date().toISOString() }).eq('id', leadId);
  const { data: st, error } = await admin.rpc('fn_supplier_registration_state', { p_lead_id: leadId });
  if (error || !(st as any)?.ok) return { status: 'unknown', fee_due: 0, may_quote: true, reason: 'registration_state_unavailable' };
  const s = st as any;
  return { status: String(s.status), fee_due: Number(s.fee_due || 0), may_quote: s.may_quote !== false, founding_rank: s.founding_rank ?? null, charging_starts: s.charging_starts ?? null, reason: String(s.reason || '') };
}
// profile_ai and supplier_review were deleted from the repository and from production by the
// 137-function sweep (182308b, 7 Sep 2026); on 14 Sep get_edge_function answers "Function not found".
// Their URL now returns a 404 JSON body, which aiReview returned AS IF it were a review — save_profile
// then wrote a blank ai_review_notes and "AI check: clean" into the registration mail. A non-2xx
// answer now means "no review", which is the truth. Both stay advisory and never gate registration.
//
// EMAIL PROOF (14 Sep 2026). login_otp records proof of e-mail ownership with an UPDATE on
// leads.claimed_by — but at sign-up no lead is claimed by that address yet (create_company or claim
// runs afterwards), so owner_email_verified stayed false for every self-registered and every invited
// supplier, and the e-mail item of the mandatory six could never be ticked. The durable proof is the
// used login OTP in email_verifications; it is read once when the company becomes this account's.
async function emailProven(email: string) {
  const { data } = await admin.from('email_verifications').select('id').eq('email', email).eq('purpose', 'login').not('used_at', 'is', null).limit(1);
  return !!(data && data.length);
}
async function aiSummarize(leadId: number) {
  try { const { data: lead } = await admin.from('leads').select('id,company_name,sector,emirate,services,products,description,certifications,verified,service_emirates').eq('id', leadId).maybeSingle(); if (!lead) return; const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return; const text = [lead.company_name && ('Company: ' + lead.company_name), lead.sector && ('Trade: ' + lead.sector), lead.services && ('Services: ' + lead.services), lead.products && ('Products: ' + lead.products), lead.description && ('About: ' + lead.description), lead.certifications && ('Certifications: ' + lead.certifications)].filter(Boolean).join('\n'); if (!text) return; const r = await fetch(`${SUPA_URL}/functions/v1/profile_ai`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, company_name: lead.company_name, sector: lead.sector, emirate: lead.emirate, text }) }); if (!r.ok) return; const jd = await r.json(); if (jd?.ok && jd.profile) { const p = jd.profile; const upd: Record<string, unknown> = {}; if (p.capability_summary) upd.capability_summary = p.capability_summary; if (Array.isArray(p.service_emirates) && p.service_emirates.length && !(Array.isArray(lead.service_emirates) && lead.service_emirates.length)) upd.service_emirates = p.service_emirates; if (p.description && !lead.description) upd.description = p.description; if (p.category && !lead.sector) upd.sector = p.category; if (Object.keys(upd).length) await admin.from('leads').update(upd).eq('id', leadId); } } catch (_e) { /* */ }
}
async function aiReview(lead: Record<string, unknown>) {
  try { const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return null; const profile: Record<string, unknown> = {}; for (const k of ['company_name','sector','emirate','service_emirates','contact_name','signatory_name','phone','services','products','description','trade_license_no','license_authority','license_expiry','trn','egr_number','bank_name','bank_account_name','bank_iban']) profile[k] = lead[k]; const r = await fetch(`${SUPA_URL}/functions/v1/supplier_review`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, profile }) }); if (!r.ok) return null; return await r.json(); } catch (_e) { return null; }
}
async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await admin.from('notifications').insert(rows); } catch (_e) { /* */ } }

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
// has an owner (ai_review_flags is REWRITTEN WHOLESALE by this function's own aiReview on every
// save, so anything parked there is lost within seconds; machinery / brands_carried /
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
// LICENCE GATE 29 Jul 2026. Unlike the services cross-check above, this one IS a gate: the
// supplier was NOT approved. The row exists so a human can see every held registration and why,
// on the same agent_actions surface, with the same shape (agent / kind / status / risk / title /
// recommendation / jsonb detail / target_table+target_id).
async function recordLicenceGate(supplierId: number, companyName: unknown, reason: string, evidence: Record<string, unknown>) {
  const missing = reason === 'no_licence';
  try {
    await admin.from('agent_actions').insert({
      agent: 'sales_engineer',
      kind: 'supplier_licence_gate',
      // TELEMETRY, NOT A TASK (2 Aug 2026, founder decision: no manual approval path). This row
      // used to be written as 'needs_review', which is precisely the human queue the founder asked
      // us to remove — and a queue nobody reads is worse than no queue, because it looks like a
      // safety net that is not there. It is now a counted refusal. Nobody is asked to do anything;
      // the supplier self-serves by re-uploading. Its only job is to make the cost of the decision
      // measurable: select detail->>'reason', count(*) from agent_actions
      // where kind='supplier_licence_gate' group by 1;
      status: 'logged',
      risk: missing ? 'high' : 'medium',
      title: 'Supplier refused automatically (' + (missing ? 'no trade licence on file' : 'trade licence expired') + ') — ' + String(companyName || ('supplier #' + supplierId)).slice(0, 120),
      recommendation: missing
        ? 'No action required. This supplier has no trade licence document or licence number on file, so registration was refused automatically and they were emailed and asked to upload one. Uploading a valid licence approves them with no human involvement. Recorded so the auto-refusal rate stays measurable.'
        : 'No action required. The trade licence expiry read from the uploaded document is in the past, so registration was refused automatically and they were emailed and asked to upload the renewal. Uploading an in-date licence approves them with no human involvement. Recorded so the auto-refusal rate stays measurable.',
      detail: { supplier_id: supplierId, reason, gate: 'licence_expiry', approved: false, approval_status: 'action_required', ...evidence, checked_at: new Date().toISOString(), source: 'supplier_api' },
      target_table: 'leads',
      target_id: String(supplierId),
    });
  } catch (_e) { /* the review row must never break the save - the gate itself already held approval */ }
}

Deno.serve(observe('supplier_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({})); const action = body.action;

    // claimed_by is the account e-mail. Registration SHOWS it with its verification state rather
    // than asking for it — the supplier signed in with it, so a field here could only ever be
    // answered with the value we already hold.
    if (action === 'me') { const { data } = await admin.from('leads').select('id,company_name,claimed_by,emirate,sector,business_role,products,services,description,certifications,company_type,company_size,founded_year,service_emirates,claimed,verified,approval_status,ai_review_notes,registration_submitted_at,accepted_terms_at,contact_name,signatory_name,phone,trade_license_no,license_authority,license_expiry,license_city,name_corrected_from,owner_email_verified,doc_extracted_at,trn,bank_name,bank_account_name,bank_iban,license_doc_path,iban_doc_path,egr_doc_path,egr_doc_name,egr_number,company_profile_doc_path,catalog_doc_paths,registration_status,registration_fee_due,registration_expires_at,app_rating,app_reviews,rating,reviews,licence_gate_reason,exception_due_at,wa_optin').eq('claimed_by', email).maybeSingle(); return J({ supplier: data || null }); }
    if (action === 'search') { const q = String(body.q || '').slice(0, 60); if (q.length < 2) return J({ results: [] }); const { data } = await admin.from('leads').select('id,company_name,emirate,business_role,claimed,claimed_by').ilike('company_name', '%' + q + '%').order('reviews', { ascending: false, nullsFirst: false }).limit(8); return J({ results: (data || []).map((r) => ({ ...r, claimable: !r.claimed || r.claimed_by === email })) }); }
    if (action === 'create_company') { const { data: existing } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (existing) return J({ error: 'Your account already manages a company.', code: 'company_exists' }, 409); const name = String(body.company_name || '').trim().slice(0, 160); if (name.length < 2) return J({ error: 'Enter your company name.', code: 'enter_company' }, 400); const { data: ins, error } = await admin.from('leads').insert({ company_name: name, emirate: body.emirate || null, sector: body.category || null, business_role: body.role || 'supplier', claimed: true, claimed_by: email, email, owner_email_verified: await emailProven(email), source: 'self_registered', locale: asLocale(body.lang), scraped_at: new Date().toISOString().slice(0, 10) }).select('id').maybeSingle(); if (error) return J({ error: error.message }, 500); const reg = await setRegistration(ins!.id); return J({ ok: true, id: ins?.id, registration: reg }); }
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
    if (action === 'claim') { const token = String(body.claim_token || body.token || body.t || '').trim(); if (!UUID_RE.test(token)) return J({ error: 'invalid_link', message: 'This claim link is not valid. Please use the link from your invitation, or contact management@quotesdone.com.' }, 400); const { data: row } = await admin.from('leads').select('id,claimed,claimed_by').eq('claim_token', token).maybeSingle(); if (!row) return J({ error: 'not found' }, 404); const id = Number(row.id); const askedId = Number(body.leads_id); if (body.leads_id != null && isFinite(askedId) && askedId !== id) return J({ error: 'invalid_link', message: 'This claim link does not match the company you selected. Please use the link from your invitation.' }, 400); if (row.claimed && row.claimed_by !== email) return J({ error: 'This company is already claimed by another account.' }, 409); const { data: existing } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (existing && existing.id !== id) return J({ error: 'Your account already manages another company.' }, 409); await admin.from('leads').update({ claimed: true, claimed_by: email, portal_updated_at: new Date().toISOString(), ...((await emailProven(email)) ? { owner_email_verified: true } : {}) }).eq('id', id); const reg = await setRegistration(id); return J({ ok: true, id, registration: reg }); }

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

    if (action === 'process_docs') {
      const { data: sup } = await admin.from('leads').select('id,company_name,services,products,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const secret = await secretVal('cred_fn_supplier_api');
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const out: Record<string, unknown> = {};
      const lic = body.license || {};
      // 14 Sep 2026 (sales_engineer): a path is recorded only when it is this supplier's own and
      // storage holds the object - otherwise the supplier sees success for a file that is not there
      // and the backup queues a document it can never copy.
      const own = async (p: unknown, folder: string) => { const s = String(p); return s.startsWith(`${folder}/${sup.id}/`) && !s.includes('..') && await storedAt(admin, 'supplier-docs', s); };
      const notStored = (what: string) => J({ error: 'document_not_found', message: `We could not find your ${what} in our records. Please upload it again.` }, 400);
      if (lic.path) { if (!(await own(lic.path, 'licenses'))) return notStored('trade licence'); upd.license_doc_path = String(lic.path); }
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
        if (up.error || !(await storedAt(admin, 'supplier-docs', p))) return J({ error: 'upload_failed', detail: up.error?.message || 'storage does not hold the object after upload', message: 'We could not store your trade licence. Please try again.' }, 502);
        upd.license_doc_path = p;
      }
      const licImgs = Array.isArray(lic.images) ? lic.images : [];
      if (licImgs.length || lic.file_b64) {
        try { const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, mode: 'license', images: licImgs, file_b64: lic.file_b64, mime: lic.mime, filename: lic.filename }) }); const jd = await r.json();
          if (jd?.ok && jd.doc) { const d = jd.doc;
            if (d.license_number) upd.trade_license_no = d.license_number;
            if (d.license_authority) upd.license_authority = d.license_authority;
            if (d.city) upd.license_city = d.city;
            if (d.expiry_date) upd.license_expiry = d.expiry_date;
            if (d.emirate) upd.emirate = d.emirate;
            if (d.trn) upd.trn = d.trn;
            upd.doc_extracted_at = new Date().toISOString();
            const legal = String(d.legal_name || '').trim(); const cur = String(sup.company_name || '').trim();
            if (legal && legal.toLowerCase() !== cur.toLowerCase()) { upd.name_corrected_from = cur; upd.company_name = legal; }
            out.license = { legal_name: legal, license_number: d.license_number, authority: d.license_authority, city: d.city, expiry: d.expiry_date, emirate: d.emirate, name_corrected: !!upd.name_corrected_from, confidence: d.confidence };
          } else out.license_error = jd?.error || 'extract_failed';
        } catch (e) { out.license_error = String((e as Error)?.message || e); }
      }
      const profImgs: any[] = [];
      // Extracted services for THIS run, kept aside so they can be cross-checked against the
      // supplier's own typed text once the row has been written (see the 29 Jul 2026 header).
      let xServices: string[] = [];
      const prof = body.company_profile || {};
      if (prof.path) { if (!(await own(prof.path, 'profiles'))) return notStored('company profile'); upd.company_profile_doc_path = String(prof.path); }
      // AUDIT 9.1. Company profile document - same treatment as the trade licence above.
      else if (prof.original_b64) {
        const sc = await sanitizeAndScan({ input: String(prof.original_b64), declaredMime: prof.mime, filename: prof.filename || 'profile', allow: SAFE_UPLOAD,
                                           scan: { source: 'supplier_api.company_profile', subject: String(sup.id), filename: prof.filename, bucket: 'supplier-docs' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'That company profile cannot be accepted. Please upload a PDF or an image (JPEG or PNG).' }, sc.status);
        const s = sc.result;
        const p = `profiles/${sup.id}/${Date.now()}_${safeFilename(prof.filename || 'profile', s.mime)}`;
        const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error || !(await storedAt(admin, 'supplier-docs', p))) return J({ error: 'upload_failed', detail: up.error?.message || 'storage does not hold the object after upload', message: 'We could not store your company profile. Please try again.' }, 502);
        upd.company_profile_doc_path = p;
      }
      if (Array.isArray(prof.images)) profImgs.push(...prof.images);
      const cats = Array.isArray(body.catalogs) ? body.catalogs.slice(0, 5) : []; const catPaths: string[] = [];
      // AUDIT 9.1. Catalogues. A rejected catalogue is refused outright rather than skipped,
      // because silently dropping one is how a supplier ends up believing a document is on file.
      for (const c of cats) {
        if (c?.path) { if (!(await own(c.path, 'catalogs'))) return notStored('catalogue'); catPaths.push(String(c.path)); }
        else if (c?.original_b64) {
          const sc = await sanitizeAndScan({ input: String(c.original_b64), declaredMime: c.mime, filename: c.filename || 'catalog', allow: SAFE_UPLOAD,
                                             scan: { source: 'supplier_api.catalog', subject: String(sup.id), filename: c.filename, bucket: 'supplier-docs' } });
          if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'One of your catalogue files cannot be accepted. Please upload PDFs or images (JPEG or PNG).' }, sc.status);
          const s = sc.result;
          const p = `catalogs/${sup.id}/${Date.now()}_${safeFilename(c.filename || 'catalog', s.mime)}`;
          const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
          if (up.error || !(await storedAt(admin, 'supplier-docs', p))) return J({ error: 'upload_failed', detail: up.error?.message || 'storage does not hold the object after upload', message: 'We could not store one of your catalogue files. Please try again.' }, 502);
          catPaths.push(p);
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
        try { const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, mode: 'profile', images: profImgs.slice(0, 10) }) }); const jd = await r.json();
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
      const { error: updErr } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (updErr) {
        console.error('process_docs: leads update failed —', updErr.message);
        return J({ error: 'save_failed', detail: updErr.message, message: 'We read your documents but could not save them to your profile. Please try again.' }, 502);
      }
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
    // These are deliberately NOT added to PROFILE_COLS. That list carries the bank IBAN, the
    // emirates ID, the trade licence number and the licence expiry — fields whose writes are what
    // the licence gate and the approval flow are built around. Letting a preferences screen post
    // into the same allowlist would mean a change of interface language travelled through the same
    // door as a change of bank account. Three columns, named here, and nothing else is settable.
    if (action === 'save_settings') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      if (body.locale !== undefined) {
        const loc = String(body.locale);
        if (!['en', 'ar'].includes(loc)) return J({ error: 'locale must be en or ar' }, 400);
        upd.locale = loc;
      }
      if (body.wa_optin !== undefined) upd.wa_optin = !!body.wa_optin;
      if (body.email_shared !== undefined) upd.email_shared = !!body.email_shared;
      const { error } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, saved: Object.keys(upd).filter((k) => k !== 'portal_updated_at') });
    }

    if (action === 'settings') {
      const { data: sup } = await admin.from('leads')
        .select('id,company_name,locale,wa_optin,email_shared,claimed_by,phone,approval_status,registration_status,owner_email_verified,owner_phone_verified,accepted_terms_at,accepted_terms_version,license_expiry')
        .eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      return J({ ok: true, settings: sup });
    }

    if (action === 'save_profile') {
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,approval_status,registration_submitted_at,verified,license_doc_path,license_expiry,trade_license_no,owner_phone_verified,owner_email_verified,company_profile_doc_path,accepted_terms_at').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const { data: pc } = await admin.from('pricing_config').select('auto_approve_suppliers').eq('id', 1).maybeSingle(); const autoApprove = !!pc?.auto_approve_suppliers;
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      for (const c of PROFILE_COLS) if (body[c] !== undefined) upd[c] = body[c];
      if (Array.isArray(body.service_emirates)) upd.service_emirates = body.service_emirates;
      // DOCUMENTS LEAD + DOUBLE CONFIRMATION (spec, 29 Jul 2026). PROFILE_COLS contains
      // 'services', so the typed box wrote straight over whatever the documents produced -
      // extraction would win at upload time and then be silently reverted by the next save. The
      // typed text is for CONFIRMATION, not authorship: once an extraction exists it keeps the
      // canonical field and the typed text is stored as the declared value and cross-checked
      // instead. With no extraction on file the supplier's text is still the only source we have,
      // so it is written through unchanged.
      let servicesCheck: Record<string, unknown> | null = null;
      if (upd.services !== undefined) {
        const prior = await priorCrossCheck(sup.id);
        if (prior.extracted.length) {
          const declared = clip(upd.services, 2000);
          upd.services = prior.extracted.join(', ');
          const cc = await recordServicesCrossCheck(sup.id, sup.company_name, prior.extracted, declared);
          servicesCheck = { verdict: cc.verdict, overlap: Math.round(cc.overlap * 100) / 100, note: cc.note, extracted_services: prior.extracted, declared_services: declared };
        }
      }
      // EVIDENCE FIX 27 Jul 2026. The version recorded as legally accepted was whatever the
      // browser posted in body.terms_version. The record this writes is the platform's dispute
      // evidence for the 3% non-response fine (see the file header) - letting the accepting party
      // choose which version of the agreement is on file makes it evidence of nothing, and a
      // supplier could pin themselves to an old or invented version by editing one JSON field.
      // The current version is now read server-side from app_secrets('terms_version'); the key is
      // not set today, so the existing 'v2' default still applies until it is.
      // SPF5 (14 Sep 2026): a version label does not prove which words were on screen, so the SHA-256
      // of the exact agreement text is stored beside it. It is recomputed here from the text itself
      // (not trusted from the generated constant) and written only while the live terms_version is the
      // version that text was exported for; otherwise null, never a hash of the wrong agreement.
      if (body.accept_terms) { const tv = String((await secretVal('terms_version')) || 'v2').trim().slice(0, 20) || 'v2'; upd.accepted_terms_at = new Date().toISOString(); upd.accepted_terms_version = tv; upd.accepted_terms_ip = clientIp(req) || null; upd.accepted_terms_sha256 = tv === SUPPLIER_AGREEMENT_VERSION ? await agreementSha256() : null; if (tv !== SUPPLIER_AGREEMENT_VERSION) console.error(`supplier_api: terms_version ${tv} has no exported agreement text (module is ${SUPPLIER_AGREEMENT_VERSION}); hash not stored`); }
      // THE MANDATORY SIX, ENFORCED WHERE REGISTRATION IS SUBMITTED (14 Sep 2026). Until now this
      // action checked the licence alone while the portal demanded a company profile and the
      // Documents tab said only the licence was required. The one definition lives in
      // _shared/supplier_registration.ts; the row as it will be after this save is what is tested, so
      // a supplier who accepts the terms and saves in one go is not refused for the terms.
      // An ALREADY-APPROVED company editing its profile is not refused: the approval fix above says
      // this path may never take an approval away, and refusing the save would do exactly that to
      // their ability to correct a typo. (0 suppliers are claimed on production, 14 Sep, so no live
      // account sits in that branch today.)
      if (String(sup.approval_status || '') !== 'approved') {
        const missing = registrationMissing({ ...sup, ...upd } as Record<string, unknown>);
        if (missing.length) return J({ error: 'missing_required', code: 'missing_required', params: { missing }, message: 'Still needed to register: ' + missing.join(', ') + '.' }, 400);
      }
      // APPROVAL FIX 27 Jul 2026. `else if (!sup.verified)` demoted an ALREADY-APPROVED supplier
      // back to 'pending' every time they saved their profile, because os_ops approves by setting
      // approval_status only and never touches leads.verified. The supplier silently lost the
      // ability to submit quotes (submit_quote requires approval_status === 'approved') and an
      // admin's decision was reverted by an unrelated edit. Approval is only ever revoked
      // deliberately by an admin now - this path can put a supplier INTO pending, never back.
      //
      // AUTOMATION 29 Jul 2026 (spec: "everything is fully automated... no manual approval
      // steps"): pricing_config.auto_approve_suppliers is now TRUE, so the first branch is the
      // live one and every registration is approved and verified on save instead of halting at
      // 'pending'. Be honest about what that does and does not check: this branch applies NO
      // licence-validity, document-presence or banned test - none has ever existed on this path,
      // before or after the change, so nothing automated is being bypassed; what is removed is the
      // human licence check that 'pending' used to force. The checks that DO survive live
      // elsewhere and are untouched: match_suppliers_kw still excludes banned, matching_blocked,
      // permanently_closed and 'rejected' suppliers, submit_quote still requires accepted terms
      // and a settled registration fee, and aiReview below still writes its findings to
      // ai_review_notes / ai_review_flags and still emails management on first submission -
      // advisory only, it has never gated anything. An automated licence-expiry gate belongs HERE.
      //
      // LICENCE-EXPIRY GATE 29 Jul 2026 — this is the "belongs HERE" above, now implemented.
      // Auto-approval is fully automated, so the licence check the human 'pending' queue used to
      // force is made automatically from what license_extract has ALREADY written to leads:
      //   leads.license_doc_path  - the stored trade licence document (set on upload)
      //   leads.trade_license_no  - the licence number read off it
      //   leads.license_expiry    - the expiry date read off it (date, YYYY-MM-DD), left NULL
      //                             when the document printed none (license_extract never guesses)
      // Values being saved in THIS request win over what is on the row, so a supplier who uploads
      // a valid licence and saves in one go is approved on that licence, not on the stale row.
      //
      // An extracted-but-absent expiry is deliberately NOT a failure: license_extract returns null
      // rather than inventing a date, and blocking on that would suspend suppliers whose licence
      // genuinely prints no expiry. The gate is "present, and not known to be expired".
      const licPath = String((upd.license_doc_path ?? sup.license_doc_path) || '').trim();
      const licNo = String((upd.trade_license_no ?? sup.trade_license_no) || '').trim();
      const licExpiryVal = (upd.license_expiry ?? sup.license_expiry) ?? null;
      const licExpiry = licExpiryVal ? String(licExpiryVal).slice(0, 10) : '';
      const todayIso = new Date().toISOString().slice(0, 10);
      const licencePresent = !!licPath || !!licNo;
      const licenceExpired = !!licExpiry && licExpiry < todayIso;
      const licenceOk = licencePresent && !licenceExpired;
      const licenceReason = !licencePresent ? 'no_licence' : (licenceExpired ? 'licence_expired' : 'ok');
      // NO MANUAL APPROVAL PATH (2 Aug 2026, founder decision on the external review's §1).
      // The code used to contain two contradictory ideas: auto-approve when the licence reads, and
      // an implicit human queue ('pending') when it does not. The founder chose fully automatic,
      // no human path. So a failed licence gate is now a REFUSAL WITH A REASON the supplier can
      // act on immediately, not a ticket parked on someone's desk:
      //   * approval_status goes to 'action_required', not 'pending' — 'pending' reads as "we are
      //     looking at it", which is a promise nobody is going to keep.
      //   * licence_gate_reason is stored so the portal and the email can name the exact problem.
      //   * re-saving the profile re-runs this gate, so the supplier self-serves an approval the
      //     moment they upload a readable, in-date licence. No queue, no waiting, no human.
      // THE RISK THE FOUNDER ACCEPTED, stated plainly: a genuine supplier with a bad scan or an
      // unusual licence layout is now refused with no exception route, and would never be seen.
      // That is invisible unless it is counted, so every refusal is still recorded (as telemetry,
      // status 'logged' — NOT 'needs_review', which would recreate the queue we just removed).
      // Watch it: select count(*) from agent_actions where kind='supplier_licence_gate'.
      // If that number climbs against real registrations, the decision needs revisiting.
      const autoApproved = autoApprove && licenceOk;
      const firstSubmit = !sup.registration_submitted_at;
      if (autoApproved) { upd.approval_status = 'approved'; upd.verified = true; upd.licence_gate_reason = null; }
      else if (String(sup.approval_status || '') !== 'approved' && !sup.verified) { upd.approval_status = autoApprove ? 'action_required' : 'pending'; upd.licence_gate_reason = autoApprove ? licenceReason : null; }
      if (firstSubmit) upd.registration_submitted_at = new Date().toISOString();
      // 5 Aug 2026. Same discarded-result defect as process_docs, and worse here: the three lines
      // above put approval_status, verified and licence_gate_reason into `upd`, so this write IS
      // the approval decision. Discarding its result meant a supplier who should have been approved
      // could be left unapproved with the failure recorded nowhere — and the exception window below
      // would then open a 14-day clock against a state that was never persisted.
      const { error: updErr } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (updErr) {
        console.error('save_profile: leads update failed —', updErr.message);
        return J({ error: 'save_failed', code: 'save_failed', detail: updErr.message, message: 'We could not save your profile. Please try again.' }, 502);
      }
      // EXCEPTION WINDOW (2 Aug 2026, Phase 1.3). 'action_required' with no deadline is not
      // automation, it is a queue with the label removed: the account sits there forever, holding a
      // company name and an email, and neither the supplier nor the founder can tell whether it is
      // alive. Opening the exception starts a 14-day clock with reminders at day 3, 7 and 12 and an
      // automatic, reasoned rejection at the end. Re-opening does NOT restart the clock - otherwise
      // a supplier could extend their own deadline forever by re-saving the same bad scan.
      // Approval closes it; nothing here approves anybody.
      if (autoApprove && !licenceOk) {
        await recordLicenceGate(sup.id, sup.company_name, licenceReason, { license_doc_path: licPath || null, trade_license_no: licNo || null, license_expiry: licExpiry || null, checked_on: todayIso });
        try { await admin.rpc('fn_supplier_exception_open', { p_lead_id: sup.id, p_reason: licenceReason }); } catch (_e) { /* the gate already held approval; the window is bookkeeping */ }
      } else if (autoApproved) {
        try { await admin.rpc('fn_supplier_exception_close', { p_lead_id: sup.id, p_outcome: 'resolved' }); } catch (_e) { /* */ }
      }
      await aiSummarize(sup.id);
      const { data: full } = await admin.from('leads').select('*').eq('id', sup.id).maybeSingle();
      const review = await aiReview(full || {});
      if (review) { const notes = (review.summary || '') + (Array.isArray(review.issues) && review.issues.length ? '  Issues: ' + review.issues.map((i: { field: string; note: string }) => `${i.field} — ${i.note}`).join('; ') : ''); await admin.from('leads').update({ ai_review_notes: notes.slice(0, 2000), ai_review_flags: review.issues || [], ai_reviewed_at: new Date().toISOString() }).eq('id', sup.id); }
      if (firstSubmit) { const mgmt = (await secretVal('admin_emails') || 'management@quotesdone.com').split(',')[0].trim(); const revLine = review ? ` AI check: ${review.severity || 'clean'} — ${review.summary || ''}` : ''; const lic = full?.name_corrected_from ? ` Licence name corrected from \"${full.name_corrected_from}\" to \"${full.company_name}\".` : ''; const licInfo = full?.trade_license_no ? ` Licence ${full.trade_license_no}${full.license_city ? ', ' + full.license_city : ''}${full.license_expiry ? ', expires ' + full.license_expiry : ''}.` : ''; // NOTIFICATION HONESTY 2 Aug 2026 (external code review). This email was hardcoded to
      // 'review needed / pending your approval' even on the path that had just AUTO-APPROVED the
      // supplier a few lines above. Two costs: the founder is trained to ignore an inbox of
      // 'action required' mails that need no action, and the one case that DOES need a human —
      // the licence gate failing — is indistinguishable from the all-clear case. The subject and
      // body now state what actually happened, and only the blocked case asks for anything.
      await notify([ { type: 'supplier_registered', to_email: mgmt, to_role: 'admin', lead_id: sup.id, subject: autoApproved ? 'New supplier auto-approved' : `Supplier refused automatically — ${licenceReason || 'licence check failed'}`, body: `New supplier \"${full?.company_name || sup.company_name}\"${full?.emirate ? ' (' + full.emirate + ')' : ''} has registered and was ${autoApproved ? 'APPROVED AUTOMATICALLY (licence present and in date). No action needed — this is a record.' : `REFUSED AUTOMATICALLY: ${licenceReason || 'the trade licence could not be verified'}. No action needed — there is no approval queue. They have been emailed the exact problem and are approved the moment they upload a readable, in-date licence. This mail exists so the auto-refusal rate stays visible; if you start seeing genuine businesses here, the fully-automatic policy needs revisiting.`}${licInfo}${lic}${revLine}` }, { type: 'registration_received', to_email: email, to_role: 'supplier', lead_id: sup.id, subject: autoApproved ? 'Your QuotesDone supplier account is active' : 'Thanks for registering with QuotesDone', body: autoApproved ? `Your account for ${sup.company_name} is active — you can now receive inquiries and submit quotes.` : `Thank you for registering ${full?.company_name || sup.company_name} with QuotesDone.\n\nYour account is not active yet for one reason: ${licenceReason || 'we could not read a valid, in-date trade licence from what you uploaded'}.\n\nPlease sign in to your supplier portal and upload a clear copy of your current trade licence (all pages, in date). Your account activates automatically as soon as we can read it — there is no waiting list and no manual approval queue, so nobody has to get to you.\n\nPlease do this within 14 days. If we have not received a readable licence by then this registration closes automatically, and you are welcome to start again at any time.\n\nTips if it keeps failing: photograph or scan the whole page (not a crop), make sure the text is sharp enough to read on screen, and check the expiry date has not passed. If you have tried this and still see the same message, reply to this email.` } ]); }
      const { data: me } = await admin.from('leads').select('approval_status').eq('id', sup.id).maybeSingle();
      return J({ ok: true, approval_status: me?.approval_status || 'pending', services_crosscheck: servicesCheck, review: review ? { severity: review.severity, summary: review.summary, issues: review.issues } : null });
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
      const { data: matches } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sup.id); const ids = (matches || []).map((m) => m.inquiry_id);
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
      const { data: myq } = await admin.from('quotes').select('id,inquiry_id,option_no,quote_amount,price_ex_vat,vat_treatment,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,source,original_file_name,submittable').eq('supplier_id', sup.id).in('inquiry_id', ids);
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
      { const { data: owners, error: eOwners } = await admin.from('inquiries').select('id,customer_id,project_id').in('id', ids);
        if (eOwners) ownerResolved = false;
        else for (const o of (owners || [])) { if (o?.customer_id) ownerOf[String(o.id)] = String(o.customer_id); if (o?.project_id) projectOf[String(o.id)] = String(o.project_id); } }
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
      const out: any[] = [];
      for (const i of (inq || [])) {
        const pages: string[] = [];
        for (const p of (Array.isArray(i.drawing_redacted_paths) ? i.drawing_redacted_paths : [])) { const u = await signedRedacted(String(p)); if (u) pages.push(u); }
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
        const sSummary = revealed ? i.summary : (ownerResolved ? (redactText(String(scrubIdentity(i.summary ?? null, buyerName, hits) ?? ''), seeds).text || null) : null);
        const sSpec = revealed ? i.spec : (ownerResolved ? scrubDeep(i.spec, buyerName, hits) : null);
        // THE LAST GATE before a supplier sees a BOQ. redactBoq removes the buyer's seed terms and the
        // generic identifiers, then residual-scans; anything still identifying HOLDS the BOQ (null,
        // boq_withheld:true). It never fails open: a BOQ we cannot prove clean is not shown.
        let boqWithheld = false;
        const sBoq = revealed ? i.boq : (ownerResolved ? (() => {
          if (!i.boq) return null;
          const r = redactBoq(scrubDeep(i.boq, buyerName, hits) as any, seeds);
          boqWithheld = r.held;
          return r.held ? null : r.boq;
        })() : null);
        // ANONYMITY FIX 29 Jul 2026. budget is an 80-char FREE-TEXT box, not a number ("around
        // 250k, call Ahmad on 050 123 4567"), and it was the one customer-authored field on this
        // response still emitted verbatim while summary / spec / boq were scrubbed. It now goes
        // through the same scrubIdentity as summary, behind the same reveal gate.
        const sBudget = revealed ? i.budget : (ownerResolved ? scrubIdentity(i.budget ?? null, buyerName, hits) : null);
        out.push({ id: i.id, category: i.category, emirate: i.emirate, summary: sSummary, spec: sSpec, created_at: i.created_at, budget: sBudget || null, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: sBoq || null, boq_withheld: boqWithheld, boq_confidence: i.boq_confidence || null, drawing_file_name: null, drawing_file_url: null, drawing_pages: pages, status: i.status, concluded, you_won: youWon, revealed, quote: optsOf(i.id)[0] || null, quotes: optsOf(i.id) });
      }
      return J({ inquiries: out, approval_status: sup.approval_status });
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
      const inquiry_id = body.inquiry_id;
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
        if (up.error) return J({ error: 'upload_failed', detail: up.error.message, message: 'We could not store your quotation file. Please try again.' }, 502);
      }
      const { data: inq } = await admin.from('inquiries').select('category,summary').eq('id', inquiry_id).maybeSingle();
      const secret = await secretVal('cred_fn_supplier_api');
      let jd: any = {};
      try { const r = await fetch(`${SUPA_URL}/functions/v1/quote_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, images, inquiry: inq || {}, ...(orig.b64 ? { file_b64: String(orig.b64), mime: String(orig.mime || ''), filename: String(orig.filename || 'quotation') } : {}), supplier_terms: [String((sup as any).company_name || '')].filter(Boolean) }) }); jd = await r.json(); } catch (e) { return J({ error: 'Reading failed, please try again or fill the form.', code: 'quote_read_failed', detail: String((e as Error)?.message || e) }, 502); }
      // Under the OpenRouter hold quote_extract has no model to call, so this is the expected path:
      // the code tells the portal to say "fill in the form", which is a complete way to quote.
      if (!jd?.ok) return J({ error: jd?.error || 'Could not read the quotation. Please fill the form instead.', code: 'quote_read_failed', detail: jd?.detail || null }, 502);
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
      const { data: inqRow } = await admin.from('inquiries').select('category,spec').eq('id', q.inquiry_id).maybeSingle();
      const { count: optCount } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('inquiry_id', q.inquiry_id).eq('supplier_id', sup.id);
      // deno-lint-ignore no-explicit-any
      const spec: any = inqRow?.spec;
      const ctx = { category: inqRow?.category ?? null, requirements: requirementsOf(spec), ref: String(q.inquiry_id).slice(0, 8).toUpperCase(), multiOption: (optCount || 0) > 1 };
      const signed = async (b?: string | null, p?: string | null) => { if (!b || !p) return null; try { const { data } = await admin.storage.from(b).createSignedUrl(p, 3600); return data?.signedUrl || null; } catch (_e) { return null; } };
      if (action === 'spec_hold') {
        const { data: hs } = await admin.from('quote_spec_hold').select('id,state,missing,note_en,note_ar,regenerated,regenerated_at,pdf_bucket,pdf_path,opened_at,approved_at,released_at').eq('quote_id', qid).order('id', { ascending: false }).limit(1);
        const hold = hs?.[0] || null;
        const lines = await repo.lines(qid);
        const a = assessQuote({ category: ctx.category, lines, terms: q, requirements: ctx.requirements });
        return J({ ok: true, quote_id: qid, option_no: q.option_no, hold: hold ? { ...hold, pdf_url: await signed(hold.pdf_bucket, hold.pdf_path) } : null, schema: formSchema(a, lines) });
      }
      if (action === 'spec_fill') {
        // The regenerated quotation is drawn by pdf_native, the existing quote renderer, both languages.
        const render: Render = async (rec) => {
          const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return null;
          const r = await fetch(`${SUPA_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, ...pdfBody(rec, 'Supplier'), bucket: 'quote-files', folder: `quotes/${sup.id}/${q.inquiry_id}/regenerated`, name: `quotation_${String(rec.quote_id).slice(0, 8)}_option${rec.option_no}` }) });
          const j = await r.json().catch(() => null);
          return j?.ok ? { bucket: String(j.bucket), path: String(j.path) } : null;
        };
        const out = await fillIn(repo, qid, supplierOf(sup, email), body.values && typeof body.values === 'object' ? body.values : {}, ctx, render);
        if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 400);
        if (out.complete) return J({ ...out, pdf_url: await signed(out.pdf?.bucket, out.pdf?.path) });
        return J(out);
      }
      const out = await approve(repo, qid, supplierOf(sup, email), email, body.confirm, ctx, async (row) => (await acceptLive(String(row.id), String(row.inquiry_id), true)).accepted);
      if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 409);
      return J(out);
    }
    if (action === 'submit_quote') {
      const { data: sup } = await admin.from('leads').select('id,company_name,locale,whatsapp,phone,accepted_terms_at,registration_status,approval_status,licence_gate_reason,rejection_reason').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
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
        if (reg.may_quote === false) return J({ error: 'Your ' + String(reg.currency || 'AED') + ' ' + Number(reg.fee_due || 0) + ' yearly registration is due. Please complete registration to send quotes.', code: 'registration_due', params: { fee: Number(reg.fee_due || 0), currency: String(reg.currency || 'AED') }, registration: { status: reg.status, fee_due: reg.fee_due, currency: reg.currency, reason: reg.reason } }, 402);
      }
      const { data: inqStat } = await admin.from('inquiries').select('status').eq('id', body.inquiry_id).maybeSingle();
      if (inqStat && CONCLUDED.includes(String(inqStat.status))) return J({ error: 'This request has been concluded — the customer has already selected a supplier. Thank you for your interest, and best of luck on the next one.', code: 'inquiry_concluded' }, 409);
      const amt = Number(body.amount); if (!(amt > 0)) return J({ error: 'invalid amount', code: 'invalid_amount' }, 400);
      const isUpload = body.source === 'upload';
      const items = Array.isArray(body.items) ? body.items : [];
      // Free text the supplier typed. On the FORM path it goes through scrubIdentity (see the
      // helper's note, 27 Jul 2026) before it is ever stored, because these four columns are read
      // straight back out to the buyer pre-payment. The UPLOAD path is left as-is: quote_extract
      // already anonymised it and supplies its own masked_terms, so scrubbing twice would only
      // mangle text a model has already cleaned.
      const maskHits: string[] = [];
      const scrub = (v: unknown, n: number) => isUpload ? clip(v, n) : scrubIdentity(clip(v, n), sup.company_name, maskHits);
      const sNotes = scrub(body.notes, 1000), sScope = scrub(body.scope, 2000), sCond = scrub(body.conditions, 2000), sExcl = scrub(body.exclusions, 2000);
      const priorMasked: string[] = Array.isArray(body.masked_terms) ? body.masked_terms.map((x: unknown) => String(x)) : [];
      const allMasked = [...priorMasked, ...maskHits.filter((h) => !priorMasked.includes(h))];
      const { data: inqRow } = await admin.from('inquiries').select('category,spec').eq('id', body.inquiry_id).maybeSingle();
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
      const { data: mine } = await admin.from('quotes').select('id,option_no,status').eq('inquiry_id', body.inquiry_id).eq('supplier_id', sup.id);
      const maxOpt = Math.max(0, ...(mine || []).map((r: any) => Number(r.option_no) || 1));
      const single = Number(body.option_no) >= 1 ? Math.floor(Number(body.option_no)) : (body.new_option === true ? maxOpt + 1 : 1);
      const plan = multi ? opts.map((o) => ({ option_no: o.option_no, lines: o.lines, amount: optionAmount(o) })) : [{ option_no: single, lines: opts[0]?.lines ?? normItems, amount: amt as number | null }];
      if (plan.some((p) => p.option_no > 20)) return J({ error: 'A quote can carry at most 20 options.', code: 'too_many_options' }, 400);
      const noTotal = plan.find((p) => !(Number(p.amount) > 0));
      if (noTotal) return J({ error: 'Enter the total for option ' + noTotal.option_no + '.', code: 'option_total_missing', params: { option: noTotal.option_no } }, 400);
      const submission_id = crypto.randomUUID();
      const repo = supabaseRepo(admin, { dispatch: kickDelivery });
      const supplier = supplierOf(sup, email);
      const ref = String(body.inquiry_id).slice(0, 8).toUpperCase();
      const multiOption = multi || single > 1 || (mine || []).length > 1;
      const results: any[] = [];
      let anyAccepted = false;
      for (const p of plan) {
        const vat = readVat({ amount: p.amount, subtotal: multi ? null : numOrNull(body.subtotal), vat_amount: multi ? null : numOrNull(body.vat_amount), text: vatText,
          stated: body.vat_treatment ? String(body.vat_treatment) : null, price_ex_vat: multi ? null : numOrNull(body.price_ex_vat) });
        const det = { inquiry_id: body.inquiry_id, supplier_id: sup.id, option_no: p.option_no, submission_id, quote_amount: vat.price_ex_vat ?? p.amount, price_ex_vat: vat.price_ex_vat, vat_treatment: vat.treatment, vat_amount: vat.vat_amount, supplier_trn: trn, amount_as_stated: p.amount,
          notes: sNotes, lead_time: clip(body.lead_time, 200), validity: clip(body.validity, 200), payment_terms: clip(body.payment_terms, 400), warranty: clip(body.warranty, 200), scope: sScope, conditions: sCond, exclusions: sExcl, source: isUpload ? 'upload' : 'form', anonymized: true, original_file_path: body.original_file_path || null, original_file_name: body.original_file_name || null, masked_terms: allMasked.length ? allMasked : null, structured: p.lines.length > 0 };
        // Capture the status BEFORE the write. A new row is created as a draft, never in the
        // 'submitted' column default: a dry_run preflight or a held quote must not be visible to the
        // customer even for a moment (caught by a demo walkthrough on 21 Jul 2026).
        const prior = (mine || []).find((r: any) => (Number(r.option_no) || 1) === p.option_no) || null;
        let qid: string;
        if (prior) { const { error } = await admin.from('quotes').update(det).eq('id', prior.id); if (error) return J({ error: error.message }, 500); qid = String(prior.id); }
        else { const { data: ins, error } = await admin.from('quotes').insert({ ...det, status: 'draft' }).select('id').single(); if (error) return J({ error: error.message }, 500); qid = String(ins.id); }
        try {
          await admin.from('quote_items').delete().eq('quote_id', qid);
          const rows = p.lines.slice(0, 80).map((it: any, i: number) => ({ quote_id: qid, line_no: i + 1, description: clip(it.description, 300), brand: clip(it.brand, 120), model: clip(it.model, 120), specification: clip(it.specification, 800), qty: numOrNull(it.qty), unit: clip(it.unit, 40), unit_price: numOrNull(it.unit_price), labour: numOrNull(it.labour), install: numOrNull(it.install), commissioning: numOrNull(it.commissioning), amount: numOrNull(it.amount) ?? ((numOrNull(it.qty) || 0) * (numOrNull(it.unit_price) || 0) || null), country_of_origin: clip(it.country_of_origin, 80), notes: clip(it.notes, 300) }));
          // A line item with no description is dropped, not stored blank - a quote line the buyer
          // cannot read is worse than one that is absent.
          const clean = rows.filter((r: { description: string | null }) => r.description);
          if (clean.length) await admin.from('quote_items').insert(clean);
        } catch (_e) { /* */ }
        // Preflight (dry_run). Runs the real scorer, the real accept rule and the real hold gate's
        // assessment, then stops: the status is put back as it was, nothing is notified, no hold opens.
        if (body.dry_run === true) {
          const acc = await acceptRule(qid);
          const a = assessQuote({ category, lines: await repo.lines(qid), terms: (await repo.quote(qid))!, requirements });
          try { await admin.from('quotes').update({ status: prior?.status || 'draft' }).eq('id', qid); } catch (_e) { /* */ }
          results.push({ quote_id: qid, option_no: p.option_no, dry_run: true, submittable: acc.submittable, would_accept: acc.accept && !a.held, status_after: prior?.status || 'draft',
            accept_via: acc.submittable ? 'structured_score' : (acc.formComplete ? 'form_complete' : (!acc.requireStructured ? 'structured_not_required' : null)),
            require_structured: acc.requireStructured, priced_items: acc.priced, total_items: p.lines.length, score: acc.score, spec_missing: a.missing, would_hold: a.held });
          continue;
        }
        // THE HOLD GATE (founder, 14 Sep 2026). The sales engineer holds a quote that does not state
        // every required detail exactly, records which line and which detail, and tells the supplier.
        const g = await gate(repo, qid, supplier, { category, requirements, ref, multiOption });
        if (g.held) { results.push({ quote_id: qid, option_no: p.option_no, accepted: false, held: true, missing: g.missing, code: 'spec_hold' }); continue; }
        const live = await acceptLive(qid, String(body.inquiry_id), false);
        if (live.accepted) anyAccepted = true;
        results.push({ quote_id: qid, option_no: p.option_no, held: false, ...live });
      }
      if (anyAccepted) await notifyNewQuote(String(body.inquiry_id));
      if (multi) return J({ ok: true, options: results, submission_id, accepted: results.some((r) => r.accepted), held: results.some((r) => r.held), dry_run: body.dry_run === true, code: 'options_split', params: { count: results.length } });
      const r0 = results[0];
      const q = { id: r0.quote_id, option_no: r0.option_no, status: r0.accepted ? 'submitted' : 'draft' };
      if (body.dry_run === true) return J({ ok: true, ...r0 });
      if (r0.held) return J({ ok: true, quote: q, accepted: false, held: true, missing: r0.missing, code: 'spec_hold', message: 'Your quote is on hold until the exact details listed are stated. Fill them in here or upload a revised quote.' });
      if (r0.accepted) return J({ ok: true, quote: q, submittable: r0.submittable, accepted: true, coaching: r0.coaching, score: r0.score });
      return J({ ok: true, quote: q, submittable: false, accepted: false, coaching: r0.coaching, score: r0.score, code: 'draft_saved', message: 'Your quote was saved as a draft. Add the missing details so we can send it to the customer.' });
    }
    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String(e) }, 500);
  }
}));
