import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD, SAFE_CAD, SAFE_SHEET, SAFE_DOCS } from '../_shared/attachment.ts';
import { seedTerms, redactBoq, titleBlockBoxes } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
import { cadSupplierBoq, dxfTextOf } from '../_shared/cad_identity.ts';
import { postedSingle, postedSplit } from '../_shared/inquiry_posted.ts';
import { parseRatingInput } from './rating_input.ts';
import { cadNote, drawingHandoff, heldRun } from './drawing_hold.ts';
import { splitInquiry } from '../_shared/inquiry_split.ts';
import { KW, detect } from './keywords.ts';
import { openLines, settleLines, type BoqCheck } from '../_shared/boq_open_lines.ts';
import { asLocale, documentLocale } from '../_shared/registered_locale.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { LENGTHS_FAILED_NOTE, LENGTHS_QUEUED_NOTE } from '../drawing_boq/length_notes.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. A customer drawing is stored AND handed to a
// supplier to quote from, so a malicious file here would be forwarded by us, under our name.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { storedAt } from '../_shared/stored_at.ts';
import { quoteDocument, compareDocument, compareTable, completenessOf, itemsOfRows, toCsv, clipCell, quoteRef, jobNoOf, isCurrentDoc, arCategory, arEmirate, enCategory, type Item } from '../_shared/quote_documents.ts';
import { labelQuotes } from '../_shared/quote_labels.ts';
import { accountMissing } from '../_shared/account_rule.ts';
import { applyEdits, validateStored, supplierLine } from '../_shared/intake_requirements.ts';
import { portalLink } from '../_shared/site_origins.ts';
import { revealCharge } from '../_shared/reveal_fee.ts';
import { requestDelivery } from '../_shared/deliver.ts';
import { acceptedMessage, apologyMessage, type OfferForText } from '../_shared/line_specs/no_exact_spec.ts';
import { SANCTIONED_REFUSAL, sanctionedLead, sanctionedLeads } from '../_shared/sanctioned.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const INQUIRY_LIMIT_PER_HOUR = 20;
const PDF_LIMIT_PER_HOUR = 40;
// Anonymised quote labels must stay alphabetic beyond 26 quotes. String.fromCharCode(65 + i)
// emits '[', '\\', ']' from the 27th, so a customer with 30 quotes saw "Supplier [" and the
// comparison report referenced a label that did not exist in their list.
function supplierLabel(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }
async function signedFile(path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from('quote-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
async function signedDrawing(path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from('drawing-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
async function signedDoc(bucket: string | null | undefined, path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from(bucket || 'agent-docs').createSignedUrl(path, 7 * 24 * 3600); return data?.signedUrl || null; } catch { return null; } }
async function getSecret(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function b64ToBytes(b64: string): Uint8Array { const raw = atob(String(b64).replace(/^data:[^;]+;base64,/, '')); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i); return arr; }

// KW and detect() live in ./keywords.ts (21 Sep 2026) — see its header for the create_inquiry 500.
// The portal's drawing OCR (ocrPlan lines with page boxes, the sheet width, the symbol counts),
// passed through to drawing_boq, which validates every field. Bounded here only by size.
function drawingOcr(body: any): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (Array.isArray(body?.ocr_lines)) out.ocr_lines = body.ocr_lines.slice(0, 4000);
  if (Number.isFinite(Number(body?.ocr_width))) out.ocr_width = Number(body.ocr_width);
  if (body?.symbol_counts && typeof body.symbol_counts === 'object') out.symbol_counts = body.symbol_counts;
  return out;
}
// The portal's SCHEDULE READ (ocrClient.ocrSchedules, 21 Sep 2026, founder instruction 580): the ruled
// tables found on each page (_shared/table_grid.ts) with every cell OCR'd on its own, row/column
// structure kept. Untrusted browser output, so it is rebuilt here to the exact shape and caps the
// portal produces — 40 tables x 80 rows x 24 columns, 120 characters a cell, strings and numbers only —
// and anything else is dropped rather than passed on. Page numbers are bounded by MAX_DRAWING_PAGES.
const MAX_DRAWING_PAGES = 20; // = src/components/me/pdfRaster.ts PDF_MAX_PAGES
function scheduleTables(body: any): Record<string, unknown> {
  if (!Array.isArray(body?.schedule_tables)) return {};
  const num = (v: unknown, lo: number, hi: number) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : lo; };
  const out: unknown[] = [];
  for (const t of body.schedule_tables.slice(0, 40)) {
    if (!t || typeof t !== 'object' || !Array.isArray(t.rows)) continue;
    const page = Math.round(Number(t.page));
    if (!Number.isInteger(page) || page < 1 || page > MAX_DRAWING_PAGES) continue;
    const b = t.bbox || {};
    const rows = t.rows.slice(0, 80).filter(Array.isArray).map((r: unknown[]) => r.slice(0, 24).map((s) => (typeof s === 'string' ? s.slice(0, 120) : '')));
    if (!rows.length) continue;
    const conf = rows.map((r: string[], i: number) => r.map((_, j) => num(Array.isArray(t.conf) && Array.isArray(t.conf[i]) ? t.conf[i][j] : 0, 0, 100)));
    out.push({ page, bbox: { x: num(b.x, 0, 1), y: num(b.y, 0, 1), w: num(b.w, 0, 1), h: num(b.h, 0, 1) }, rows, conf });
  }
  return out.length ? { schedule_tables: out } : {};
}
function labelize(s: string): string { return String(s || '').replace(/[-_]/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase()); }
// 29 Jul 2026 - ANONYMITY. The scrubber lived only in supplier_api's portal READ path, so every
// write path out of here shipped the customer's raw words straight to suppliers: the new-inquiry
// email, its WhatsApp clone via fn_wa_fanout, and the job_awarded_other notice. A customer typing
// "villa fit-out for Ahmed Khan, call 050 123 4567" had that emailed verbatim to up to eight
// suppliers before anyone paid a reveal fee, which is the entire business model inverted. Anything
// leaving this function toward a supplier goes through scrubIdentity first.
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)';
const ID_PATTERNS: RegExp[] = [
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
async function buyerNameOf(inquiryId: string): Promise<BuyerName> {
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
async function notifyLosers(inquiryId: string, summary: string | null, winnerId: number | null) {
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
  try { await admin.from('founder_alerts').insert({ level: 'high', event: 'rfq_no_supplier', detail: ('A customer request (' + label + ', inquiry ' + inqId + ') matched zero suppliers and reached nobody.' + (flagged ? '' : ' The coverage_gap flag ALSO failed to insert, so this gap is not in the action queue.')).slice(0, 900), channel: 'email' }); } catch (_e) { /* */ }
  try {
    const owner = ((await getSecret('admin_emails')) || 'management@quotesdone.com').split(',')[0].trim();
    await queueNotifications([{ type: 'rfq_no_supplier', to_email: owner, to_role: 'admin', inquiry_id: inqId, channel: 'email', status: 'queued',
      subject: 'Customer request reached no suppliers: ' + label,
      body: 'A customer posted a request (' + label + ') and it matched ZERO suppliers, so no one was contacted and no quote can arrive.\n\nInquiry: ' + inqId + '\nSummary: ' + String(summary || '').slice(0, 300) + '\n\nThe customer is waiting. Onboard suppliers in this trade/emirate, or contact them directly.' }]);
  } catch (_e) { /* */ }
  return flagged;
}
async function matchAndNotify(inqId: string, opts: { category: string; emirate: string | null; summary: string; budget: string | null; extra: string }): Promise<{ matches: number; routing: Record<string, any> }> {
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
      // decision_policy's fanout ceiling, per-trade cap and relevance floor. persist:false because
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
  if (!landedIds.length) { if (!routing.matcher_unavailable) routing.coverage_gap_flagged = await flagCoverageGap(inqId, category, emirate, summary); return { matches: 0, routing }; }
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

type Cfg = { standard_reveal_rate: number; refund_window_working_days: number };
async function getCfg(): Promise<Cfg> { const { data } = await admin.from('pricing_config').select('*').eq('id', 1).maybeSingle(); return (data as Cfg) || { standard_reveal_rate: 0.03, refund_window_working_days: 3 }; }
// 6 Sep 2026 (founder): the reveal fee is 3% of the quotation value with NO discount, NO promotional rate
// and NO cap. This copy computes the standard rate and nothing else, the same as public.reveal_fee();
// pricing_config forbids a promo or a cap by constraint (pricing_config_no_discount_no_cap_ck).
function revealFee(amount: number, cfg: Cfg): number { if (!amount || amount <= 0) return 0; return Math.round(amount * Number(cfg.standard_reveal_rate) * 100) / 100; }
// A RATING IS EARNED HERE OR IT DOES NOT EXIST (founder, 9 Sep 2026): "supplier rating should be
// from customers after they tried them", "google review shouldnt be counted". This used to fall
// back to leads.rating ?? leads.rating_maps — the Google Maps star of a business QuotesDone has
// never worked with — and label it source:'Google', which the portal then showed as the supplier's
// rating and scored in its value ranking. 4,477 suppliers carry that scraped number and 0 have ever
// been rated by a customer here, so the fallback WAS the rating on every quote ever compared.
// It is gone. app_rating/app_reviews are written by recompute_supplier_rating() from public.reviews
// and nothing else. No platform review means value null and count 0, which the surface renders as
// "not yet rated on QuotesDone" — an honest absence beats a number that means something else.
function ratingOf(l: Record<string, any>) { const appN = Number(l.app_reviews || 0); const v = (appN > 0 && l.app_rating != null) ? Number(l.app_rating) : null; return { value: v, count: appN, source: v != null ? 'QuotesDone' : null }; }
function band(n: number) { n = Number(n || 0); if (n < 1000) return '< AED 1k'; if (n < 5000) return 'AED 1–5k'; if (n < 20000) return 'AED 5–20k'; if (n < 50000) return 'AED 20–50k'; return 'AED 50k+'; }
// PRE-REVEAL FINGERPRINT (27 Jul 2026). my_inquiries used to return the supplier's exact rating,
// exact review count, emirate, years-since-founding and win rate on EVERY quote, revealed or not.
// "4.6 stars, 23 reviews, Sharjah, trading since 2011" is a unique fingerprint: one Google Maps
// search finds the company, and the buyer contacts them directly without ever paying the reveal
// fee, which is the only transaction revenue this business has. Unrevealed quotes now carry
// coarse bands that fit hundreds of firms, plus the verified flag (a trust signal that identifies
// nobody). Emirate, win rate and rating source are withheld until a transaction exists.
function ratingBand(v: unknown): string | null { const n = Number(v); if (v == null || !isFinite(n) || n <= 0) return null; if (n >= 4.5) return '4.5+'; if (n >= 4) return '4.0-4.5'; if (n >= 3.5) return '3.5-4.0'; return 'below 3.5'; }
// 9 Sep 2026: 'under 5' was returned for a count of ZERO, so a supplier nobody has ever rated on
// QuotesDone read as "has a few reviews" instead of "has none". Zero is now null, the same answer
// the band gives for an absent rating, and the portal renders the pair as "not yet rated".
function reviewCountBand(v: unknown): string | null { const n = Number(v || 0); if (n >= 50) return '50+'; if (n >= 20) return '20-49'; if (n >= 5) return '5-19'; return n > 0 ? 'under 5' : null; }
function yearsBand(v: unknown): string | null { if (v == null) return null; const n = Number(v); if (!isFinite(n)) return null; if (n >= 10) return '10+ years'; if (n >= 5) return '5-9 years'; return 'under 5 years'; }

// A CAD DRAWING THE EDGE CANNOT READ IS READ OFF THE REQUEST PATH (22 Sep 2026, sales_engineer; founder:
// "customer will share cad files or pdf mainly"). MEASURED on production that day: every DWG sent to
// drawing_boq died 546 "Memory limit exceeded" (fixed in doc_read/dwg.ts), and even fixed, a DWG's cost is
// not its size (a 562 KB drawing took 1.9 s of CPU against the 2 s cap). drawing_boq is a SEPARATE worker,
// so its death reaches this function as a 546 answer, not a silent kill. On that answer, or when dwg.ts
// says the drawing is past its edge ceiling, the stored original is queued in public.cad_read_jobs and the
// CAD worker (scripts/cad_read_worker.ts on a GitHub runner, the same reader code, no CPU cap) reads it;
// 'cad_read_status' hands the take-off to the customer's screen. Prevented from regressing by
// scripts/checks/a_cad_upload_reaches_the_cad_reader.test.mjs.
function cadQueueReason(status: number, jd: any): 'over_edge_ceiling' | 'edge_worker_died' | 'edge_reader_failed' | null {
  if (jd?.ok) return jd.kind === 'dwg' && jd.needs === 'cad_conversion' ? 'over_edge_ceiling' : null;
  if (status === 546 || jd?.code === 'WORKER_RESOURCE_LIMIT') return 'edge_worker_died';
  // A refusal the reader gave for the file itself (not a DWG, damaged) would fail the same way off the
  // edge, so only a transport failure or a server error is worth a second reading.
  return status === 0 || status >= 500 ? 'edge_reader_failed' : null;
}
async function queueCadRead(o: { customerId: string; email: string; path: string; name: string; mime: string; b64Len: number; why: string; boqIn?: unknown }): Promise<string | null> {
  const { data, error } = await admin.from('cad_read_jobs').insert({ customer_id: o.customerId, owner_email: o.email, source_path: o.path,
    file_name: o.name, mime: o.mime, bytes: Math.floor(o.b64Len * 3 / 4), why: o.why, boq_in: o.boqIn ?? null }).select('id').maybeSingle();
  if (error || !data?.id) { console.warn(`[cad] could not queue ${o.path}: ${error?.message || 'no id'}`); return null; }
  await dispatchCadWorker(String(data.id));
  return String(data.id);
}
// THE QUEUE STARTS ITS OWN WORKER. A new job dispatches .github/workflows/cad-read-worker.yml at once, and
// while the customer's screen polls cad_read_status (every 15 s) a job still waiting - the dispatch was
// lost - or whose runner went silent is dispatched again (at most once a minute per job). The workflow's
// 6-hourly schedule is only the last resort for a job nobody is polling: a lost dispatch after the
// customer closed the page, or a runner that died after the polling stopped.
async function dispatchCadWorker(jobId: string): Promise<void> {
  try {
    const gh = await getSecret('github_token');
    if (!gh) { console.warn(`[cad] no github_token; job ${jobId} waits for the worker's schedule`); return; }
    const r = await fetch('https://api.github.com/repos/ahmadmhdnabilalzain-bot/quotesdone/actions/workflows/cad-read-worker.yml/dispatches', {
      method: 'POST', headers: { Authorization: `Bearer ${gh}`, Accept: 'application/vnd.github+json', 'User-Agent': 'quotesdone-customer-api' },
      body: JSON.stringify({ ref: 'main' }), signal: AbortSignal.timeout(5000) });
    if (r.status !== 204) console.warn(`[cad] worker dispatch answered ${r.status} for job ${jobId}`);
  } catch (_e) { console.warn(`[cad] worker dispatch failed for job ${jobId}`); }
}
/** A polled job that should have started by now: queued past 2 minutes, or running with no word for 30. */
function cadJobNeedsRedispatch(job: { status: string; created_at: string; claimed_at: string | null }, now = Date.now()): boolean {
  const age = (t: string | null) => (t ? now - Date.parse(t) : 0);
  const stuck = (job.status === 'queued' && age(job.created_at) > 120_000) || (job.status === 'running' && age(job.claimed_at) > 30 * 60_000);
  // At most once a minute per job: the 15 s poll lands in the first 15 s of a minute once in four.
  return stuck && Math.floor(age(job.created_at) / 1000) % 60 < 15;
}

// AUDIT 9.1 (3 Aug 2026). This is the least trusted input in the system: the customer drawing
// path. Whatever lands here is later rendered, passed to an LLM, and shown to suppliers. It
// previously took the caller's declared Content-Type and the caller's filename at face value and
// checked nothing but the byte length - so an HTML document, an SVG carrying script, or a PDF with
// an embedded /Launch action all stored cleanly as "a drawing". It also stored phone photos with
// their EXIF intact, which on an anonymous marketplace means the supplier receives the customer's
// GPS coordinates attached to the "masked" site photo.
// `allow` widens to SAFE_SHEET only on the analyze_boq path (14 Sep 2026); drawings keep PDF/image/CAD.
async function storeOriginal(custId: string, email: string, name: string, mime: string, b64: string, allow: readonly string[] = [...SAFE_UPLOAD, ...SAFE_CAD]): Promise<string | null> {
  try {
    // 5 Aug 2026. The allow-list was SAFE_UPLOAD (PDF + jpeg/png/webp), which excludes CAD - on the
    // one path in the system that explicitly SUPPORTS CAD. analyze_drawing detects .dwg/.dxf and
    // routes it through cad_convert to get page images, so the drawing was converted, read and
    // turned into a BOQ, while storeOriginal rejected the original and returned null behind a
    // console.warn. The customer saw a successful upload; the inquiry got no drawing_file_path, so
    // the actual CAD file the supplier needs to quote from was gone and nothing reported it.
    // SAFE_CAD already exists for exactly this and was simply never wired to its only caller. The
    // sniffer validates both formats structurally (DWG by its AC10xx magic, ASCII DXF by its
    // SECTION/HEADER shape, and it prefers the dangerous reading on ambiguity), so this widens the
    // accepted set without trusting the caller's declared type.
    const sc = await sanitizeAndScan({ input: b64, declaredMime: mime, filename: name, allow, maxBytes: 25 * 1024 * 1024,
                                       scan: { source: 'customer_api.drawing', subject: String(custId || email || ''), filename: name, bucket: 'drawing-files' } });
    if (!sc.ok) {
      console.warn(`[9.1] drawing rejected: ${sc.body.error} - ${sc.body.detail} (declared ${mime})`);
      return null;
    }
    const s = sc.result;
    if (s.declaredMismatch) console.warn(`[9.1] drawing declared ${mime} but is ${s.mime}; stored as ${s.mime}`);
    const path = `drawings/${custId}/${Date.now()}_${safeFilename(name, s.mime)}`;
    const up = await admin.storage.from('drawing-files').upload(path, s.bytes, { contentType: s.mime, upsert: false });
    // The sanitizer's rejection is logged above but the STORAGE rejection was not, and the bucket
    // carries its own allowed_mime_types. A CAD upload was therefore refused twice, silently, and
    // both layers returned the same null: the caller could not tell "we would not accept this" from
    // "the bucket would not accept this" from "the network failed".
    if (up.error) { console.warn(`[9.1] drawing accepted by the sanitizer as ${s.mime} but REJECTED by storage: ${up.error.message}`); return null; }
    // 14 Sep 2026: the path is returned (and later backed up) only once storage confirms the object.
    if (!(await storedAt(admin, 'drawing-files', path))) { console.warn(`[9.1] drawing upload returned no error but storage does not hold ${path}`); return null; }
    // 5 Aug 2026. THE ORPHAN WINDOW. At this point the object exists and the ONLY record of it is
    // the path about to be returned to the client. If the customer never submits, swaps the
    // attachment, or create_inquiry refuses, no row anywhere names it — and both pdpl_erase and
    // retention_purge walk `inquiries`, so an abandoned upload is not merely litter, it is a
    // customer's drawing that cannot be found and therefore cannot be ERASED on request.
    // A ledger row makes it findable by owner. status='original_stored' distinguishes it from a
    // real redaction run; resolveRedactedPaths filters it out (see the .neq there) because it
    // carries no output_paths and would otherwise consume that query's 60-row window.
    try {
      await admin.from('drawing_redaction_runs').insert({
        customer_id: custId, owner_email: email, source_path: path,
        output_paths: [], pages_in: 0, pages_out: 0, status: 'original_stored',
      });
    } catch (_e) { /* never fail an accepted upload on its own bookkeeping */ }
    return path;
  } catch { return null; }
}
// THE QUOTATION DOCUMENT (14 Sep 2026, agent: ceo). quoteDocument lays it out with no model; the
// Arabic copy translates what the platform knows the meaning of and reproduces the supplier's own
// words as written (see _shared/quote_documents.ts for why). translateQuoteAr — an ai_gateway call
// whose failure under the OpenRouter hold silently shipped English under Arabic headings — is gone.
// The anonymous letter of a quote is its place among the LIVE quotes by ascending price: the rule
// my_inquiries and quote_compare both use. This used to count drafts too, so a draft priced below a
// quote made its PDF say "Supplier C" on a card the customer sees as "Supplier B".
async function letterOf(q: any): Promise<string> {
  const { data: sibs } = await admin.from('quotes').select('id,quote_amount').eq('inquiry_id', q.inquiry_id).neq('status', 'draft').order('quote_amount', { ascending: true });
  const idx = (sibs || []).findIndex((s: any) => s.id === q.id); return supplierLabel(idx >= 0 ? idx : 0);
}
// The strings that must not appear on a customer's document before the reveal.
async function supplierIdentities(ids: any[]): Promise<string[]> {
  const uniq = [...new Set((ids || []).filter((x) => x != null).map(String))];
  if (!uniq.length) return [];
  try {
    const { data } = await admin.from('leads').select('company_name,email,phone,whatsapp,website').in('id', uniq);
    return (data || []).flatMap((l: any) => [l.company_name, l.email, l.phone, l.whatsapp, l.website]).filter((v: any) => v && String(v).trim().length >= 3).map(String);
  } catch (_e) { return []; }
}
// 21 Sep 2026 (customer audit, finding 19): after a paid reveal the PDF still said "Supplier A".
// A transactions row for the quote means the customer bought the name; it is printed as the party.
async function revealedPartyName(q: any): Promise<string | null> {
  try {
    const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', String(q.id)).limit(1).maybeSingle();
    if (!tx) return null;
    const { data: l } = await admin.from('leads').select('company_name').eq('id', q.supplier_id).maybeSingle();
    return l?.company_name ? String(l.company_name) : null;
  } catch (_e) { return null; }
}
async function buildQuotePdf(q: any, inq: any, lang: 'en' | 'ar') {
  const partyName = await revealedPartyName(q);
  const letter = await letterOf(q);
  // The supplier's OWN priced breakdown lives in quote_items; the customer's requested BOQ is only
  // the fallback when the supplier priced a lump sum.
  // Each line carries its own price and technical specification (brand, model, specification, and the
  // spec agent's per-attribute `specs` when that column exists), so the quotation can show them.
  let items: Item[] = [];
  try {
    const { data: qi } = await admin.from('quote_items').select('*').eq('quote_id', String(q.id)).order('line_no', { ascending: true }).limit(60);
    items = itemsOfRows(qi);
  } catch (_e) { items = []; }
  // The completeness checks and the per-line specs are the hold desk's own reading (completenessOf,
  // audit 21 Sep 2026, finding 4) — the same reader that approved the quote, so the page cannot
  // contradict the review. The intake answers are read for the checks only.
  let inqSpec: unknown = null;
  try { const { data: s } = await admin.from('inquiries').select('spec').eq('id', String(q.inquiry_id)).maybeSingle(); inqSpec = s?.spec ?? null; } catch (_e) { /* the checks then apply the trade's standard alone */ }
  const done = completenessOf(q, items, inq?.category ?? null, inqSpec);
  items = done.items;
  if (!items.length && inq?.boq && Array.isArray((inq.boq as any).boq)) items = (inq.boq as any).boq.map((b: any) => ({ desc: String(b.description || ''), qty: b.qty == null ? '' : String(b.qty), unit: String(b.unit || '') })).filter((x: any) => x.desc).slice(0, 40);
  const quoteRow = { ...done.quote, scope: items.length ? q.scope : (q.scope || inq?.summary || '') };
  const { body, ref } = quoteDocument({ quote: quoteRow, inquiry: inq, items, letter, lang, partyName, maskNames: partyName ? [] : await supplierIdentities([q.supplier_id]), requestUrl: portalLink(lang, inq.id, q.id) });
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...body, __secret: secret }) });
  const j = await r.json();
  return { j, ref };
}
// The anonymised supplier brief as a branded document. Same engine as the quotations
// and the comparison report, so the customer sees exactly what left the building on
// QuotesDone letterhead instead of a browser print-out.
async function buildBriefPdf(inq: any, lang: string) {
  const ar = lang === 'ar';
  const T = (en: string, arx: string) => (ar ? arx : en);
  const blocks: any[] = [];
  const ref = 'QD-' + jobNoOf(inq) + '-BRIEF';
  // The trade code ('hvac') and the emirate ('Dubai') printed raw on the Arabic brief (audit 21 Sep 2026);
  // they take the same deterministic Arabic the quotation uses. The budget is the customer's own words.
  const trade = (c: unknown) => (ar ? arCategory(c) : null) ?? enCategory(c);
  const kv: any[] = [
    [T('Reference', 'الرقم المرجعي'), ref],
    [T('Category', 'الفئة'), clipCell(trade(inq?.category), 40) || '—'],
    [T('Emirate', 'الإمارة'), clipCell((ar ? arEmirate(inq?.emirate) : null) ?? inq?.emirate, 40) || '—'],
    [T('Budget', 'الميزانية'), clipCell(inq?.budget, 40) || '—'] ];
  if (Array.isArray(inq?.trades) && inq.trades.length) kv.push([T('Trades', 'التخصصات'), clipCell(inq.trades.map(trade).join(ar ? '، ' : ', '), 80)]);
  blocks.push({ t: 'kv', pairs: kv });
  blocks.push({ t: 'h2', text: T('Scope', 'نطاق العمل') });
  blocks.push({ t: 'p', text: String(inq?.summary || '—') });
  const spec = (inq?.spec && typeof inq.spec === 'object' && !Array.isArray(inq.spec)) ? inq.spec : null;
  if (spec) {
    const rows = Object.entries(spec)
      .filter(([k, v]) => k !== 'customer_requirements' && v != null && (typeof v !== 'object' || Array.isArray(v)) && String(v).trim() !== '')
      .map(([k, v]) => [clipCell(String(k).replace(/_/g, ' '), 40), clipCell(Array.isArray(v) ? v.join(', ') : v, 160)]);
    if (rows.length) {
      blocks.push({ t: 'h2', text: T('Specification', 'المواصفات') });
      blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Detail', 'التفاصيل')], rows, widths: [0.32, 0.68] });
    }
  }
  // What the customer asked the sales engineer for (docs/contracts/intake_answers.md), from the derived
  // display rows so the PDF says exactly what the portal says, in the document's language.
  const reqRows = (spec as any)?.customer_requirements?.display?.[ar ? 'ar' : 'en'];
  if (Array.isArray(reqRows) && reqRows.length) {
    blocks.push({ t: 'h2', text: T('What the customer asked for', 'ما طلبه العميل') });
    blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Requested', 'المطلوب')], rows: reqRows.map((r: any) => [clipCell(r?.label, 40), clipCell(r?.value, 160)]), widths: [0.32, 0.68] });
  }
  const boq = (inq?.boq && Array.isArray((inq.boq as any).boq)) ? (inq.boq as any).boq : null;
  if (boq && boq.length) {
    const rows = boq.slice(0, 60)
      .map((b: any, i: number) => [String(i + 1), clipCell(b.description, 150), b.qty == null ? '' : String(b.qty), clipCell(b.unit, 12)])
      .filter((r: any) => r[1]);
    if (rows.length) {
      blocks.push({ t: 'h2', text: T('Bill of quantities', 'جدول الكميات') });
      blocks.push({ t: 'table', head: ['#', T('Description', 'الوصف'), T('Qty', 'الكمية'), T('Unit', 'الوحدة')], rows, widths: [0.07, 0.68, 0.12, 0.13] });
    }
  }
  if (inq?.drawing_file_name) blocks.push({ t: 'note', text: T('A drawing is attached to this request and is shared with matched suppliers: ', 'أُرفق بهذا الطلب مخطط يطّلع عليه المورّدون المطابقون: ') + clipCell(inq.drawing_file_name, 80) });
  blocks.push({ t: 'space', h: 6 });
  blocks.push({ t: 'note', text: T(
    'This is the anonymised brief QuotesDone sends to matched suppliers. The customer name, company and contact details are never included - suppliers quote on the scope alone, and contact details are exchanged only after the customer reveals a quote.',
    'هذا ملخّص الطلب كما ترسله QuotesDone إلى المورّدين المطابقين، دون الإفصاح عن هوية العميل؛ فلا يتضمّن اسمه ولا اسم شركته ولا بيانات التواصل معه. يقدّم المورّدون عروضهم استنادًا إلى نطاق العمل وحده، ولا تُتبادل بيانات التواصل إلا بعد أن يكشف العميل عن العرض الذي يختاره.') });
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, title: T('Supplier brief', 'ملخّص الطلب للمورّدين'), ref, name: ref, lang: ar ? 'ar' : 'en', blocks, options: { letterhead: true } }) });
  const j = await r.json();
  return { j, ref };
}
// The refund case reference the Terms (§5) and Refund Policy (§3, §6) promise to quote.
const refundRef = (id: number | string) => 'QD-RF-' + String(id);

// The comparison report: the analysis quote_compare returned, laid out by compareDocument (see
// _shared/quote_documents.ts — the side-by-side table, the roster of every quote, the anonymity
// mask). compare_csv exports the same compareTable rows, so the two can never disagree.
// ONE server-to-server call to quote_compare, shared by compare_pdf and compare_csv.
// Measured 14 Sep 2026 (e2e run 5): the same customer got a deterministic analysis from
// quote_compare with their own JWT and {"error":"comparison_unavailable"} from compare_pdf in both
// languages. quote_compare is deployed with verify_jwt = true and both call sites POSTed with no
// Authorization header, so the gateway refused them with a 401 BEFORE the function ran; the
// gateway's body carries neither `error` nor `note`, which is exactly what fell through to the
// generic label. Same defect sales_engineer's `match` call had (see the routing block above).
// The service key gets past the gateway; __secret (cred_fn_customer_api, scope includes
// quote_compare) is what decides the caller inside.
async function fetchCompareAnalysis(iid: string, lang: 'en' | 'ar'): Promise<{ analysis?: any; error?: string }> {
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/quote_compare`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${SERVICE}`, apikey: SERVICE },
    body: JSON.stringify({ __secret: secret, inquiry_id: iid, lang }) });
  const jd = await r.json().catch(() => null);
  if (jd?.ok && jd.analysis) return { analysis: jd.analysis };
  return { error: jd?.note || jd?.error || (r.ok ? 'comparison_unavailable' : 'comparison_unavailable_http_' + r.status) };
}

async function buildComparePdf(a: any, inq: any, lang: 'en' | 'ar') {
  const { data: sq } = await admin.from('quotes').select('supplier_id').eq('inquiry_id', inq.id);
  const maskNames = await supplierIdentities((sq || []).map((r: any) => r.supplier_id));
  const portalUrl = portalLink(lang, inq.id);
  const { body, ref } = compareDocument({ analysis: a, inquiry: inq, lang, maskNames, portalUrl, linkFor: (qid) => portalLink(lang, inq.id, qid) });
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...body, __secret: secret }) });
  const j = await r.json();
  return { j, ref };
}

// REDACTION PROVENANCE 2 Aug 2026 (external security review). WHY: QuotesDone sells anonymity —
// a supplier must not learn who the buyer is until the reveal fee is paid. supplier_api hands every
// matched supplier a SIGNED URL for each entry in inquiries.drawing_redacted_paths, and it will sign
// ANY object path in the 'drawing-files' bucket. The customer's ORIGINAL, unredacted upload sits in
// that SAME bucket at drawings/<customer_id>/<ts>_<name> (see storeOriginal above); redacted pages
// sit at redacted/<uuid>/page_pN.jpg. create_inquiry used to copy drawing.drawing_redacted_paths
// verbatim out of the REQUEST BODY, so a modified or simply buggy frontend could name the original —
// title block, client name, address, contacts, project number — and every matched supplier would get
// it for free, pre-reveal, destroying both the promise and the reveal-fee revenue behind it.
// Paths are no longer trusted from the client. drawing_redact records each run in
// public.drawing_redaction_runs (owner, outputs, pages_in/pages_out, status) and this resolver will
// only ever attach paths found in a run row that belongs to the CALLING customer. Anything else is
// REJECTED with an explicit error rather than silently dropped, so the frontend can surface it
// instead of quietly shipping a half-anonymous RFQ.
const REDACT_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
type RedactResolve = { paths: string[] } | { err: Record<string, unknown>; status: number };
async function resolveRedactedPaths(custId: string, authUserId: string, drawing: any): Promise<RedactResolve> {
  const asked = Array.isArray(drawing?.drawing_redacted_paths) ? drawing.drawing_redacted_paths.map((s: any) => String(s)).slice(0, 24) : [];
  const jobIds = [
    ...(drawing?.redaction_job_id ? [String(drawing.redaction_job_id)] : []),
    ...(Array.isArray(drawing?.redaction_job_ids) ? drawing.redaction_job_ids.map((s: any) => String(s)) : []),
  ].filter((s) => REDACT_UUID_RE.test(s)).slice(0, 8);
  // Explicit opt-out: the buyer (or the UI, after a partial redaction) can choose to share no pages
  // at all. Sharing fewer pages never leaks anything, so this is always allowed.
  if (drawing?.share_redacted === false) return { paths: [] };
  if (!jobIds.length && !asked.length) return { paths: [] };
  // Reference photos go through attach_photos, which is authenticated as the same auth user but does
  // not know customers.id; drawing_redact stores the prefix it was called with, so those runs are
  // attributed by that instead. Both branches are server-side ownership checks — neither trusts a path.
  const photoRef = 'refphoto/' + String(authUserId || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 24) + '/';
  const { data: runs, error: rerr } = await admin.from('drawing_redaction_runs')
    .select('id,customer_id,caller_ref,output_paths,pages_in,pages_out,status')
    .or(`customer_id.eq.${custId},caller_ref.like.${photoRef}%`)
    // NOT optional. storeOriginal now writes one 'original_stored' row per upload so an abandoned
    // drawing stays erasable. Those rows carry no output_paths and contribute nothing here, but
    // this query keeps only the 60 most recent runs — so without this filter a customer who
    // uploads repeatedly would push their own REAL redaction runs out of the window, and
    // create_inquiry would answer redaction_job_not_found (403) on a perfectly good drawing.
    .neq('status', 'original_stored')
    // 'held' rows (analyze_drawing, 21 Sep 2026) are the ledger of drawings that went out unshared;
    // they carry no output_paths either and must not push real runs out of the window.
    .neq('status', 'held')
    .order('created_at', { ascending: false }).limit(60);
  if (rerr) return { err: { error: 'redaction_lookup_failed', message: 'We could not verify the redacted drawing pages just now. Please try again in a moment.' }, status: 503 };
  const mine = (runs || []).filter((r: any) => (r.customer_id && String(r.customer_id) === String(custId)) || (r.caller_ref && String(r.caller_ref).startsWith(photoRef)));
  const byId: Record<string, any> = {}; for (const r of mine) byId[String(r.id)] = r;
  const chosen: any[] = [];
  for (const jid of jobIds) {
    const r = byId[jid];
    if (!r) return { err: { error: 'redaction_job_not_found', message: 'That redaction job does not belong to your account or has expired. Please re-upload the drawing and try again.' }, status: 403 };
    chosen.push(r);
  }
  if (!jobIds.length) chosen.push(...mine);
  const allowed = new Set<string>();
  for (const r of chosen) for (const p of (r.output_paths || [])) allowed.add(String(p));
  let paths: string[];
  if (asked.length) {
    const bad = asked.filter((p: string) => !allowed.has(p));
    if (bad.length) return { err: { error: 'redacted_paths_unverified', rejected: bad.length, message: `${bad.length} of the attached drawing page(s) did not come from a redaction run on your account, so nothing was sent. Please re-run the drawing analysis and submit again.` }, status: 400 };
    paths = asked;
  } else {
    paths = Array.from(allowed);
  }
  // COMPLETENESS. A partial run (say 5 of 8 pages cleaned) must not quietly attach the 5 that
  // worked: the buyer believes the whole drawing was anonymised, and the 3 that failed are exactly
  // the pages the model was least sure about. Fail closed and name the number. A TOTAL failure still
  // behaves as before — no run outputs, no paths, and the inquiry goes out with no drawing attached.
  const used = chosen.filter((r: any) => (r.output_paths || []).some((p: any) => paths.includes(String(p))));
  let missing = 0; for (const r of used) missing += Math.max(0, Number(r.pages_in || 0) - Number(r.pages_out || 0));
  if (paths.length && missing > 0) {
    return { err: { error: 'redaction_incomplete', pages_missing: missing, message: `${missing} page(s) of your drawing could not be redacted, so no pages were shared. Please re-upload a clearer copy, or send the request without the drawing.` }, status: 409 };
  }
  return { paths };
}

Deno.serve(observe('customer_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  // KEEP-WARM (resilience_ping, 14 Sep 2026). No auth, no DB, before anything else: the isolate is
  // what needs exercising, not a real answer. See the header of resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    const auth = req.headers.get('Authorization') || ''; const jwt = auth.replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    // THIS ENDPOINT USED TO MANUFACTURE A CUSTOMER ACCOUNT FOR WHOEVER CALLED IT (13 Aug 2026).
    //
    //     if (!cust) { await admin.from('customers').insert({ email }) ... }
    //
    // Any authenticated identity that touched customer_api became a customer. Measured: the
    // duplicate management@quotesdone.com row was retired at 20:30 and a NEW one appeared at
    // 21:01:05 with a different id, full_name null and phone null - the exact shape of
    // insert({ email }), and this is the only line in the estate that writes it. The admin address
    // is admin_emails[0]; it is not a buyer, and a buyer account under it is what made the identity
    // defect read as "the account screen shows the wrong e-mail" in the first place.
    //
    // It is also redundant on the legitimate path: login_otp's email branch already inserts the
    // customers row when a real customer verifies their code (the 12 Aug fix - a first-time
    // customer had no row to UPDATE, so email_verified stayed false and every RFQ was refused).
    // A customer JWT can only come from mintSession there, so by the time anyone reaches this line
    // with a genuine buyer session the row exists. What was left was the case this must NOT serve:
    // staff and admin sessions silently acquiring buyer accounts.
    //
    // Refusing matches what stripe_checkout and stripe_confirm already answer on the same
    // condition ('No customer profile', 403) rather than inventing a new vocabulary for it.
    const { data: cust } = await admin.from('customers').select('*').eq('email', email).maybeSingle();
    if (!cust) return J({ error: 'No customer profile', hint: 'This signed-in identity has no customer account. Customer accounts are created when a buyer verifies their sign-in code, not by reading this endpoint.' }, 403);
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');
    // BANNED CUSTOMER (27 Jul 2026). messages_api auto-bans a buyer who pushes contact details
    // off-platform (it writes customers.banned = true) but customer_api never read that column,
    // so the ban only ever closed the chat: the same person could still post RFQs, reveal
    // suppliers, request refunds and rate them from the main buyer surface. Every mutating
    // action is refused now. 'me' and 'my_inquiries' stay open on purpose so the person can
    // still see their own account state and existing requests rather than hitting a dead wall.
    const MUTATING = ['create_inquiry', 'edit_inquiry', 'reveal', 'request_refund', 'rate_supplier', 'complete_inquiry', 'cancel_inquiry', 'rfq_note'];
    if (cust?.banned === true && MUTATING.includes(action)) return J({ error: 'Your account is suspended. Please contact support@quotesdone.com if you believe this is a mistake.' }, 403);

    if (action === 'me') return J({ customer: cust });

    // ATTACH A BOQ (founder, 14 Sep 2026: "describe a job / drop a drawing is fine but add attach a
    // BOQ also"). A spreadsheet BOQ (xlsx / xls / csv). drawing_boq mode 'sheet' sniffs it by its
    // bytes, caps it at 5 MB, refuses macros and encryption, and reads cached cell values with no model.
    // Only a file it accepted is stored, beside drawings, with the same owner ledger row, so pdpl_erase
    // finds it the same way. A PDF BOQ does not come here: analyze_drawing reads its text layer.
    // THE TAKE-OFF OF A QUEUED CAD DRAWING (22 Sep 2026, see queueCadRead). Only the job's own customer
    // gets an answer; anyone else's id reads as not found.
    if (action === 'cad_read_status') {
      const id = String(body.job_id || '');
      if (!/^[0-9a-f-]{36}$/i.test(id)) return J({ ok: false, error: 'not_found' }, 404);
      const { data: job } = await admin.from('cad_read_jobs').select('status, result, finished_at, created_at, claimed_at').eq('id', id).eq('customer_id', cust.id).maybeSingle();
      if (!job) return J({ ok: false, error: 'not_found' }, 404);
      if (cadJobNeedsRedispatch(job as any)) await dispatchCadWorker(id);
      return J({ ok: true, status: job.status, boq: job.status === 'done' ? (job.result as any)?.boq ?? null : null });
    }

    if (action === 'analyze_boq') {
      const name = String(body.file_name || 'boq').slice(0, 180);
      const mime = String(body.mime || '');
      const b64 = String(body.file_b64 || '');
      if (!b64) return J({ ok: false, error: 'empty_upload' }, 400);
      // 5 MB of bytes is about 6.7 MB of base64: refused here before anything is decoded or forwarded.
      if (b64.length > 7 * 1024 * 1024) return J({ ok: false, error: 'file_too_large' });
      const hint = String(body.hint || '').slice(0, 400);
      const secret = await getSecret('cred_fn_customer_api');
      let jd: any = null;
      try {
        const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'sheet', file_b64: b64, mime, filename: name, hint }) });
        jd = await r.json();
      } catch (_e) { /* answered below as boq_unreadable */ }
      if (!jd?.ok) return J({ ok: false, error: String(jd?.error || 'boq_unreadable'), detail: String(jd?.detail || '').slice(0, 200) });
      const path = await storeOriginal(cust.id, email, name, mime, b64, SAFE_SHEET);
      return J({ ok: true, boq: jd.boq, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], stored: !!path });
    }

    // EVERY DOCUMENT (14 Sep 2026; founder: "the sales agent need to be extremely capable of reading
    // all types of document"). Word, PowerPoint, ODF, RTF, text, email (.eml/.msg), DXF, IFC, GAEB,
    // zip and PDF are read by drawing_boq mode 'document' with no model; a photo arrives with the
    // customer's browser OCR as ocr_text. The same 20 MB ceiling as doc_read; stored only if accepted.
    if (action === 'analyze_document') {
      const name = String(body.file_name || 'document').slice(0, 180);
      const mime = String(body.mime || '');
      const b64 = String(body.file_b64 || '');
      if (!b64) return J({ ok: false, error: 'empty_upload' }, 400);
      if (b64.length > 27 * 1024 * 1024) return J({ ok: false, error: 'file_too_large' });
      const hint = String(body.hint || '').slice(0, 400);
      const secret = await getSecret('cred_fn_customer_api');
      let jd: any = null; let st = 0;
      try {
        const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'document', file_b64: b64, mime, filename: name, hint, ocr_text: String(body.ocr_text || '').slice(0, 200_000), ...drawingOcr(body) }) });
        st = r.status; jd = await r.json().catch(() => null);
      } catch (_e) { /* answered below as document_unreadable */ }
      // A DXF (ASCII or binary) too heavy for the edge is queued for the CAD worker like a DWG (22 Sep 2026).
      const cadWhy = /\.(dxf|dwg)$/i.test(name) ? cadQueueReason(st, jd) : null;
      if (cadWhy) {
        const p = await storeOriginal(cust.id, email, name, mime, b64, SAFE_DOCS);
        const job = p ? await queueCadRead({ customerId: cust.id, email, path: p, name, mime, b64Len: b64.length, why: cadWhy }) : null;
        if (job) return J({ ok: true, boq: null, kind: 'dxf', needs: 'cad_conversion', drawing_file_path: p, drawing_file_name: name, drawing_redacted_paths: [], stored: true, note: 'cad_queued', cad_job_id: job });
      }
      if (!jd?.ok) return J({ ok: false, error: String(jd?.error || 'document_unreadable'), detail: String(jd?.detail || '').slice(0, 200) });
      const path = await storeOriginal(cust.id, email, name, mime, b64, SAFE_DOCS);
      // A DXF's take-off carries the file's own names (layers, blocks, title block): cad_identity takes them
      // out before the customer's portal holds the BOQ it will send (22 Sep 2026). The CAD file itself is
      // never shared, and the customer is told so (drawing_held, the same notice analyze_drawing gives).
      const cad = /\.(dxf|dwg)$/i.test(name) || /dxf|dwg/i.test(mime);
      return J({ ok: true, boq: cad && jd.boq ? cadSupplierBoq(jd.boq, dxfTextOf(b64)) : jd.boq, kind: jd.kind || null, needs: jd.needs || null, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], stored: !!path, ...(cad ? { drawing_held: !!path, share_redacted: false } : {}) });
    }

    if (action === 'analyze_drawing') {
      let images: any[] = Array.isArray(body.images) ? body.images.slice(0, MAX_DRAWING_PAGES) : [];
      const name = String(body.drawing_file_name || 'drawing').slice(0, 180);
      const mime = String(body.mime || 'application/octet-stream');
      const hint = String(body.hint || '').slice(0, 400);
      const path = body.original_b64 ? await storeOriginal(cust.id, email, name, mime, String(body.original_b64)) : null;
      const secret = await getSecret('cred_fn_customer_api');
      const isCad = /\.(dwg|dxf)$/i.test(name) || /dwg|dxf|autocad|acad/i.test(mime);
      if (!images.length && isCad && body.original_b64) {
        try { const cr = await fetch(`${SUPABASE_URL}/functions/v1/cad_convert`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, b64: body.original_b64, filename: name }) }); const cj = await cr.json(); if (cj?.ok && Array.isArray(cj.images) && cj.images.length) images = cj.images.slice(0, MAX_DRAWING_PAGES); } catch (_e) { /* */ }
      }
      // WHY THE NOTE IS SPECIFIC NOW (11 Aug 2026). Spec #7 §3 names "a customer uploads a ZIP file
      // instead of a PDF" and "a PDF is corrupted" as two of its sixteen exception scenarios.
      // Measured before changing anything: neither crashed — both fell through to the single note
      // 'no_readable_pages', which is true and useless. The customer is told nothing they can act
      // on, and sending a ZIPPED DRAWING SET is normal practice in UAE construction, so this is the
      // likeliest of the sixteen to actually happen. The recovery strategy for both is the same and
      // it is not a retry: tell the person exactly what to send instead.
      const isArchive = /\.(zip|rar|7z|tar|tgz|gz)$/i.test(name)
        || /(^|[^a-z])(zip|rar|7z|x-7z|x-tar|gzip|compressed)([^a-z]|$)/i.test(mime);
      if (!images.length && isCad && body.original_b64) {
        // No picture of the sheet, so nothing a supplier can be shown - but the CAD file itself is still
        // read for its take-off (doc_read dwg / dxf). The drawing stays held for suppliers.
        let boq: unknown = null; let st = 0; let jd: any = null;
        try {
          const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'document', file_b64: body.original_b64, mime, filename: name, hint }) });
          st = r.status; jd = await r.json().catch(() => null); if (jd?.ok && jd.boq) boq = cadSupplierBoq(jd.boq, dxfTextOf(String(body.original_b64)));
        } catch (_e) { /* answered below with boq null */ }
        const why = cadQueueReason(st, jd);
        if (why && path) {
          const job = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why });
          if (job) return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], drawing_held: true, share_redacted: false, note: 'cad_queued', cad_job_id: job });
        }
        if (boq) return J({ ok: true, boq, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], drawing_held: !!path, share_redacted: false, note: 'cad_read_not_pictured' });
      }
      if (!images.length) {
        const note = isCad ? 'cad_not_converted' : (isArchive ? 'archive_not_supported' : 'no_readable_pages');
        const advice = isCad
          ? 'We could not convert this CAD file. Please export it to PDF and upload that.'
          : (isArchive
            ? 'This is a compressed archive, so we cannot read the drawings inside it. Please extract it and upload the PDF or image files themselves — you can attach up to 10 pages.'
            : 'We could not read any pages from this file. It may be corrupted, password-protected, or saved in a format we cannot open. Please re-export it as a PDF or upload clear images of each page.');
        return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name,
                   drawing_redacted_paths: [], drawing_held: !!path, share_redacted: false, note, advice });
      }
      try {
        const redPrefix = `redacted/${crypto.randomUUID()}/page`;
        // REDACTION IS BATCHED (13 Aug 2026), because one call over a real drawing set does not
        // survive. MEASURED on staging with a genuine 6-sheet consultant mechanical set rasterised
        // exactly as the portal rasterises it: 1-4 pages return 200 (22.9s / 24.2s / 27.6s / 37.2s),
        // 5 pages return HTTP 546 WORKER_RESOURCE_LIMIT at 37.5s. imagescript decodes each page to
        // full-resolution RGBA before resizing to MAXW, so cost is per page and the isolate is
        // killed outright - which means drawing_redact's own recordRun never runs and NOTHING is
        // written. The customer saw a successful upload with zero redacted pages and no trace.
        // Four pages per call is the measured ceiling with a page in hand; the loop is sequential
        // so two batches never run concurrently against the same budget.
        // 22 SEP 2026 — ONE PAGE PER CALL. Since #794 the portal's pages are kept at 2600 px (a 36x24 sheet
        // readable to a supplier) and at that size four pages did not survive: on production an 8-sheet set
        // came back 546 WORKER_RESOURCE_LIMIT on both 4-page calls (12.0 s and 8.9 s), 8 of 8 pages lost,
        // the drawing held (scripts/e2e/drawing_reaches_suppliers.mjs). drawing_redact now also interprets
        // only its own pages of the original. Measured per page, see the PR: decode + paint + encode of a
        // 2600 px sheet plus that one page's text layer.
        const REDACT_BATCH = 1;
        // CUSTOMER-DRAWN REDACTION (website audit 14 Sep 2026). Under the model hold drawing_redact
        // verifies nothing, so a drawing never reached a supplier. The portal now lets the customer
        // box what must be hidden; drawing_redact applies those boxes deterministically. One entry
        // per page, normalised 0..1 {x,y,w,h}; anything malformed is dropped here, never forwarded.
        const c01 = (v: unknown) => { const n = Number(v); return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0; };
        let manualBoxes: { x: number; y: number; w: number; h: number }[][] | null = Array.isArray(body.manual_boxes)
          ? body.manual_boxes.slice(0, 10).map((pg: unknown) => Array.isArray(pg)
            ? pg.slice(0, 40).map((bx: any) => ({ x: c01(bx?.x), y: c01(bx?.y), w: c01(bx?.w), h: c01(bx?.h) })).filter((bx) => bx.w > 0 && bx.h > 0)
            : [])
          : null;
        // THE TITLE BLOCK, BOXED WITHOUT A MODEL, AND THE TRUST BOUNDARY (14 Sep 2026). A PDF drawing's
        // title block, revision table and every run carrying this customer's name / email / phone /
        // file name or a plot, Makani, address or permit pattern are boxed by the SERVER from the stored
        // original's own text positions. The customer's boxes come from their browser and prove nothing:
        // they are only ever added as extra cover (supplier_copy.supplierBoxes). When the server cannot
        // derive the boxes itself — any photo, scan or CAD raster (no text layer), a rotated page, a
        // title block it did not find, a residual it could not cover — no boxes are sent at all, and
        // drawing_redact holds every page. Fail closed.
        let serverBoxes: { x: number; y: number; w: number; h: number }[][] | null = null;
        if (/pdf/i.test(mime) && body.original_b64) {
          try {
            const bytes = Uint8Array.from(atob(String(body.original_b64).replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));
            const tb = titleBlockBoxes(await pdfPages(bytes, undefined, { layers: false }), seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', extra: [name] }));
            serverBoxes = supplierBoxes(tb, manualBoxes, images.length);
          } catch (_e) { serverBoxes = null; }
        }
        manualBoxes = serverBoxes;
        const redactBatch = async (slice: any[], from: number) => {
          const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, images: slice, prefix: redPrefix, owner_customer_id: cust.id, owner_email: email, source_path: path, page_offset: from, original_b64: body.original_b64 || null, ...(manualBoxes ? { manual_boxes: manualBoxes.slice(from, from + slice.length) } : {}) }) });
          return await r.json();
        };
        // original_b64 lets drawing_boq read a PDF's own text layer with no model — the hold-proof path.
        // A CAD FILE IS READ, NOT PICTURED (22 Sep 2026, sales_engineer; founder instructions 31, 63, 64).
        // doc_read now opens a DWG (LibreDWG) and runs the DXF take-off, but the portal sends a .dwg here,
        // to analyze_drawing, and this call gave drawing_boq only the rasterised sheets: the reader had no
        // way in. The CAD original goes to drawing_boq's 'document' mode for the take-off; cad_convert's
        // pictures above are still what drawing_redact covers for suppliers.
        const boqBody = isCad && body.original_b64
          ? { __secret: secret, mode: 'document', file_b64: body.original_b64, mime, filename: name, hint }
          : { __secret: secret, hint, images, original_b64: body.original_b64 || null, mime, ocr_text: String(body.ocr_text || '').slice(0, 200_000), ...drawingOcr(body), ...scheduleTables(body) };
        const boqP = fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify(boqBody) });
        let redacted: string[] = []; const redJobs: string[] = []; let redIn = 0; let redOut = 0; let redDied = 0;
        // drawing_redact says needs_manual_boxes when its automatic detection could not run (no model
        // under the hold) — the portal opens the customer's box editor on exactly that signal.
        let needsManual = false;
        // Only pass paths back to the client once drawing_redact has RECORDED the run server-side
        // (drawing_redaction_runs). An unrecorded run cannot be verified at create_inquiry, so its
        // paths are unusable — dropping them here lands on the existing total-failure behaviour
        // (inquiry goes out with no drawing) instead of a confusing rejection later.
        for (let i = 0; i < images.length; i += REDACT_BATCH) {
          const slice = images.slice(i, i + REDACT_BATCH);
          try {
            const rj = await redactBatch(slice, i);
            const inN = Number(rj?.pages_in || 0);
            if (rj?.needs_manual_boxes === true) needsManual = true;
            // A 546 answers JSON too - {code:'WORKER_RESOURCE_LIMIT'} with no pages_in - so an
            // isolate death is counted as pages LOST rather than as a batch that carried no pages.
            if (!inN && !rj?.ok) { redDied += slice.length; redIn += slice.length; continue; }
            redIn += inN; redOut += Number(rj?.pages_out || 0);
            if (rj?.ok && rj?.recorded && rj?.job_id && Array.isArray(rj.paths)) { redacted = redacted.concat(rj.paths.map((x: any) => String(x))); redJobs.push(String(rj.job_id)); }
          } catch (_e) { redDied += slice.length; redIn += slice.length; }
        }
        const boqRes = await Promise.allSettled([boqP]).then((a) => a[0]);
        // redaction_complete compared redOut >= redIn, and both are 0 when the redactor dies before
        // it can report anything - so total failure read as "complete". It now requires that pages
        // were sent AND that every one of them came back.
        const redMeta = { redaction_job_id: redJobs[0] || null, redaction_job_ids: redJobs, redaction_pages_in: redIn, redaction_pages_out: redOut, redaction_pages_lost: redDied, redaction_complete: redIn > 0 && redOut === redIn, needs_manual_boxes: false /* the customer's boxes no longer make a page shareable (trust boundary, 14 Sep 2026), so they are not asked for */ };
        // THE HOLD IS DECIDED AND RECORDED HERE (audit 21 Sep 2026, finding 9; ./drawing_hold.ts).
        // Anything short of every page verified hands back NO redacted paths and share_redacted:false,
        // and writes one 'held' row against the stored original so the unshared drawing is visible.
        const hand = drawingHandoff(redMeta, path, redacted);
        if (hand.drawing_held && path) {
          const reason = serverBoxes ? 'server_boxes_sent_pages_refused' : (needsManual ? 'no_server_boxes_and_model_refused' : (redDied ? 'redactor_died' : 'pages_not_verified'));
          try { await admin.from('drawing_redaction_runs').insert(heldRun({ customerId: cust.id, email, sourcePath: path, meta: redMeta, reason })); } catch (_e) { /* the hold stands even if its record fails */ }
        }
        if (boqRes.status !== 'fulfilled') return J({ ok: false, error: 'analysis_exception', detail: 'boq_fetch_failed', drawing_file_path: path, drawing_file_name: name, ...redMeta, ...hand }, 200);
        const jd = await boqRes.value.json().catch(() => null);
        // A CAD original the edge could not read (past its ceiling, or its worker died) is read off the
        // request path; the pictured sheets above still went through redaction for suppliers.
        const cadWhy = isCad && body.original_b64 ? cadQueueReason(boqRes.value.status, jd) : null;
        if (cadWhy && path) {
          const job = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why: cadWhy });
          if (job) return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name, ...redMeta, ...hand, note: 'cad_queued', cad_job_id: job });
        }
        if (!jd?.ok) return J({ ok: false, error: 'analysis_failed', detail: jd?.detail || jd?.error || '', drawing_file_path: path, drawing_file_name: name, ...redMeta, ...hand }, 200);
        // THE CONFIRM STEP RUNS ONLY NOW, after redaction has finished and every page came back
        // (review of #642: it used to run in parallel and could see the original page). drawing_boq
        // re-reads the run by id and uses its recorded redacted page, or marks the lines unconfirmed.
        // A CAD take-off loses the file's own names here (cad_identity, 22 Sep 2026); a PDF's is gated below.
        const boqOut = isCad && jd.boq ? cadSupplierBoq(jd.boq, dxfTextOf(String(body.original_b64 || ''))) : jd.boq;
        let lengthsJob: string | null = null;
        // THE LENGTHS (22 Sep 2026): a drawing set read from a PDF gets its duct and pipe lengths from a SECOND
        // drawing_boq call that reads the CAD layers (drawing_set.ts, "THE LENGTHS ARE A SECOND CALL"). If it
        // fails or is killed, boqOut stands with its counted lines, and the customer is told why no lengths.
        if (boqOut && boqOut.method === 'drawing_set' && /pdf/i.test(mime) && body.original_b64) {
          try {
            const lr = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'lengths', boq: boqOut, original_b64: body.original_b64 }) });
            const lj = await lr.json().catch(() => null);
            // A big set's lengths killed the edge worker (measured 22 Sep 2026: 546 at 40 synthetic sheets,
            // 200 at 20): the counted take-off goes back now, and the CAD worker merges the lengths in.
            if (lr.status === 546 && path && Array.isArray(boqOut.boq)) {
              const job = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why: 'pdf_lengths_worker_died', boqIn: boqOut });
              if (job) { lengthsJob = job; boqOut.missing_info = [LENGTHS_QUEUED_NOTE, ...(Array.isArray(boqOut.missing_info) ? boqOut.missing_info : [])]; }
            }
            if (lj?.ok && lj.boq && Array.isArray(lj.boq.boq)) Object.assign(boqOut, lj.boq);
            else if (!lengthsJob && Array.isArray(boqOut.boq) && boqOut.boq.some((l: any) => /^(duct|pipe):/.test(String(l?.type || '')) && l?.qty == null)) boqOut.missing_info = [LENGTHS_FAILED_NOTE, ...(Array.isArray(boqOut.missing_info) ? boqOut.missing_info : [])];
          } catch (_e) { /* the counted take-off stands */ }
        }
        if (boqOut && Array.isArray(boqOut.boq) && boqOut.boq.length) {
          try {
            const cr = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'confirm', boq: boqOut.boq, redaction_job_id: redMeta.redaction_complete ? redJobs[0] : null }) });
            const cj = await cr.json();
            if (cj?.ok && Array.isArray(cj.boq)) { boqOut.boq = cj.boq; boqOut.confirm = cj.confirm; if (cj.confirm_detail) boqOut.confirm_detail = cj.confirm_detail; }
          } catch (_e) { /* the coded result stands */ }
        }
        return J({ ok: true, boq: boqOut, drawing_file_path: path, drawing_file_name: name, ...redMeta, ...hand, ...cadNote(isCad && !!body.original_b64, hand), ...(lengthsJob ? { note: 'lengths_queued', cad_job_id: lengthsJob } : {}) });
      } catch (e) { return J({ ok: false, error: 'analysis_exception', detail: String((e as Error)?.message || e), drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], drawing_held: !!path, share_redacted: false }, 200); }
    }

    if (action === 'create_inquiry') {
      // THE FOUNDER'S ACCOUNT RULE (14 Sep 2026): a request is made only by a signed-up customer with
      // a name, an 18+ date of birth, an OTP-verified mobile OR email, and the Terms checkbox. The
      // definition lives in _shared/account_rule.ts so kyc and this gate cannot drift. A reachable
      // mobile stays required on top (the reveal hands the winning supplier a contact card).
      const missingAcct = accountMissing(cust);
      if (!String(cust.phone || '').trim()) missingAcct.push('mobile_number');
      if (missingAcct.length) return J({ error: 'account_incomplete', code: 'account_incomplete', missing: missingAcct, message: 'Please finish setting up your account first: ' + missingAcct.join(', ') + '. Open the Account tab.' }, 403);
      // REGISTRATION COMPLETENESS GATE (2 Aug 2026, external code review). This endpoint checked
      // email_verified and nothing else, so the three things that make a buyer real — a name, a
      // reachable mobile, and an accepted version of the Terms — were enforced by the FRONTEND
      // only. Anyone with a verified email and a JWT could POST straight here and put an RFQ in
      // front of matched suppliers with none of them. Two concrete costs: the supplier who later
      // wins the job is handed a reveal (which the buyer paid 3% for) containing an empty contact
      // card, and there is no accepted-terms record to point at if that job goes wrong — the
      // entire T&C evidence chain assumes tos_accepted_at exists by the time an RFQ is dispatched.
      //
      // Deliberately NOT blocking on signed_terms_path. The signed certificate is produced
      // out-of-band by compliance_archive (PDF render + Dropbox mirror), so a transient failure
      // there is not the buyer's fault, is not a privacy risk, and blocking on it would take a
      // customer's ability to trade away for an operational fault of ours. It is repaired in the
      // background instead, so the evidence still lands and the gap stays visible.
      // (Enforced by the account-rule gate above since 14 Sep 2026.)
      if (!cust.signed_terms_path) {
        // Fire-and-forget repair. Never awaited: create_inquiry must not inherit the latency or
        // the failure mode of a PDF render and a Dropbox round-trip.
        try {
          const s = await getSecret('cred_fn_customer_api');
          fetch(`${SUPABASE_URL}/functions/v1/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: s, action: 'sign', kind: 'customer', email }) }).catch(() => { /* best effort */ });
        } catch (_e) { /* never blocks the buyer */ }
      }
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: recent } = await admin.from('inquiries').select('id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((recent || 0) >= INQUIRY_LIMIT_PER_HOUR) return J({ error: 'You have created many requests in a short time. Please try again later.' }, 429);
      const drawing = body.drawing && typeof body.drawing === 'object' ? body.drawing : null;
      let boqObj = drawing?.boq && typeof drawing.boq === 'object' ? drawing.boq : null;
      const briefSource = drawing ? (['drawing','quotation','boq'].includes(String(drawing.brief_source)) ? String(drawing.brief_source) : 'drawing') : null;
      let intake: any = null;
      if (body.intake_id) { const { data: it } = await admin.from('inquiry_intake').select('*').eq('id', String(body.intake_id)).maybeSingle(); if (it && it.email === email && it.status === 'ready') intake = it; }
      // INTAKE GATE BYPASS (27 Jul 2026). The mandatory intake used to be waived whenever the
      // CALLER posted a drawing object carrying a one-line boq array — a body the client builds
      // and can therefore forge, so { drawing: { boq: { boq: [{}] } } } skipped the questions
      // entirely and suppliers got briefs with no scope, quantity or emirate. The only bypass now
      // is a real, server-side inquiry_intake row owned by this customer and marked 'ready'
      // (resolved just above). A drawing still enriches the brief; it no longer replaces it.
      if (!intake) return J({ error: 'intake_required', message: 'Please answer a few quick questions so suppliers can quote accurately.' }, 428);
      const briefObj = intake?.brief && typeof intake.brief === 'object' ? intake.brief : null;
      let category = String(body.category || '').trim();
      if (!category && intake?.category) category = String(intake.category).trim();
      if (!category && boqObj?.category) category = String(boqObj.category).trim();
      const raw = String(body.raw_input || (intake?.raw_input || '')).slice(0, 4000);
      let summary = String(body.summary || '').slice(0, 500);
      if (!summary && briefObj?.summary) summary = String(briefObj.summary).slice(0, 500);
      if (!summary && boqObj?.summary) summary = String(boqObj.summary).slice(0, 500);
      if (!category) { const dd = detect(raw + ' ' + summary); category = dd.category || 'general'; }
      const emirate = body.emirate || (briefObj?.emirate || null) || null;
      const specIn = body.spec && typeof body.spec === 'object' ? body.spec : {};
      const spec = (briefObj?.details && typeof briefObj.details === 'object') ? { ...briefObj.details, ...specIn } : specIn;
      const budget = (body.budget ? String(body.budget) : (briefObj?.budget ? String(briefObj.budget) : '')).slice(0, 80) || null;
      // THE SALES ENGINEER'S QUESTIONS GATE THE POST (founder, 14 Sep 2026: "do you require a warranty?
      // do you require installation? do you have specific material in mind ... our job is to ask").
      // inquiry_intake only marks an intake ready once they are answered; this re-checks the stored
      // answers on the server, because a ready intake from before this change, or a body that edits
      // them, must not post a request whose baseline is missing. Edits from the summary card are
      // parsed again here (applyEdits); the browser's reading of them is never trusted. The answers go
      // into spec, so the existing identity scrub (spec_masked, scrubDeep) covers them and suppliers
      // read them with the rest of the brief (docs/contracts/intake_answers.md).
      const reqCategory = String(briefObj?.requirements?.category || intake?.category || category);
      let reqStored: any = briefObj?.requirements ?? null;
      if (body.requirement_edits && typeof body.requirement_edits === 'object' && !Array.isArray(body.requirement_edits) && Object.keys(body.requirement_edits).length) {
        const ed = applyEdits(reqCategory, reqStored, body.requirement_edits, new Date());
        if (ed.invalid.length) return J({ error: 'requirements_invalid', keys: ed.invalid, message: 'One of your changes could not be read. Pick one of the options instead.' }, 422);
        reqStored = ed.stored;
      }
      const reqCheck = validateStored(reqCategory, reqStored);
      if (!reqCheck.ok) return J({ error: 'requirements_incomplete', missing: reqCheck.missing, message: 'A few quick questions are still open: materials, installation, warranty or the date you need it by.' }, 428);
      spec.customer_requirements = reqStored;
      const scope_type = ['single','multi','turnkey'].includes(String(body.scope_type)) ? String(body.scope_type) : 'single';
      const tradesIn = Array.isArray(body.trades) ? body.trades.map((t: any) => String(t).toLowerCase()).filter(Boolean) : [];
      const d = detect(raw + ' ' + summary + ' ' + Object.values(spec).join(' '));
      const base = d.keywords.length ? d.keywords : (KW[category] || []);
      let keywords = Array.from(new Set([...base, category, ...tradesIn]));
      if (Array.isArray(boqObj?.keywords)) keywords = Array.from(new Set([...keywords, ...boqObj.keywords.map((s: any) => String(s).toLowerCase())]));
      keywords = keywords.slice(0, 30);
      const drawingPath = drawing?.drawing_file_path ? String(drawing.drawing_file_path) : null;
      const drawingName = drawing?.drawing_file_name ? String(drawing.drawing_file_name).slice(0, 180) : null;
      // Never trust drawing.drawing_redacted_paths from the body — see resolveRedactedPaths above.
      const rr = await resolveRedactedPaths(String(cust.id), String(user.id || ''), drawing);
      if ('err' in rr) return J(rr.err, rr.status);
      const drawingRedacted = rr.paths.length ? rr.paths.slice(0, 24) : null;
      // `tradesIn` arrives from the request body, so Set<unknown> is what TypeScript infers and
      // every downstream use of a trade - labelize(tr), KW[tr], category: tr - was an error.
      // Coercing here rather than casting at each use means a non-string trade is normalised once,
      // at the boundary, instead of being asserted away four times further down.
      const tradeStrings: string[] = (Array.isArray(tradesIn) ? tradesIn : []).map((t: unknown) => String(t ?? '').trim()).filter((s: string) => s.length > 0);
      const distinctTrades: string[] = Array.from(new Set<string>(tradeStrings)).slice(0, 6);
      const wantSplit = scope_type === 'multi' && distinctTrades.length > 1;
      const wantTurnkey = scope_type === 'turnkey';
      // THE ANONYMITY GATE (founder, 14 Sep 2026): "any info related to the client name / project
      // details contact info or anything that could let the supplier know who is the customer need to
      // be removed before sharing the drawings" — "the same applies for boq's". The BOQ is stored
      // ONLY after _shared/anonymise has removed this customer's own name, email, phone, project and
      // file name wherever they appear, plus plot / Makani / address / permit patterns, and a residual
      // scan found nothing. A BOQ that still identifies the customer is HELD: not stored on the RFQ,
      // recorded as a 'boq_held' run so it is visible, and never sent. It does not fail open.
      // THE DRAWING'S OPEN LINES ARE SETTLED AND RECORDED HERE (14 Sep 2026, _shared/boq_open_lines).
      // The sales engineer asked the customer to confirm our count; whatever is true at Send is the
      // outcome — confirmed, adjusted, not sure, or unanswered (the window closes when the customer
      // sends). Lines nobody confirmed go out as "estimated from drawing, supplier to verify
      // take-off", and the outcome is recorded on the inquiry, so nothing is silently assumed.
      if (boqObj && Array.isArray(boqObj.boq)) {
        const open = openLines(boqObj.boq);
        if (open.length) {
          const asked = briefObj?.boq_check && typeof briefObj.boq_check === 'object' ? briefObj.boq_check as BoqCheck : null;
          const outcome: BoqCheck = asked && asked.status !== 'asked' ? asked : { status: 'unanswered', asked_at: asked?.asked_at, answered_at: null, lines: open };
          boqObj = { ...boqObj, boq: settleLines(boqObj.boq, outcome) };
          spec.boq_check = { status: outcome.status, asked_at: outcome.asked_at || null, answered_at: outcome.answered_at || null, answer: outcome.answer || null, adjustments: outcome.adjustments || {}, lines: open, recorded_at: new Date().toISOString(), recorded_by: 'sales_engineer' };
        }
      }
      if (boqObj) {
        let projName = '';
        { const want = String(body.project_id || briefObj?.project_id || '').trim();
          if (want) { const { data: pj } = await admin.from('projects').select('name').eq('id', want).eq('customer_id', cust.id).maybeSingle(); projName = pj?.name ? String(pj.name) : ''; } }
        const seeds = seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', project: projName, extra: [drawingName || ''] });
        const gate = redactBoq(boqObj, seeds);
        if (gate.held) {
          try { await admin.from('drawing_redaction_runs').insert({ customer_id: cust.id, owner_email: email, source_path: drawingPath, output_paths: [], pages_in: 0, pages_out: 0, skipped: 0, status: 'boq_held', pages_verified: 0, verify_failed: 1, verify_detail: { reasons: gate.reasons.slice(0, 20) } }); } catch (_e) { /* the hold stands even if its record fails */ }
          boqObj = null;
        } else boqObj = gate.boq;
      }
      const drawCols = { drawing_file_path: drawingPath, drawing_file_name: drawingName, drawing_redacted_paths: drawingRedacted, boq: boqObj, boq_confidence: boqObj?.confidence || null };

      // ── §7: THREE THINGS THE ASSISTANT EXTRACTED AND THIS ROUTINE THREW AWAY ────────────────────
      // The intake contract emits brief.quantity and brief.timeline — measured true — and the
      // ready-brief card shows the timeline to the customer before they press Send. Then
      // create_inquiry merged ONLY brief.details into inquiries.spec, so both survived just for the
      // minority of categories whose checklist happens to define a canonical key for them
      // (quantity: 30 of 56, timeline: 3 of 56). Everywhere else the customer confirmed a number
      // and the supplier never saw it.
      //
      // quantity is merged into spec under the canonical key and NEVER overwrites an answer the
      // customer gave explicitly: a checklist answer is stated, brief.quantity is inferred, and an
      // inference must not overwrite a statement.
      const briefQty = briefObj?.quantity;
      if (briefQty != null && String(briefQty).trim() !== '' && !('quantity' in spec)) spec.quantity = briefQty;
      // The window as stated, plus a resolved date when one can be resolved. Suppliers quote
      // against the phrase; the portal sorts against the date. `required_by` stays null rather than
      // guessing — "as soon as possible" is a real answer and is not a date.
      const timelineTxt = briefObj?.timeline != null ? String(briefObj.timeline).slice(0, 120) : (reqStored?.required_by?.text ? String(reqStored.required_by.text).slice(0, 120) : null);
      const isoDay = /^\d{4}-\d{2}-\d{2}$/;
      const requiredBy = (() => {
        // The date the customer gave the sales engineer is the customer's own answer and wins.
        const asked = String(reqStored?.required_by?.date || '');
        if (isoDay.test(asked)) return asked;
        const t = String(briefObj?.required_by || '').trim();
        if (isoDay.test(t)) return t;
        // The duration is found ANYWHERE in the phrase, not only at its start. Real answers read
        // "Installation required within 8 weeks of order" — an anchored match resolves that to
        // null, which is a date silently lost rather than a date honestly absent.
        const m = /(\d{1,4})\s*(day|days|week|weeks|month|months)\b/i.exec(String(timelineTxt || ''));
        if (!m) return null;
        const n = Number(m[1]); if (!Number.isFinite(n) || n <= 0 || n > 3650) return null;
        const mult = /week/i.test(m[2]) ? 7 : /month/i.test(m[2]) ? 30 : 1;
        return new Date(Date.now() + n * mult * 86400e3).toISOString().slice(0, 10);
      })();
      // §6: the floor this scope sits on, when the brief or the caller names one.
      const floorTxt = (body.floor ?? briefObj?.floor) != null ? String(body.floor ?? briefObj?.floor).slice(0, 40) : null;
      // §3 assistant-infers-project: the project the RFQ belongs to. Verified as THIS customer's —
      // a project_id from the request body is caller-supplied and must never link an RFQ to
      // somebody else's project.
      let projectId: string | null = null;
      { const want = String(body.project_id || briefObj?.project_id || '').trim();
        if (want) { const { data: pj } = await admin.from('projects').select('id').eq('id', want).eq('customer_id', cust.id).maybeSingle(); projectId = pj ? String(pj.id) : null; } }
      // §7 rfq-certificates: the category's required certificates and approvals, COPIED onto the
      // RFQ at creation so the supplier quoting it and the customer reading it see the same list,
      // and so a later edit to the category cannot change what an RFQ was quoted against.
      const checklistFor = async (cat: string) => {
        if (!cat) return null;
        try {
          const { data: cs } = await admin.from('category_specs').select('compliance_checklist').eq('category', cat).maybeSingle();
          const cl = cs?.compliance_checklist;
          const list = Array.isArray(cl?.list) ? cl.list : (Array.isArray(cl) ? cl : null);
          return list && list.length ? { list, source: 'category_specs', category: cat, attached_at: new Date().toISOString() } : null;
        } catch (_e) { return null; }
      };
      const briefCols = { floor: floorTxt, delivery_window: timelineTxt, required_by: requiredBy, project_id: projectId };

      if (wantSplit) {
        // ALL OR NOTHING (_shared/inquiry_split.ts; review of #653). Parent and every child are saved
        // first; any failed child removes what was saved and the post fails naming the trades, so no
        // supplier is invited to a partial request and no parent lists a trade that never went out.
        // Suppliers are matched and notified only once every child exists.
        const childSummary = (tr: string) => ((summary ? summary + ' — ' : '') + labelize(tr) + ' works (part of a combined project)').slice(0, 500);
        const childKw = (tr: string) => Array.from(new Set([...(KW[tr] || []), tr])).slice(0, 30);
        const parentIdRef = { id: '' };
        const res = await splitInquiry(distinctTrades, {
          insertParent: async () => {
            const { data, error } = await admin.from('inquiries').insert({ customer_id: cust.id, category: 'combined', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'split', budget, scope_type: 'multi', trades: distinctTrades, brief_source: briefSource, ...drawCols, ...briefCols }).select('id').maybeSingle();
            return error || !data ? null : String(data.id);
          },
          insertChild: async (tr) => {
            const { data, error } = await admin.from('inquiries').insert({ customer_id: cust.id, parent_inquiry_id: parentIdRef.id, category: tr, emirate, role_needed: 'supplier', raw_input: raw, spec, summary: childSummary(tr), keywords: childKw(tr), status: 'sent', budget, scope_type: 'single', trades: [tr], brief_source: briefSource, ...drawCols, ...briefCols, compliance_checklist: await checklistFor(tr) }).select('id').maybeSingle();
            return error || !data ? null : String(data.id);
          },
          deleteInquiries: async (ids) => {
            // Children reference the parent, so they go first. Scoped to this customer's rows.
            const kids = ids.filter((i) => i !== parentIdRef.id);
            if (kids.length) { const { error } = await admin.from('inquiries').delete().in('id', kids).eq('customer_id', cust.id); if (error) return false; }
            const { error } = await admin.from('inquiries').delete().eq('id', parentIdRef.id).eq('customer_id', cust.id);
            return !error;
          },
          notifyChild: async (id, tr) => {
            const tlabel = labelize(tr);
            const extra = ' This is the ' + tlabel + ' portion of a larger project — please quote for the ' + tlabel + ' works only; other trades are handled separately.' + (boqObj ? (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached.' : ' A redacted drawing is attached.') : '');
            // Each child is ONE trade and is routed like any single request: through the capability
            // matcher (sales_engineer.match), not keyword matching. Measured 14 Sep 2026: split children
            // went to match_suppliers_kw, which matched a registered aluminium supplier and no one for
            // the glass child, while the capability router knows glass as glazing.
            const { matches } = await matchAndNotify(id, { category: tr, emirate, summary: childSummary(tr), budget, extra: extra + supplierLine(reqStored) });
            return matches;
          },
          finding: async (detail) => {
            console.error('split compensation failed', JSON.stringify(detail));
            try { await admin.rpc('fn_emit', { p_event_type: 'it.finding', p_entity_type: 'inquiry', p_entity_id: String(detail.parent_id || ''), p_actor: 'sales_engineer', p_payload: detail }); } catch (_e) { /* logged above */ }
          },
        }, (id) => { parentIdRef.id = id; });
        if (!res.ok) {
          return J({ error: 'split_failed', code: 'split_failed', failed_trades: res.failed_trades, ...(res.cleanup_failed ? { cleanup_failed: true } : {}),
            message: 'Your request could not be sent to every trade (' + res.failed_trades.map(labelize).join(', ') + '). Nothing was sent — please try again.' }, 500);
        }
        if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
        // ONE ANSWER SHAPE (_shared/inquiry_posted.ts): inquiry_id is the parent, the stable id of
        // what the customer asked for; child_ids / quotable_ids are what suppliers quote on.
        return J(postedSplit(res.parentId, res.children.map((c) => ({ ...c, label: labelize(c.trade) })), distinctTrades));
      }

      if (wantTurnkey) {
        const tkKeywords = Array.from(new Set([...keywords, 'fitout', 'fit out', 'fit-out', 'turnkey', 'interior', 'renovation', 'decoration', ...distinctTrades])).slice(0, 40);
        const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, category: 'fitout', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords: tkKeywords, status: 'sent', budget, scope_type: 'turnkey', trades: distinctTrades.length ? distinctTrades : (tradesIn.length ? tradesIn : null), brief_source: briefSource, ...drawCols, ...briefCols, compliance_checklist: await checklistFor('fitout') }).select('id').maybeSingle();
        if (e1) return J({ error: e1.message }, 500);
        if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
        const tradeList = distinctTrades.map(labelize).join(', ');
        const extra = (tradeList ? ' Combined turnkey scope covering: ' + tradeList + '.' : '') + (boqObj ? (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached.' : ' A redacted drawing is attached.') : '');
        const { matches } = await matchAndNotify(String(inq!.id), { category: 'fitout', emirate, summary, budget, extra: extra + supplierLine(reqStored) });
        return J(postedSingle(String(inq!.id), 'turnkey', matches));
      }

      const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, category, emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'sent', budget, scope_type: 'single', trades: tradesIn.length ? tradesIn : null, brief_source: briefSource, ...drawCols, ...briefCols, compliance_checklist: await checklistFor(category) }).select('id').maybeSingle();
      if (e1) return J({ error: e1.message }, 500);
      if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
      const extra = boqObj ? (briefSource === 'quotation' ? ' A scope (anonymized from the customer’s own quotation, prices removed) is attached.' : (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached (quantities as the customer wrote them, prices removed).' : ' A drawing with a draft bill of quantities is attached.')) : '';
      const { matches, routing } = await matchAndNotify(String(inq!.id), { category, emirate, summary, budget, extra: extra + supplierLine(reqStored) });
      return J(postedSingle(String(inq!.id), 'single', matches, routing));
    }

    // THE CUSTOMER'S FOLLOW-UP REACHES THE RFQ (website audit 14 Sep 2026, BROKEN). "Ask the
    // assistant about this request" posted to inquiry_intake, which ignores inquiry_id, so every
    // follow-up became an orphan intake draft and no supplier ever saw it. A follow-up is now an
    // addendum: stored on public.rfq_clarification as a born-answered note (the same table the
    // pre-reveal Q&A uses, so a supplier reads one list), scrubbed of contact details and the
    // customer's own name, and emailed to every matched supplier through the same queue the
    // original invitation used.
    if (action === 'rfq_note') {
      const iid = String(body.inquiry_id || '');
      const raw = String(body.text || '').trim().slice(0, 1500);
      if (!iid || raw.length < 2) return J({ error: 'text_required' }, 400);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,status').eq('id', iid).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'not_your_inquiry' }, 403);
      if (['cancelled', 'closed', 'completed'].includes(String(inq.status))) return J({ error: 'inquiry_closed' }, 409);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: recentNotes } = await admin.from('rfq_clarification').select('id', { count: 'exact', head: true }).eq('inquiry_id', iid).eq('kind', 'note').gte('asked_at', hourAgo);
      if ((recentNotes || 0) >= 10) return J({ error: 'too_many_notes' }, 429);
      const hits: string[] = [];
      const clean = String(scrubIdentity(raw, cust.full_name, hits) || '').trim();
      if (clean.replace(/\[removed\]/g, '').trim().length < 2) return J({ error: 'text_required' }, 400);
      const nowIso = new Date().toISOString();
      const { data: ins, error: nerr } = await admin.from('rfq_clarification').insert({ inquiry_id: iid, supplier_id: null, kind: 'note', answer: clean, answered_at: nowIso, source: 'rfq_note' }).select('id').single();
      if (nerr || !ins) return J({ error: 'save_failed' }, 500);
      const { data: ms } = await admin.from('inquiry_matches').select('supplier_id').eq('inquiry_id', iid);
      const sids = [...new Set((ms || []).map((m: { supplier_id: number }) => Number(m.supplier_id)).filter(Boolean))];
      let notified = 0;
      if (sids.length) {
        const { data: ls } = await admin.from('leads').select('id,email,claimed_by,banned').in('id', sids);
        const rows = (ls || []).filter((l: any) => l.banned !== true).map((l: any) => ({ id: l.id, to: String(l.claimed_by || l.email || '') })).filter((l) => /@/.test(l.to))
          .map((l) => ({ type: 'rfq_addendum', to_email: l.to, to_role: 'supplier', lead_id: l.id, inquiry_id: iid, subject: 'The customer added detail to a request you were invited to quote',
            body: 'The customer added this to the ' + (inq.category || '') + (inq.emirate ? ' job in ' + inq.emirate : ' job') + ' you were invited to quote:\n\n"' + clean + '"\n\nIt is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.' }));
        await queueNotifications(rows);
        notified = rows.length;
      }
      return J({ ok: true, id: ins.id, text: clean, notified, removed: hits.length });
    }

    if (action === 'my_inquiries') {
      // rfq_no is the human reference (spec §8, "RFQ #88291"). The primary key is a uuid, which is
      // not a number a customer can read out on the phone or quote in an email to a supplier.
      // §7 spec, §8 stage, §9 applied filters. THREE THINGS WERE COMPUTED AND NEVER SERVED:
      //   pipeline_stage/stage_changed_at — recorded on every inquiry, while the browser derived
      //     the stage from quotes.length and anyRevealed. A guess sitting on top of a fact.
      //   routing — the filters the matcher actually applied (job_type, primary_trade, reasoning).
      //     Spec §9 shows them back to the customer; they never left the database.
      //   floor / required_by / delivery_window — added 7 Aug for §6 and §7.
      const cols = 'id,category,emirate,summary,spec,status,created_at,budget,scope_type,brief_source,drawing_file_path,drawing_file_name,boq,boq_confidence,hired_supplier_id,outcome,parent_inquiry_id,trades,rfq_no,pipeline_stage,stage_changed_at,routing,floor,required_by,delivery_window,project_id';
      // ONE READ AT A TIME WAS THE OVERVIEW'S CRITICAL PATH (15 Sep 2026). Measured with the e2e
      // harness's per-call timing on production (smoke run 34888342875 and a probe of 8 page loads):
      // the six dashboard calls already start together, and my_inquiries answers last (1.40-1.61 s
      // warm) because it made eleven database reads one after another. Each read below waits only for
      // what it needs, so they run in four waves: [cfg, requests, sales, reviews] -> children ->
      // [quotes, matches, open offers, refunds] -> [supplier rows, supplier performance].
      // The answer is unchanged; only the waiting is.
      const [cfg, { data: tops }, txRes, { data: revs }] = await Promise.all([
        getCfg(),
        admin.from('inquiries').select(cols).eq('customer_id', cust.id).is('parent_inquiry_id', null).order('created_at', { ascending: false }).limit(25),
        admin.from('transactions').select('id,quote_id,revealed_at,supplier_ack_at,refund_status,refund_deadline,total_charged').eq('customer_id', cust.id),
        admin.from('reviews').select('transaction_id').eq('customer_id', cust.id),
      ]);
      const topIds = (tops || []).map((i) => i.id);
      let kids: any[] = [];
      if (topIds.length) { const { data: ch } = await admin.from('inquiries').select(cols).in('parent_inquiry_id', topIds).order('created_at', { ascending: true }); kids = ch || []; }
      const kidsByParent: Record<string, any[]> = {};
      for (const k of kids) { (kidsByParent[String(k.parent_inquiry_id)] ||= []).push(k); }
      const ids = [...topIds, ...kids.map((k) => k.id)];
      const txs: any[] = ids.length ? (txRes.data || []) : [];
      if (ids.length && txRes.error) console.error('my_inquiries: transactions read failed —', txRes.error.message);
      const txIds = txs.map((t) => t.id);
      const [qsRes, msRes, sosRes, rfsRes] = await Promise.all([
        ids.length ? admin.from('quotes').select('id,inquiry_id,supplier_id,option_no,quote_amount,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,exclusions,source,original_file_path,created_at,expires_at').in('inquiry_id', ids).neq('status', 'draft').order('quote_amount', { ascending: true }) : null,
        ids.length ? admin.from('inquiry_matches').select('inquiry_id,supplier_id,similarity,match_reason').in('inquiry_id', ids) : null,
        ids.length ? admin.from('spec_alternative_offer').select('id,inquiry_id,line_no,item,attr,label_en,label_ar,requested,alternatives,state,reply_by').in('inquiry_id', ids).eq('customer_id', cust.id).eq('state', 'open').order('opened_at', { ascending: true }) : null,
        txIds.length ? admin.from('refunds').select('id,transaction_id,refund_decision_id').in('transaction_id', txIds) : null,
      ]);
      const quotes: Record<string, any>[] = qsRes?.data || [];
      // How many suppliers the request actually reached. Without this the portal cannot tell
      // "waiting for quotes" apart from "this reached nobody", and shows hope either way.
      const matchedBy: Record<string, number> = {};
      // WHY a given supplier was contacted. inquiry_matches.match_reason is the ONLY place the
      // system records it; this read kept a COUNT and threw the text away, so the only surface
      // rendering a reason was OsxShell — /os, staff-only. It is now served, keyed by supplier, and
      // REVEAL-GATED in the row mapper below.
      //
      // The gate is not optional. route_inquiry builds its candidate list as `#<id> — <Company
      // Name>` (route_inquiry/index.ts:305) and asks the model for a free-text reason per
      // candidate, so a reason may name the supplier outright. Emitting it pre-reveal would hand
      // over the identity the reveal fee exists to sell.
      //
      // THE MATCH PERCENTAGE IS NOW SERVED. It used not to be, and the reason was correct at the
      // time: both writer sites passed the literal null, so every row held null in every
      // environment and a "% match" here would have been invented rather than surfaced. Both
      // writers now store the score their matcher actually computed, normalised to 0..1 (see
      // matchAndNotify above), so there is a real number to serve.
      //
      // NOT REVEAL-GATED, unlike match_reason. A percentage names nobody — it is a number about the
      // fit between a brief and an anonymous quote — so it costs the reveal fee nothing. The reason
      // text is gated because route_inquiry builds its candidate list as `#<id> — <Company Name>`
      // (route_inquiry/index.ts) and asks the model for free-text per candidate, so a reason may
      // name the supplier outright and emitting it pre-reveal would hand over the identity the
      // reveal fee exists to sell.
      //
      // NULL MEANS NOT SCORED AND MUST RENDER AS ABSENT. A match written on the legacy
      // AI-adjudicator path carries no number at all; serving 0 there would tell the customer this
      // supplier is a 0% fit, which is a different and false claim. null travels as null.
      const reasonBySup: Record<string, string> = {};
      const pctBySup: Record<string, number> = {};
      const bestPct: Record<string, number> = {};
      try { const ms = msRes?.data; for (const m of (ms || [])) { matchedBy[String(m.inquiry_id)] = (matchedBy[String(m.inquiry_id)] || 0) + 1; if (m.match_reason) reasonBySup[String(m.inquiry_id) + ':' + String(m.supplier_id)] = String(m.match_reason); const sim = m.similarity == null ? null : Number(m.similarity); if (sim != null && Number.isFinite(sim)) { const pct = Math.round(sim * 100); pctBySup[String(m.inquiry_id) + ':' + String(m.supplier_id)] = pct; if (pct > (bestPct[String(m.inquiry_id)] ?? -1)) bestPct[String(m.inquiry_id)] = pct; } } } catch (_e) { /* */ }
      const supIds = [...new Set(quotes.map((q) => q.supplier_id))];
      const supMeta: Record<string, any> = {};
      if (supIds.length) { const [{ data: ls }, { data: perf }] = await Promise.all([admin.from('leads').select('id,company_name,app_rating,app_reviews,emirate,verified,founded_year,rv_response_rate,rv_reveals').in('id', supIds), admin.from('supplier_perf').select('supplier_id,won,win_rate').in('supplier_id', supIds)]); const perfById: Record<string, any> = {}; for (const p of (perf||[])) perfById[String(p.supplier_id)] = p; const _yr = new Date().getFullYear(); for (const l of ls || []) supMeta[String(l.id)] = { r: ratingOf(l), name: l.company_name || null, emirate: l.emirate, verified: !!l.verified, years_active: l.founded_year ? Math.max(0, _yr - Number(l.founded_year)) : null, jobs_won: (perfById[String(l.id)]||{}).won ?? 0, win_rate: (perfById[String(l.id)]||{}).win_rate ?? null, rr: Number(l.rv_reveals) > 0 && l.rv_response_rate != null ? Number(l.rv_response_rate) : null }; }
      const revealedQ = new Set<string>(); const txByQuote: Record<string, string> = {}; const revealAtByQuote: Record<string, string | null> = {};
      // 21 Sep 2026 (customer audit, finding 17): the portal said "AED 778 paid" for a card charged
      // AED 816.37 — it printed the 3% fee, not transactions.total_charged (fee + card processing).
      const chargedByQuote: Record<string, number | null> = {};
      // public.transactions HAS NO created_at COLUMN - in staging or in production. Selecting it
      // made PostgREST answer 400, so `txs` came back null, `for (const t of txs || [])` iterated
      // nothing, and revealedQ stayed empty: NO QUOTE WAS EVER MARKED REVEALED. The customer paid
      // the reveal fee, `reveal` wrote the transactions row, and the portal went on showing
      // "Supplier A" with banded ratings and supplier_ref null, forever. Found 5 Aug 2026 by the
      // first fixture that ever created a transactions row - the journey never reveals, so a green
      // 37/37 said nothing about it. revealed_at is the column that exists; there is no fallback.
      // The Reveal Guarantee clock on the customer's own job needs the facts the refund ladder runs
      // on — when they paid, whether the supplier acknowledged, and any refund already in motion.
      // All four are columns on the sale; nothing is inferred.
      const guaranteeByQuote: Record<string, Record<string, unknown>> = {};
      if (ids.length) { for (const t of txs) { revealedQ.add(String(t.quote_id)); txByQuote[String(t.quote_id)] = String(t.id); revealAtByQuote[String(t.quote_id)] = t.revealed_at || null; chargedByQuote[String(t.quote_id)] = t.total_charged == null ? null : Number(t.total_charged); guaranteeByQuote[String(t.quote_id)] = { revealed_at: t.revealed_at || null, supplier_ack_at: t.supplier_ack_at || null, refund_status: t.refund_status || null, refund_deadline: t.refund_deadline || null }; }
        // D4 (14 Sep 2026): the refund case and the chief executive's decision behind it, so the
        // customer can quote both. refunds.refund_decision_id references ceo_approval(decision_id);
        // it is null until the decision exists, and the portal says "awaiting" rather than inventing one.
        if (txIds.length) { const rfs = rfsRes?.data; const qByTx: Record<string, string> = {}; for (const [qk, tk] of Object.entries(txByQuote)) qByTx[tk] = qk; for (const rf of rfs || []) { const g = guaranteeByQuote[qByTx[String(rf.transaction_id)]]; if (g) { g.refund_ref = refundRef(rf.id); g.decision_ref = rf.refund_decision_id ? 'QD-D-' + rf.refund_decision_id : null; } } } }
      const ratedTx = new Set((revs || []).map((r) => String(r.transaction_id)));
      // NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321): the open question, with its
      // alternatives as values and supplier COUNTS only (the table cannot hold anything else).
      const offersBy: Record<string, unknown[]> = {};
      if (ids.length) { const sos = sosRes?.data; for (const s of sos || []) { const { inquiry_id, ...rest } = s as Record<string, unknown>; (offersBy[String(inquiry_id)] ||= []).push(rest); } }
      const now = new Date();
      // Pre-reveal quote rows carry BANDS only (see ratingBand/reviewCountBand/yearsBand above);
      // rating_source, emirate and win_rate are set to undefined so JSON.stringify omits the keys
      // outright rather than shipping a null the client could still reason about. Revealed quotes
      // — a transactions row exists for that quote_id — keep the exact values, unchanged.
      // §9 THE APPLIED FILTERS, WITHOUT THE FREE TEXT. inquiries.routing records what the matcher
      // did: job_type, primary_trade, emirate and how many suppliers it evaluated. It ALSO records
      // `reasoning`, which route_inquiry generates against a candidate list built as
      // `#<id> — <Company Name>` and can therefore name a supplier outright — the same hazard that
      // makes match_reason reveal-gated. The filters are shown back; the free text is not, and this
      // projection is why: serving routing whole would leak the identity the reveal fee sells.
      const appliedFilters = (r: any) => {
        if (!r || typeof r !== 'object') return null;
        const n = Array.isArray(r.evaluated) ? r.evaluated.length : (Number.isFinite(Number(r.evaluated)) ? Number(r.evaluated) : null);
        const f = { job_type: r.job_type ?? null, primary_trade: r.primary_trade ?? null, emirate: r.emirate ?? null, evaluated: n };
        return (f.job_type || f.primary_trade || f.emirate || f.evaluated != null) ? f : null;
      };
      const mapRow = async (i: any) => ({ id: i.id, rfq_no: i.rfq_no ?? null, category: i.category, emirate: i.emirate, summary: i.summary, spec: i.spec, status: i.status, created_at: i.created_at,
        // §8: the stage the LIFECYCLE recorded, not one the browser guessed from quotes.length.
        pipeline_stage: i.pipeline_stage ?? null, stage_changed_at: i.stage_changed_at ?? null,
        applied_filters: appliedFilters(i.routing),
        // §6/§7: the floor this RFQ is scoped to, and the delivery window the assistant extracted.
        floor: i.floor ?? null, required_by: i.required_by ?? null, delivery_window: i.delivery_window ?? null,
        project_id: i.project_id ?? null, budget: i.budget || null, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: i.boq || null, boq_confidence: i.boq_confidence || null, drawing_file_name: i.drawing_file_name || null, hired_supplier_id: i.hired_supplier_id ?? null, outcome: i.outcome ?? null, trades: i.trades || null, matched_suppliers: matchedBy[String(i.id)] || 0, best_match_pct: bestPct[String(i.id)] ?? null, editable: (i.status === 'sent') && ((Date.now() - new Date(i.created_at).getTime()) < 24*3600e3), edit_minutes_left: (i.status === 'sent') ? Math.max(0, Math.round((60*60e3 - (Date.now() - new Date(i.created_at).getTime()))/60000)) : 0, drawing_file_url: await signedDrawing(i.drawing_file_path), spec_offers: offersBy[String(i.id)] || [], quotes: quotes.filter((q) => q.inquiry_id === i.id).map((q, idx, arr) => { const lab = labelQuotes(arr.map((x: any) => ({ id: String(x.id), supplier_id: x.supplier_id, option_no: x.option_no }))).get(String(q.id)); const m = supMeta[String(q.supplier_id)] || {}; const r = m.r || {}; const revealed = revealedQ.has(String(q.id)); return { id: q.id, supplier_ref: revealed ? q.supplier_id : null, label: lab ? lab.en : 'Supplier ' + supplierLabel(idx), label_ar: lab ? lab.ar : null, option_no: q.option_no ?? 1, price: q.quote_amount, reveal_fee: revealFee(Number(q.quote_amount), cfg), notes: q.notes, lead_time: q.lead_time, validity: q.validity, expires_at: q.expires_at ?? null, expired: q.expires_at ? (new Date(q.expires_at) < now) : false, payment_terms: q.payment_terms, warranty: q.warranty, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, source: q.source || 'form', has_original: !!q.original_file_path, status: q.status, revealed, revealed_at: revealAtByQuote[String(q.id)] || null, supplier_name: revealed ? (m.name ?? null) : undefined, total_charged: revealed ? (chargedByQuote[String(q.id)] ?? null) : undefined, guarantee: revealed ? (guaranteeByQuote[String(q.id)] || null) : undefined, rated: ratedTx.has(String(txByQuote[String(q.id)] || '')), rating: revealed ? (r.value ?? null) : ratingBand(r.value), rating_count: revealed ? (r.count ?? 0) : reviewCountBand(r.count), rating_source: revealed ? (r.source || null) : undefined, match_reason: revealed ? (reasonBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null) : undefined, match_pct: pctBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null, emirate: revealed ? (m.emirate ?? null) : undefined, verified: m.verified ?? false, years_active: revealed ? (m.years_active ?? null) : yearsBand(m.years_active), jobs_won: m.jobs_won ?? 0, win_rate: revealed ? (m.win_rate ?? null) : undefined,
          // W9 badges: only measured facts, null when absent. Pre-reveal the response rate is floored
          // to a 10% band and the rating stays out (the banded rating above already shows it), so a
          // badge can never be an exact fingerprint of one company.
          badges: { licence_verified: m.verified === true, response_rate: m.rr == null ? null : (revealed ? m.rr : Math.floor((m.rr <= 1 ? m.rr : m.rr / 100) * 10) / 10), jobs_completed: Number(m.jobs_won) > 0 ? Number(m.jobs_won) : null, rating: revealed && typeof r.value === 'number' ? r.value : null } }; }) });
      // EACH mapRow AWAITS A STORAGE ROUND TRIP (signedDrawing) THAT THE OLD LOOP SERIALISED. Up to
      // 25 top-level rows plus every child were signed one at a time — an N+1 sequential-await chain
      // on the Overview's critical path (e2e run 6, 14 Sep 2026: 6.5s vs run 5's 1.6-1.8s, growing
      // with the number of ZZ DEMO rows that carry a drawing). None of these rows' signed URLs depend
      // on each other, so they run together; wall time is now the slowest ONE, not the sum.
      const out = await Promise.all((tops || []).map(async (i) => {
        // mapRow returns an object literal, so its inferred type has no is_combined / child_count /
        // children. The combined-project decoration below is genuinely dynamic - only split parents
        // get it - so the row is typed as an open record rather than the literal's shape.
        const row: Record<string, any> = await mapRow(i);
        const ch = kidsByParent[String(i.id)];
        if (ch && ch.length) { row.is_combined = true; row.child_count = ch.length; row.children = await Promise.all(ch.map((c: any) => mapRow(c))); }
        return row;
      }));
      // `locale` added 5 Aug 2026. customers.locale was stored and, from the portal's point of
      // view, never served: the brief called it "stored and never served", which measurement shows
      // is not quite right - `me` returns the whole customer row via select('*'), locale included.
      // But THE PORTAL NEVER CALLS `me`. It calls `kyc state` and this action, so the field was on
      // the wire only where nothing was listening, and CustomerPortal fell back to
      // localStorage['qd-lang'] and the NEXT_LOCALE cookie. A customer who set Arabic on one device
      // got English on the next, and the Arabic journey exercised a path the portal could not reach.
      // promo is always false: there is no promotional reveal rate (founder, 6 Sep 2026); the key stays so no reader breaks.
      // The ladder's numbers, from the same row the refund sweep and the supplier email read, so the
      // portal's timeline cannot drift from what is actually enforced (5 / 3 / 7-14 on 14 Sep 2026).
      const pc = cfg as unknown as Record<string, number | null | undefined>;
      const guarantee_terms = { window_days: pc.refund_window_working_days ?? null, chase_after_days: pc.chase_after_working_days ?? null, bank_min_days: pc.bank_settlement_working_days_min ?? null, bank_max_days: pc.bank_settlement_working_days_max ?? null };
      return J({ inquiries: out, locale: cust.locale || null, promo: false, guarantee_terms });
    }

    // NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321): the customer answers in the portal.
    // The routine records it (owner check, open state, which option, when, channel 'portal', inquiry
    // closed on "no"); customer_support then confirms or apologises in the registered language.
    if (action === 'spec_offer_reply') {
      const offerId = Number(body.offer_id); const choice = String(body.choice || '').trim();
      if (!Number.isFinite(offerId) || offerId <= 0 || !choice) return J({ error: 'bad_request' }, 400);
      const { data: res, error: aErr } = await admin.rpc('fn_spec_offer_answer', { p_offer: offerId, p_customer: cust.id, p_choice: choice, p_channel: 'portal' });
      if (aErr) { console.error('spec_offer_reply:', aErr.message); return J({ error: 'spec_offer_failed' }, 500); }
      if (!res?.ok) return J({ error: res?.error || 'spec_offer_failed', state: res?.state ?? null }, res?.error === 'not_your_offer' ? 403 : res?.error === 'not_found' ? 404 : 409);
      try {
        const { data: o } = await admin.from('spec_alternative_offer').select('id,inquiry_id,item,label_en,label_ar,requested,alternatives,accepted_value').eq('id', offerId).maybeSingle();
        const { data: c } = await admin.from('customers').select('email,locale').eq('id', cust.id).maybeSingle();
        const { data: inqRow } = await admin.from('inquiries').select('rfq_no').eq('id', String(res.inquiry_id)).maybeSingle();
        const lang = asLocale(c?.locale ?? cust.locale);
        const msg = res.state === 'accepted' ? acceptedMessage(o as OfferForText, lang, { rfqNo: inqRow?.rfq_no }) : apologyMessage(o as OfferForText, lang, 'declined', { rfqNo: inqRow?.rfq_no });
        const kind = res.state === 'accepted' ? 'accepted' : 'apology_declined';
        // customer_support asks and answers the alternatives question (finding SP-F-08, 22 Sep 2026;
        // the same change in sales_engineer/index.ts carries the reasoning). The `type` is unchanged.
        const base = { type: 'spec_offer_' + kind, kind: 'customer_support_spec_offer_' + kind, to_role: 'customer', inquiry_id: String(res.inquiry_id), subject: msg.subject, body: msg.body, status: 'queued', lang, requested_by: 'customer_support', sender: 'customer_support' };
        const rows: Record<string, unknown>[] = [];
        if (c?.email) rows.push({ ...base, channel: 'email', to_email: c.email, dedupe_key: `spec_offer:${offerId}:${kind}:email` });
        // WhatsApp consent is the confirmed WhatsApp number, nothing else (#322): the row names the customer by
        // email and the a03 trigger addresses it to their confirmed number, or records why it was not sent.
        if (c?.email) rows.push({ ...base, channel: 'whatsapp', to_email: c.email, dedupe_key: `spec_offer:${offerId}:${kind}:whatsapp` });
        const { data: sent } = rows.length ? await requestDelivery(admin, rows) : { data: [] };
        await admin.rpc('fn_spec_offer_mark', { p_offer: offerId, p_action: 'answered', p_notification_ids: (sent || []).map((d) => d.notification_id).filter((x) => typeof x === 'number') });
      } catch (e) { console.error('spec_offer_reply: confirmation not queued —', String((e as Error)?.message || e)); }
      return J({ ok: true, state: res.state, inquiry_closed: !!res.inquiry_closed });
    }

    if (action === 'compare_pdf') {
      const iid = String(body.inquiry_id || '');
      // THE REGISTERED LANGUAGE IS THE DEFAULT; THE BUTTON PRESSED IS THE DOCUMENT ASKED FOR.
      // 21 Sep 2026 (customer-portal journey audit): an English-registered customer on the Arabic
      // portal pressed the Arabic report and got English. The portal sends lang: docLang, and this line
      // read customers.locale only — the same defect quote_pdf had (finding 4) and was fixed for alone.
      // Every customer document now routes through documentLocale (prevented by
      // customer_api/arabic_documents.test.ts, which fails if any document action reads the locale alone).
      const lang = documentLocale(body.lang, cust.locale);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,category,summary,emirate').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      // Reuse the cached analysis when the quote set is unchanged; otherwise ask for a fresh one.
      let analysis: any = null;
      try {
        const got = await fetchCompareAnalysis(iid, lang);
        if (got.analysis) analysis = got.analysis; else return J({ error: got.error }, 200);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 502); }
      try {
        const { j, ref } = await buildComparePdf(analysis, inq, lang);
        if (j?.ok && j.url) return J({ ok: true, url: j.url, ref });
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    // W10: the comparison as a spreadsheet. Same ownership check, same rate limit and the same
    // quote_compare analysis as compare_pdf, rendered through the same compareTable().
    if (action === 'compare_csv') {
      const iid = String(body.inquiry_id || '');
      const lang = documentLocale(body.lang, cust.locale);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      let analysis: any = null;
      try {
        const got = await fetchCompareAnalysis(iid, lang);
        if (got.analysis) analysis = got.analysis; else return J({ error: got.error }, 200);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 502); }
      const side = compareTable(analysis, lang === 'ar');
      if (!side) return J({ error: 'comparison_unavailable' }, 200);
      return J({ ok: true, csv: toCsv(side.head, side.rows), filename: 'QD-' + jobNoOf(inq) + (lang === 'ar' ? '-مقارنة' : '-comparison') + '.csv' });
    }

    if (action === 'brief_pdf') {
      const iid = String(body.inquiry_id || '');
      const lang = documentLocale(body.lang, cust.locale);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,category,summary,emirate,budget,spec,boq,trades,drawing_file_name').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      try {
        const { j, ref } = await buildBriefPdf(inq, lang);
        if (j?.ok && j.url) return J({ ok: true, url: j.url, ref });
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    if (action === 'quote_pdf') {
      const qid = String(body.quote_id || '');
      // ONE LANGUAGE PER DOCUMENT, BOTH ALWAYS ON OFFER (founder, 14 Sep 2026). The old 'bi' file —
      // English page, then an "Arabic" page whose content was English whenever ai_gateway failed —
      // is no longer produced; its cache rows are simply never read again.
      // 21 Sep 2026 (customer audit, finding 4): the portal's "النسخة العربية" button sent lang:'ar'
      // and this line read customers.locale instead, so an English-registered customer could never
      // get the Arabic document the button promises ("both always on offer"). The registered locale
      // is the DEFAULT; an explicit request for the other language is the customer asking for the
      // second document, not a message being addressed in the wrong language.
      const lang = documentLocale(body.lang, cust.locale);
      const { data: q } = await admin.from('quotes').select('*').eq('id', qid).maybeSingle();
      if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,category,summary,emirate,boq').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      // A draft is not a quote the customer has; it has no letter and no document.
      if (q.status === 'draft') return J({ error: 'Quote not found' }, 404);
      const { data: cached } = await admin.from('quote_pdf_cache').select('bucket,path,created_at').eq('quote_id', qid).eq('lang', lang).maybeSingle();
      const touched = q.updated_at ? new Date(q.updated_at) : (q.created_at ? new Date(q.created_at) : null);
      // A cached file is served only if it was rendered by THIS layout (isCurrentDoc: DOC_VERSION is in the
      // file name). Measured 21 Sep 2026: 14 Arabic rows in quote_pdf_cache, the first from 14 Sep — every
      // one rendered before the Arabic fixes of #782/#790/#794 and served for as long as the quote itself
      // was untouched, so a customer kept getting the old, part-English document after the fix shipped.
      if (cached && isCurrentDoc(cached.path) && (!touched || new Date(cached.created_at) >= touched)) {
        const url = await signedDoc(cached.bucket, cached.path);
        if (url) return J({ ok: true, url, ref: quoteRef(inq, await letterOf(q)), lang, cached: true });
      }
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      try {
        const { j, ref } = await buildQuotePdf(q, inq, lang);
        if (j?.ok && j.url) {
          try { await admin.from('quote_pdf_cache').upsert({ quote_id: qid, lang, customer_id: cust.id, bucket: j.bucket || 'agent-docs', path: j.path, created_at: new Date().toISOString() }, { onConflict: 'quote_id,lang' }); } catch (_e) { /* */ }
          return J({ ok: true, url: j.url, ref, lang });
        }
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    if (action === 'reveal') {
      const cfg = await getCfg(); const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount,original_file_path,original_file_name').eq('id', qid).maybeSingle();
      if (!q) return J({ error: 'Quote not found' }, 404);
      // NEVER SHOWN TO A CUSTOMER (founder instruction 516, 18 Sep 2026). A sanctions ban lands
      // after the quote was already submitted, so the row survives the matcher that would have
      // excluded it. The refusal belongs BEFORE the charge, not after: a customer must not pay to
      // be handed the contact details of a sanctioned party.
      if (await sanctionedLead(admin, q.supplier_id)) return J(SANCTIONED_REFUSAL, 403);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
      if (existing) { const { data: sup } = await admin.from('leads').select('company_name,phone,whatsapp,email,website,emirate').eq('id', q.supplier_id).maybeSingle(); return J({ ok: true, already_revealed: true, supplier: sup, original_file_url: await signedFile(q.original_file_path), original_file_name: q.original_file_name || null }); }
      // The breakdown the confirm dialog prints is the one stripe_checkout charges: one module.
      const ch = revealCharge(Number(q.quote_amount), Number(cfg.standard_reveal_rate));
      return J({ ok: true, payment_required: true, quote_id: qid, quote_amount: q.quote_amount, reveal_fee: ch.base_fee, processing_fee: ch.processing_fee, total_charged: ch.total_charged, currency: 'AED' });
    }

    if (action === 'request_refund') {
      const qid = String(body.quote_id || '');
      const { data: tx } = await admin.from('transactions').select('id,customer_id').eq('quote_id', qid).maybeSingle();
      if (!tx || tx.customer_id !== cust.id) return J({ error: 'Transaction not found' }, 404);
      // ONE DOOR, ONE TRANSACTION (14 Sep 2026). Until today this action flipped the sale to
      // 'requested' first, then tried to open the case, threw the refusal away and told the customer
      // "received" anyway: e2e run 7 left a sale reading "requested" with no case, no handoff to the
      // accountant and no decision coming. Every check, the case, the sale's status and the
      // confirmation in the customer's registered language now happen inside
      // fn_refund_open_from_customer, or none of them do. The published terms let a customer complain
      // "at any time"; the five working days govern when the CEO may decide, not when they may ask.
      const { data: rf, error: rfErr } = await admin.rpc('fn_refund_open_from_customer', { p_transaction_id: tx.id, p_requested_by: 'customer' });
      if (rfErr || !rf) {
        // NOT A POLICY REFUSAL: the one transaction rolled back (a guard, the confirmation handoff, the
        // database). The customer's claim is not lost -- they are told to try again -- but somebody must
        // see it, so it is an IT finding keyed on the sale (reopened, not duplicated, on a repeat).
        try {
          await admin.rpc('fn_it_engineer_finding_upsert', {
            p_issue_key: 'refund:request_failed:' + tx.id,
            p_title: 'A customer could not open a refund case: the request rolled back',
            p_where: 'customer_api request_refund -> public.fn_refund_open_from_customer',
            p_blast: 'customer_facing', p_affected: 1,
            p_evidence: { transaction_id: tx.id, customer_id: cust.id, error: String(rfErr?.message || 'no answer').slice(0, 600), at: new Date().toISOString() },
            p_raised_by: 'customer_api',
          });
        } catch (_e) { /* the finding is best-effort; the customer's answer below is not */ }
        return J({ ok: false, error: 'refund_request_failed', code: 'refund_request_failed', detail: rfErr?.message || 'no answer' }, 500);
      }
      const msg = rf.locale === 'ar' ? rf.message_ar : rf.message_en;
      if (!rf.ok) return J({ ok: false, error: rf.code, code: rf.code, message: msg, can_claim_later: rf.can_claim_later ?? null }, 400);
      return J({ ok: true, refund_status: 'requested', refund_id: rf.refund_id, refund_ref: refundRef(rf.refund_id),
        duplicate: rf.duplicate === true, decision_after: rf.decision_after ?? null, message: msg });
    }

    // A CUSTOMER IS NEVER BLOCKED FROM RATING (operator, 17 Sep 2026). Measured on the production
    // journey: every star press returned HTTP 500 — SQLSTATE 23514, `reviews_reason_required` — and
    // public.reviews held 0 rows, so no rating had ever succeeded. The widget sends stars and no
    // comment; the constraint demanded a comment of 10+ characters. The constraint now reads
    // "a comment, IF GIVEN, must be 10+ characters"
    // (scripts/sql/a_customer_is_never_blocked_from_rating.sql) and this handler refuses a short one
    // BEFORE the write, in words the customer can read, rather than letting the database refuse it
    // as a 500. Who may rate and when is unchanged: a transaction on this quote, 1..5, one per job.
    if (action === 'rate_supplier') {
      const qid = String(body.quote_id || '');
      // The rule (stars alone suffice; a comment, if given, is 10+ characters) lives in
      // ./rating_input.ts with its tests, so the handler and the test read the same code.
      const parsed = parseRatingInput(body);
      if (!parsed.ok) return J({ error: parsed.error, code: parsed.code }, 400);
      const { rating, comment } = parsed;
      const { data: q } = await admin.from('quotes').select('id,supplier_id,inquiry_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found', code: 'not_found' }, 404);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'You can only rate a supplier you have revealed and dealt with.', code: 'forbidden' }, 403);
      const { error } = await admin.from('reviews').upsert({ supplier_id: q.supplier_id, customer_id: cust.id, inquiry_id: q.inquiry_id, transaction_id: tx.id, rating, comment }, { onConflict: 'transaction_id' });
      if (error) {
        // A 500 ON A USER ACTION IS ITSELF A DEFECT: the customer sees a broken product and we learn
        // nothing. Class 23 is an integrity violation — the database REFUSED the request, which is a
        // 4xx. Anything else is ours, and is still answered in words rather than with a raw driver
        // string that would put a constraint name in front of a customer.
        const sqlstate = String((error as { code?: string }).code || '');
        console.error('rate_supplier refused', JSON.stringify({ sqlstate, message: error.message, quote_id: qid }));
        if (sqlstate.startsWith('23')) return J({ error: 'We could not accept that rating. Please check what you entered and try again.', code: 'review_refused' }, 400);
        return J({ error: 'Could not save your rating. Please try again in a moment.', code: 'review_save_failed' }, 500);
      }
      await admin.rpc('recompute_supplier_rating', { p_supplier: q.supplier_id });
      return J({ ok: true });
    }

    if (action === 'complete_inquiry') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'Reveal this supplier first.' }, 403);
      await admin.from('inquiries').update({ status: 'completed', hired_supplier_id: q.supplier_id, completed_at: new Date().toISOString(), outcome: 'hired' }).eq('id', inq.id);
      await notifyLosers(String(inq.id), inq.summary ?? null, Number(q.supplier_id));
      return J({ ok: true });
    }

    if (action === 'edit_inquiry') {
      const iid = String(body.inquiry_id || '');
      const patch = (body.patch && typeof body.patch === 'object') ? body.patch : body;
      const clean: Record<string, unknown> = {};
      for (const k of ['summary','raw_input','budget','emirate','scope_type','spec','boq','trades','keywords']) if (patch[k] !== undefined) clean[k] = patch[k];
      const { data: r } = await admin.rpc('fn_edit_inquiry', { p_inquiry: iid, p_customer: cust.id, p_patch: clean });
      if (r?.error) return J({ error: r.message || r.error, editable_until: r.editable_until }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }

    if (action === 'cancel_inquiry') {
      const iid = String(body.inquiry_id || '');
      const reason = body.reason ? String(body.reason).slice(0, 300) : null;
      const { data: r } = await admin.rpc('fn_cancel_inquiry', { p_inquiry: iid, p_customer: cust.id, p_reason: reason });
      if (r?.error) return J({ error: r.message || r.error }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }

    if (action === 'supplier_history') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,supplier_id,original_file_path,original_file_name').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      if (await sanctionedLead(admin, q.supplier_id)) return J(SANCTIONED_REFUSAL, 403);  // founder instruction 516: never shown to a customer
      // The reveal check gates what is RETURNED, not what may be read, so the three reads that only
      // need q.supplier_id run beside it instead of one after another (14 Sep 2026: four sequential
      // round trips here, then three more below).
      const [{ data: tx }, { data: sup }, { data: projs }, mine, { count: sentAll }] = await Promise.all([
        admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle(),
        admin.from('leads').select('id,company_name,emirate,phone,whatsapp,email,website,app_rating,app_reviews,description,capability_summary,founded_year,company_type').eq('id', q.supplier_id).maybeSingle(),
        admin.from('transactions').select('revealed_at,quote_amount,inquiries(category,emirate)').eq('supplier_id', q.supplier_id).order('revealed_at', { ascending: false }).limit(20),
        admin.from('inquiries').select('id').eq('customer_id', cust.id).limit(500),
        admin.from('inquiry_matches').select('inquiry_id', { count: 'exact', head: true }).eq('supplier_id', q.supplier_id),
      ]);
      if (!tx) return J({ error: 'Reveal this supplier first to see their profile.' }, 403);
      const projects = (projs || []).map((p: any) => ({ category: p.inquiries?.category || null, emirate: p.inquiries?.emirate || null, month: p.revealed_at ? new Date(p.revealed_at).toLocaleDateString('en-GB', { month: 'short', year: 'numeric' }) : null, value_band: band(Number(p.quote_amount)) }));
      // §13 "History: 17 RFQs, 8 Orders" — TWO DIFFERENT NUMBERS, and this action served only the
      // second. projects[] is built from transactions, i.e. from PAID REVEALS, so an RFQ that was
      // sent to this supplier and never quoted was invisible: a supplier who received eleven of
      // this customer's briefs and answered none of them read as "no history", which is the
      // opposite of what the customer needs to know about them.
      //
      // SCOPED TO THIS CUSTOMER, deliberately. §13 is headed "Customer Supplier Relationship
      // Management" — it is this buyer's relationship with this supplier, not the supplier's
      // platform-wide record, which they can already see as the rating. The platform-wide count is
      // returned beside it and labelled, so the two can never be mistaken for one another.
      const myInqIds = mine.data?.map((r: any) => r.id) || [];
      let rfqsSent = 0, quotesBack = 0;
      if (myInqIds.length) {
        const [{ count: sent }, { count: back }] = await Promise.all([
          admin.from('inquiry_matches').select('inquiry_id', { count: 'exact', head: true }).eq('supplier_id', q.supplier_id).in('inquiry_id', myInqIds),
          admin.from('quotes').select('id', { count: 'exact', head: true }).eq('supplier_id', q.supplier_id).in('inquiry_id', myInqIds).neq('status', 'draft'),
        ]);
        rfqsSent = sent || 0;
        quotesBack = back || 0;
      }
      const relationship = {
        rfqs_sent: rfqsSent, quotes_returned: quotesBack, orders: projects.length,
        response_rate_pct: rfqsSent ? Math.round((quotesBack / rfqsSent) * 100) : null,
        scope: 'this customer',
        rfqs_sent_platform_wide: sentAll || 0,
      };
      return J({ ok: true, supplier: sup ? { ...sup, rating_display: ratingOf(sup) } : null, projects, projects_count: projects.length, relationship, original_file_url: await signedFile(q.original_file_path), original_file_name: q.original_file_name || null });
    }


    // ── §8 / §6: THE RECORDED LIFECYCLE, SERVED TO THE CUSTOMER ────────────────────────────────
    // fn_entity_activity carries the QD_RFQ_TRACE branch — dated milestone / event / quote / match
    // entries — and its only reader was os_api, the staff console. The customer's own portal
    // derived the stage in the browser from quotes.length and anyRevealed: a guess sitting on top
    // of a recorded fact.
    //
    // IDENTITY IS SCRUBBED, NOT TRUSTED. The trace's own text names suppliers — its quote entries
    // read "Quotation AED 250000 from supplier #3251" and its match entries carry route_inquiry's
    // free-text reason, which is generated against a candidate list built as `#<id> — <Company
    // Name>`. Every title and body goes through the same scrubIdentity the quote surface uses,
    // against the company name of every supplier this customer has NOT paid to reveal on this RFQ.
    // Suppliers already revealed are left alone: the customer bought that name.
    if (action === 'activity') {
      const iid = String(body.inquiry_id || '');
      const { data: own } = await admin.from('inquiries').select('id').eq('id', iid).eq('customer_id', cust.id).maybeSingle();
      if (!own) return J({ error: 'Not your inquiry' }, 403);
      const { data: trace, error: te } = await admin.rpc('fn_entity_activity', { p_entity: 'inquiry', p_id: iid });
      if (te) return J({ error: te.message }, 500);
      const { data: qs } = await admin.from('quotes').select('id,supplier_id').eq('inquiry_id', iid);
      const { data: txs } = await admin.from('transactions').select('quote_id').eq('customer_id', cust.id);
      const revealedQuotes = new Set((txs || []).map((t: any) => String(t.quote_id)));
      const hiddenSupIds = [...new Set((qs || []).filter((q: any) => !revealedQuotes.has(String(q.id))).map((q: any) => q.supplier_id))];
      const { data: ms } = await admin.from('inquiry_matches').select('supplier_id').eq('inquiry_id', iid);
      for (const m of (ms || [])) if (!hiddenSupIds.includes(m.supplier_id)) hiddenSupIds.push(m.supplier_id);
      const names: string[] = [];
      if (hiddenSupIds.length) { const { data: ls } = await admin.from('leads').select('company_name').in('id', hiddenSupIds); for (const l of ls || []) if (l.company_name) names.push(String(l.company_name)); }
      const hits: string[] = [];
      const clean = (t: unknown) => { let s = t == null ? null : String(t); for (const n of names) s = scrubIdentity(s, n, hits); return s; };
      const entries = (Array.isArray(trace) ? trace : []).map((e: any) => ({
        at: e.at ?? null, kind: e.kind ?? null, actor: e.actor ?? null,
        title: clean(e.title), status: e.status ?? null,
      }));
      return J({ ok: true, inquiry_id: iid, entries, entries_count: entries.length, redacted: hits.length });
    }

    // ── §9 SUPPLIER DISCOVERY, AS ITS OWN ACT ───────────────────────────────────────────────────
    // "Customer does not search. They ask." Both matchers existed and both sat on the DISPATCH
    // path only — discovery happened as a side effect of sending an RFQ, and no customer action
    // invoked it on its own, so the spec's "Found: 47 suppliers / Filtered: UAE, capacity,
    // certification" screen had nothing behind it.
    //
    // NO COMPANY NAMES. fn_match_capability returns company_name and this endpoint drops it: the
    // entire product sells the supplier's identity at reveal, and a free discovery call that
    // listed names would give away the thing being sold. The customer gets the COUNT, the FILTERS
    // that were applied, and a ranked, anonymous shortlist — which is what they need to decide
    // whether the brief is worth sending.
    // The controlled vocabulary the trades box is actually matched against. It is served because
    // the box is free text and fn_match_capability compares with `sc.trades && p_trades` — an exact
    // array overlap on CODES. A customer typing a perfectly ordinary word gets silence otherwise.
    if (action === 'trades') {
      const { data: tr } = await admin.from('taxonomy_trade').select('code,label').eq('active', true).order('sort');
      return J({ ok: true, trades: tr || [] });
    }

    if (action === 'discover') {
      const typed = Array.isArray(body.trades) ? body.trades.map((t: unknown) => String(t).toLowerCase().trim()).filter(Boolean).slice(0, 6) : [];
      if (!typed.length) return J({ error: 'trades_required', message: 'Name at least one trade to search for.' }, 400);
      // ── A WORD THAT IS NOT A CODE MATCHED NOTHING, SILENTLY ──────────────────────────────────
      // MEASURED 13 Aug 2026: typing "marble" into this box returns nothing, and so does the
      // screen's own worked example. taxonomy_trade holds 40 active codes — civil_works, flooring,
      // building_materials, aluminium — and `marble` is not one of them, nor one of the 283
      // aliases. fn_match_capability compares CODES with an exact array overlap, so the query was
      // for a trade that cannot exist and the answer was an empty list with no hint that the word
      // itself was the problem.
      //
      // route_inquiry has resolved customer words through taxonomy_trade.aliases since it was
      // written; discovery never did. Same lexicon, same three steps — code, alias, then label —
      // and whatever still does not resolve is REPORTED rather than searched for and lost.
      const { data: taxo } = await admin.from('taxonomy_trade').select('code,label,aliases').eq('active', true);
      const resolveTrade = (w: string): string | null => {
        for (const t of (taxo || [])) if (String(t.code).toLowerCase() === w) return t.code;
        for (const t of (taxo || [])) if ((t.aliases || []).some((a: string) => String(a).toLowerCase() === w)) return t.code;
        for (const t of (taxo || [])) if (String(t.label || '').toLowerCase().includes(w) && w.length >= 4) return t.code;
        return null;
      };
      const resolved: string[] = []; const unresolved: string[] = [];
      for (const w of typed) { const c = resolveTrade(w); if (c && !resolved.includes(c)) resolved.push(c); else if (!c) unresolved.push(w); }
      if (!resolved.length) {
        return J({ ok: true, found: 0, matches: [], anonymous: true,
          filters: { trades: [], emirate: body.emirate ? String(body.emirate).slice(0, 40) : null },
          unresolved,
          why_empty: { suppliers_holding_trade: 0, confirmed_total: 0, reason: 'not_a_trade_we_know' },
          trades_known: (taxo || []).map((t: Record<string, unknown>) => ({ code: t.code, label: t.label })),
          note: 'Supplier identities are revealed after a quote is accepted, so discovery returns ranked, anonymous matches.' });
      }
      const trades = resolved;
      const filters = {
        trades,
        emirate: body.emirate ? String(body.emirate).slice(0, 40) : null,
        need: ['executes', 'supplies', 'both'].includes(String(body.need)) ? String(body.need) : 'executes',
        products: Array.isArray(body.products) ? body.products.map((s: unknown) => String(s)).slice(0, 8) : [],
        brands: Array.isArray(body.brands) ? body.brands.map((s: unknown) => String(s)).slice(0, 8) : [],
        project_type: body.project_type ? String(body.project_type).slice(0, 40) : null,
        value: Number.isFinite(Number(body.value)) ? Number(body.value) : null,
        limit: Math.min(24, Math.max(1, Number(body.limit) || 12)),
      };
      // trade-level by design: no brief — `discover` is a free-text TRADES box, so the customer has
      // named trades and not a job, and there is no summary or BOQ to read service keys from. Every
      // matcher that DOES have a brief passes p_services (SP-F-01, 22 Sep 2026), and the check
      // scripts/checks/every_matcher_that_has_a_brief_passes_its_services.test.mjs reads this marker
      // per CALL, so a second matcher added in this file is not exempt by living here.
      const { data: rows, error: me } = await admin.rpc('fn_match_capability', {
        p_trades: filters.trades, p_need: filters.need, p_products: filters.products, p_brands: filters.brands,
        p_project_type: filters.project_type, p_value: filters.value, p_emirate: filters.emirate, p_limit: filters.limit,
      });
      if (me) return J({ error: me.message }, 500);
      const hits2: string[] = [];
      const matches = (rows || []).map((r: any, i: number) => ({
        label: 'Supplier ' + supplierLabel(i),
        match_pct: Number.isFinite(Number(r.score)) ? Math.round(Number(r.score) * (Number(r.score) <= 1 ? 100 : 1)) : null,
        trades: r.trades || null, roles: r.roles || null,
        product_hits: r.product_hits ?? 0, brand_hit: !!r.brand_hit, project_type_hit: !!r.ptype_hit,
        track_record: r.track ?? null,
        why: scrubIdentity(r.why ?? null, r.company_name, hits2),
      }));
      // ── A ZERO HAS TO NAME ITS OWN REASON ────────────────────────────────────────────────────
      // MEASURED 13 Aug 2026, typing this screen's OWN worked example into it: "Found 0 suppliers —
      // No registered supplier matches that yet." The database holds 20,470 leads and 15,306
      // supplier_capabilities rows, EVERY ONE of them carrying trades. What it does not hold is
      // confirmations: fn_match_capability gates on `sc.confirmed_at is not null`, and exactly ONE
      // row in 15,306 satisfies it. So the matcher can return at most one supplier for any query,
      // and the sentence on screen blamed the wrong thing.
      //
      // That distinction is the whole decision behind the screen. "No supplier matches that" reads
      // as "you need more suppliers" — buy scraping, run outreach. "1,143 suppliers do that trade
      // and none has confirmed their scope" reads as "chase confirmations", which is a different
      // action, cheaper, and the correct one. A count is not an explanation.
      //
      // The GATE IS NOT WEAKENED. Matching an unconfirmed scope would put a customer's RFQ in front
      // of a supplier who never said they do the work — the exact thing confirmed_at exists to
      // prevent. Only the explanation is added.
      let why_empty = null;
      if (!matches.length) {
        const [{ count: holding }, { count: confirmedTotal }] = await Promise.all([
          admin.from('supplier_capabilities').select('supplier_id', { count: 'exact', head: true }).overlaps('trades', filters.trades),
          admin.from('supplier_capabilities').select('supplier_id', { count: 'exact', head: true }).not('confirmed_at', 'is', null),
        ]);
        why_empty = {
          suppliers_holding_trade: holding || 0,
          confirmed_total: confirmedTotal || 0,
          reason: (holding || 0) === 0 ? 'no_supplier_holds_this_trade' : 'held_but_unconfirmed',
        };
      }
      return J({ ok: true, found: matches.length, filters, matches, anonymous: true, why_empty,
        unresolved: unresolved.length ? unresolved : undefined,
        note: 'Supplier identities are revealed after a quote is accepted, so discovery returns ranked, anonymous matches.' });
    }

    // ── §17 CUSTOMER AI MEMORY: SEE, AND CORRECT ────────────────────────────────────────────────
    // customer_preference, fn_customer_preference_learn and the learning trigger were all green,
    // and the store had ZERO customer-authed readers — the only consumer was os_api. The customer
    // could not see what had been inferred about them, and had no way to say it was wrong. Both
    // verbs are served here; `learned` and `stated` are kept apart on the wire so the customer can
    // tell what they told us from what we guessed.
    if (action === 'preferences') {
      const { data: pref } = await admin.from('customer_preference').select('preferences,consented_at,updated_at').eq('customer_id', cust.id).maybeSingle();
      const p = (pref?.preferences && typeof pref.preferences === 'object') ? pref.preferences as Record<string, unknown> : {};
      return J({ ok: true,
        preferences: p,
        // The store's own two halves, kept apart on the wire under the names it uses. `learned` is
        // an alias for `inferred` because that is the word the customer reads; both are emitted so
        // a client written against either keeps working.
        stated: (p as any).stated ?? {},
        inferred: (p as any).inferred ?? {},
        learned: (p as any).inferred ?? {},
        consented_at: pref?.consented_at ?? null, updated_at: pref?.updated_at ?? null,
        note: 'Learned values come from your past requests. Anything you state here overrides them.' });
    }

    if (action === 'save_preferences') {
      const stated = (body.stated && typeof body.stated === 'object' && !Array.isArray(body.stated)) ? body.stated : null;
      if (!stated) return J({ error: 'stated_object_required' }, 400);
      // fn_customer_preference_learn merges the stated block over the learned one and stamps
      // updated_at — the same routine the trigger uses, so a correction the customer types and a
      // value the system infers can never be written by two different rules.
      const { error: pe } = await admin.rpc('fn_customer_preference_learn', { p_customer_id: cust.id, p_stated: stated });
      if (pe) return J({ error: pe.message }, 500);
      const { data: pref } = await admin.from('customer_preference').select('preferences,consented_at,updated_at').eq('customer_id', cust.id).maybeSingle();
      return J({ ok: true, preferences: pref?.preferences ?? {}, updated_at: pref?.updated_at ?? null });
    }

    // THE LANGUAGE THE PORTAL APOLOGISED FOR NOT SAVING.
    //
    // customers.locale has been read for months — my_inquiries serves it and the portal applies it
    // on a device that has no stored choice — and NOTHING has ever written it. The Account screen
    // said so out loud: "We have no settings endpoint that writes them back to your profile yet,
    // so nothing here is saved to your account." An Arabic customer therefore set their language
    // once per device, forever. This is that endpoint; the apology goes with it.
    //
    // Deliberately narrow: two values, validated against the same pair i18n/routing declares, and
    // it touches one column. A generic profile-patch action here would be a way to write full_name
    // and phone without passing kyc's checks — the phone one now clears phone_verified, and this
    // must not become a route around it.
    if (action === 'set_locale') {
      const loc = String(body.locale || '').toLowerCase();
      if (loc !== 'en' && loc !== 'ar') return J({ error: 'locale must be en or ar' }, 400);
      const { error: le } = await admin.from('customers').update({ locale: loc }).eq('id', cust.id);
      if (le) return J({ error: le.message }, 500);
      return J({ ok: true, locale: loc });
    }

    return J({ error: 'Unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
}));
