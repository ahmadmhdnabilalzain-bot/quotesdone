// supplier_portal v5 — advanced supplier dashboard API. Supplier-authed (own leads row via claimed_by).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD } from '../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. A refused file is reported in `failed`
// exactly as a refused SHAPE already was, so a supplier is never told a document is on file when
// the scanner refused it.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { defaultDeps } from '../_shared/think.ts';
import { readSupplierProfile } from '../_shared/reasoned_suppliers.ts';
import { runtimeWaitUntil } from '../_shared/async_webhook.ts';
import { REQUIRED_DOC_KEYS } from '../_shared/supplier_registration.ts';
import { buildAlerts, buildDashboard, buildEligibility, buildNotifications, supplierCard, type Supplier } from './overview.ts';
import { proposeTradesFromDocs, type DocIn } from '../_shared/supplier_doc_trades.ts';
import { buildInsightsSummary } from './insights_summary.ts';
import { deleteSupporting, listSupporting, saveSupporting, urlSupporting } from './supporting_documents.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail, sanctionedLead } from '../_shared/sanctioned.ts';
// EVERY DOCUMENT READS ITS OWN DATES, AND OFFERS VIEW / DOWNLOAD / REPLACE / REMOVE (founder
// instruction 524, 21 Sep 2026). _shared/document_expiry.ts reads the expiry off the bytes by code
// before any model is asked; ./document_actions.ts holds the Remove refusal and the version row.
import { readExpiry, type ExpiryRead } from '../_shared/document_expiry.ts';
import { removeRefusal, versionRow, type ExpiryNote, type VersionSnapshot } from './document_actions.ts';
import { refusalBody, signedInUser } from '../_shared/signed_in_user.ts';
import { productsAsked } from '../_shared/reasoned_matching.ts';
import { COMPANY_ALREADY_REGISTERED, type LeadWriter, updateLeadSettingAsideClashingLicence } from '../_shared/duplicate_company.ts';
// The model path (license_extract → ai_gateway) is OFF unless app_secrets.document_expiry_ai is
// 'on'. OpenRouter is on hold; a closed door must not be knocked on for every upload.
async function flagOn(key: string): Promise<boolean> { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return /^(on|true|1)$/i.test(String(data?.value || '').trim()); }
// SUPPLIER-FACING TEXT CARRIES A CODE (14 Sep 2026). Every sentence below that reaches a supplier
// (document hints, alerts, eligibility titles/details) now travels with a stable `code` and `params`;
// the portal renders the EN/AR wording from src/components/portal/supplier/serverCopy.ts and falls
// back to the English here, which is kept verbatim for emails and older clients.
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
// A POSTGRES ERROR IS NOT A SENTENCE FOR A SUPPLIER (audit 22 Sep 2026, SP-I-01; agent:
// customer_support). Thirteen reads answered `{ error: error.message }`, which put raw Postgres text
// ("function fn_supplier_twin(p_lead_id => bigint) does not exist", column names, constraint names)
// straight into the browser — a schema leak, and untranslatable, so the Arabic portal printed English
// database prose. The real message now goes to the function log, the supplier gets a stable `code`
// src/components/portal/supplier/serverCopy.ts renders in their language, and `error` keeps a plain
// English sentence as the fallback for an older client.
const failed = (where: string, code: string, english: string, error: { message?: string } | null, status = 500) => {
  console.error('supplier_portal: ' + where + ' failed —', String(error?.message || 'unknown'));
  return J({ error: english, code }, status);
};
const loadFailed = (where: string, error: { message?: string } | null) =>
  failed(where, 'load_failed', 'Could not load this section. Please try again.', error);
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
async function sign(bucket:string, path:string|null){ if(!path) return null; try{ const { data } = await admin.storage.from(bucket).createSignedUrl(path, 3600); return data?.signedUrl || null; }catch{ return null; } }
// Every document a supplier can hold, in the order the portal shows them.
//
// Until v4 this map contained ONLY `iso`, which meant save_documents could write an ISO
// certificate and nothing else. The documents tab rendered the trade licence and company
// profile as read-only, and VAT / insurance / manufacturer authorisation had no UI at all.
// The effect was a dead end: fn_supplier_expiries raises "Insurance has expired - upload a
// renewed copy" and routes the supplier to a tab with no insurance field. Worse, an
// established supplier could never replace an expired trade licence, because the only
// licence upload lives in ProfileForm, which renders only while the account still has no
// company. Driving both read and write off one map closes that.
//
// `folder` keeps storage tidy and mirrors what save_profile already writes.
const DOC_KINDS: Record<string, { pathCol: string; nameCol?: string; expCol: string | null; label: string; folder: string; hint: string }> = {
  license:      { pathCol:'license_doc_path',           nameCol:'license_doc_name', expCol:'license_expiry',            label:'Trade licence',              folder:'licence',   hint:'Required. Your current trade licence from your licensing authority (Economic Department or free-zone authority).' },
  profile:      { pathCol:'company_profile_doc_path',                               expCol:null,                        label:'Company profile',            folder:'profile',   hint:'Required. Your company introduction deck or PDF. Shown to customers after a reveal.' },
  vat:          { pathCol:'vat_doc_path',                                           expCol:null,                        label:'VAT certificate',            folder:'certs',     hint:'Your TRN certificate. Needed before you can invoice with VAT.' },
  insurance:    { pathCol:'insurance_doc_path',                                     expCol:'insurance_expiry',          label:'Insurance',                  folder:'certs',     hint:'Public liability or contractor all-risk cover.' },
  iso:          { pathCol:'iso_doc_path',                                           expCol:'iso_expiry',                label:'ISO certification',          folder:'certs',     hint:'Any ISO certificate you hold. Strengthens your capability score.' },
  manufacturer: { pathCol:'manufacturer_auth_doc_path',                             expCol:'manufacturer_auth_expiry',  label:'Manufacturer authorisation', folder:'certs',     hint:'Authorised-dealer letters from the brands you carry.' },
  // ONE NAME FOR THE EGR (audit 21 Sep 2026, finding 18): the establishment card issued with the
  // trade licence — the profile's "Economic Register (EGR) no." is its number. It was "Establishment
  // card" here, "EGR (Emirates Green Building) certificate" in the portal and "immigration
  // establishment card" in the hint; fn_supplier_certifications and the portal now say the same.
  egr:          { pathCol:'egr_doc_path',               nameCol:'egr_doc_name',     expCol:null,                        label:'Establishment card (EGR)',   folder:'certs',     hint:'Your establishment card (EGR), issued with your trade licence.' },
};
// `iban` (a bank letter) was a document type here until 21 Sep 2026. Money moves both directions through
// Stripe, so the estate never holds a supplier's bank details — founder instruction 527.
const DOC_ORDER = ['license','profile','catalogs','vat','insurance','iso','manufacturer','egr'];
// The supporting-document subject that can stand in for a fixed kind (fn_supplier_document_home).
const HOME_KEY: Record<string, string> = { license: 'trade_licence', profile: 'company_profile', insurance: 'insurance', iso: 'iso', manufacturer: 'manufacturer_auth', egr: 'establishment' };

// THE DOCUMENTS LIST — the one builder every read and every write answers with (finding 16), and the
// one home for each subject (finding 17): a certificate a supplier uploaded as a SUPPORTING document
// (ISO 9001 under "Supporting documents") is on file here too, marked source 'supporting', the same
// way fn_supplier_certifications, fn_supplier_document_impact and fn_supplier_twin now see it.
async function listDocuments(supId: number) {
  // Column list is derived from DOC_KINDS so adding a document type here needs no edit below.
  const cols = new Set<string>(['catalog_doc_paths']);
  for (const k of Object.values(DOC_KINDS)) { cols.add(k.pathCol); if (k.nameCol) cols.add(k.nameCol); if (k.expCol) cols.add(k.expCol); }
  const [{ data: l }, { data: homeRows }, { data: vers }, expiries] = await Promise.all([
    admin.from('leads').select([...cols].join(',')).eq('id', supId).maybeSingle(),
    admin.rpc('fn_supplier_document_home', { p_lead_id: supId }),
    // Previous versions (replaced or removed files) per kind, from doc_versions — the supplier
    // sees "2 earlier versions kept" beside a document, and Remove can say what was hidden.
    admin.from('doc_versions').select('entity_id,version,snapshot,created_at')
      .eq('entity_type', 'supplier_document').like('entity_id', `${supId}:%`).order('version', { ascending: false }).limit(200),
    admin.rpc('fn_supplier_expiries', { p_supplier_id: supId }),
  ]);
  const row = (l || {}) as Record<string, unknown>;
  const home = new Map<string, { path: string | null; name: string | null; source: string | null }>();
  for (const h of ((homeRows || []) as { key: string; path: string | null; name: string | null; source: string | null }[])) home.set(h.key, h);

  const cats: string[] = Array.isArray(row.catalog_doc_paths) ? (row.catalog_doc_paths as string[]) : [];
  const catalogues: { path: string; name: string; url: string | null }[] = [];
  for (const p of cats.slice(0, 20)) {
    catalogues.push({ path: p, name: String(p).split('/').pop() || 'Catalogue', url: await sign('supplier-docs', p) });
  }

  const today = new Date(); today.setHours(0, 0, 0, 0);
  const docs: Record<string, unknown>[] = [];
  for (const key of DOC_ORDER) {
    if (key === 'catalogs') {
      docs.push({ key:'catalogs', label:'Catalogues', hint_code:'doc_hint_catalogs', hint:'Product or project catalogues. Upload as many as you like - new files are added, never replaced.',
        path: cats.length ? 'catalogs' : null, expiry:null, url:null, name:null, required:false,
        count: cats.length, urls: catalogues.map((c) => c.url).filter(Boolean), items: catalogues,
        status: cats.length ? 'on_file' : 'missing' });
      continue;
    }
    const k = DOC_KINDS[key]; if (!k) continue;
    const own = (row[k.pathCol] as string) || null;
    const stand = !own && HOME_KEY[key] ? home.get(HOME_KEY[key]) : undefined;
    const path = own || (stand && stand.path) || null;
    const source = own ? 'leads' : (stand && stand.path ? 'supporting' : null);
    const expiry = own && k.expCol ? ((row[k.expCol] as string) || null) : null;
    // Filename falls back to the stored path's tail so the supplier always sees which file is on record.
    const name = (own && k.nameCol ? (row[k.nameCol] as string) : null) || (stand && stand.path ? stand.name : null) || (path ? String(path).split('/').pop() : null) || null;
    let status = 'missing';
    if (path) {
      status = 'on_file';
      if (expiry) {
        const d = Math.round((new Date(expiry).getTime() - today.getTime()) / 864e5);
        status = d < 0 ? 'expired' : d <= 30 ? 'expiring' : 'valid';
      }
    }
    docs.push({ key, label: k.label, hint: k.hint, path, name, expiry, has_expiry: !!k.expCol, source,
      // The mandatory six (_shared/supplier_registration.ts): licence AND company profile. This
      // said `key === 'license'` while the same tab's heading listed three required documents.
      required: REQUIRED_DOC_KEYS.includes(key), hint_code: 'doc_hint_' + key, status, url: await sign('supplier-docs', path) });
  }

  const required = docs.filter((d) => d.required);
  const complete = docs.filter((d) => d.status !== 'missing').length;
  for (const d of docs) {
    const mine = ((vers || []) as { entity_id: string; snapshot: VersionSnapshot; created_at: string }[]).filter((v) => v.entity_id === `${supId}:${d.key}`);
    d.versions = mine.length;
    d.last_version = mine[0] ? { event: mine[0].snapshot?.event, name: mine[0].snapshot?.name, at: mine[0].created_at } : null;
  }
  return { ok:true, documents: docs, expiries: expiries.data || [],
    summary: { total: docs.length, on_file: complete, missing: docs.length - complete,
      required_missing: required.filter((d) => d.status === 'missing').length,
      attention: docs.filter((d) => d.status === 'expired' || d.status === 'expiring').length } };
}

Deno.serve(observe('supplier_portal', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  // KEEP-WARM (resilience_ping; 28 Sep 2026 it_engineer, supplier journey). No auth, no DB: the isolate is
  // what needs exercising. See warmPortal() in resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    // Local refusal first, a bounded auth call, and 503 (not 401) when auth is down — _shared/signed_in_user.ts.
    const who = await signedInUser(admin, req.headers.get('Authorization'));
    if (!who.ok) return J(refusalBody(who), who.status);
    const { email } = who;
    const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,registration_status,license_expiry,name_corrected_from').eq('claimed_by', email).maybeSingle();
    if (!sup) return J({ error: 'no_company', hint: 'claim your company first' }, 400);
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026). One gate, above the
    // action switch, so every screen this function serves is covered by one line rather than
    // forty — including the ones written after today. overview.ts already RENDERS a ban as a
    // banner; a banner is not a refusal, and this is the refusal.
    if (await sanctionedLead(admin, sup.id) || await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);
    const b = await req.json().catch(() => ({} as any));
    const action = b.action;

    const supId = sup.id;

    // THE OVERVIEW IN ONE CALL (15 Sep 2026): stats, alerts, eligibility, document impact and the
    // notification counts, every independent read started together. See ./overview.ts for the measurement.
    if (action === 'dashboard') { const r = await buildDashboard(admin, sup as Supplier); return J(r.body, r.status); }
    // The bell's two counts alone: what the portal re-reads after the supplier leaves Messages.
    if (action === 'notifications') return J({ ok: true, notifications: await buildNotifications(admin, supId) });

    if (action === 'overview') {
      const [{ data: stats, error }, { count: activeMatches }, alerts] = await Promise.all([
        admin.rpc('fn_supplier_stats', { p_supplier_id: supId }),
        admin.from('inquiry_matches').select('id', { count:'exact', head:true }).eq('supplier_id', supId),
        buildAlerts(admin, supId),
      ]);
      if (error) return loadFailed(String(action), error);
      return J({ ok:true, supplier: supplierCard(sup as Supplier), stats, active_matches: activeMatches || 0, alerts, alerts_count: alerts.length });
    }

    // ROW #5 §3 §4 §6 §13 — THE SUPPLIER'S OWN DIGITAL TWIN AND HEALTH PANEL.
    //
    // supplier_score holds `reliability` and `response_rate` non-null on 20,464 of 20,464 rows on
    // production, and until this action existed the supplier surface could reach NEITHER. The
    // portal already renders `{s.response_rate != null && <Stat …/>}` — a tile whose guard could
    // never be true, because no endpoint returned the field. This is that missing read path.
    //
    // The whole payload comes from ONE routine, fn_supplier_twin, so the numbers a supplier sees
    // are the numbers the database computed rather than a second derivation that can drift from it.
    if (action === 'twin') {
      // What the capability summary and the supplier's own service words MEAN is reasoned (think(),
      // _shared/reasoned_suppliers.ts; founder_instruction 886-903), once per text, AFTER this response:
      // the page never waits on a model, and under the hold the reading is queued and the twin shows the
      // capabilities from keyed data with capability_reading 'needs_reasoning'.
      runtimeWaitUntil()?.(readSupplierProfile(defaultDeps(admin, 'supplier_portal'), supId).catch((e) => console.error('supplier reading failed:', String(e))));
      const { data: twin, error } = await admin.rpc('fn_supplier_twin', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      // A demo fixture must never be presentable as a live account. fn_supplier_twin sets is_demo
      // from the fence itself (matching_blocked AND a 'demo' tag), so the flag cannot drift from
      // the thing it describes, and the UI can label the row rather than passing it off as real.
      return J({ ok: true, twin });
    }

    // ROW #5 §7 §8 — PRODUCT INTELLIGENCE.
    //
    // supplier_product, supplier_product_variant and supplier_catalog are a complete schema —
    // jsonb attributes, certifications, evidence_refs, catalog versioning by source_hash, variants
    // with price and lead-time policy — that had 0 rows AND 0 readers on production, confirmed by
    // two independent scans against a control. Built and abandoned. This is the read path.
    //
    // `q` searches names, brands, models, categories AND attribute values, so "5000 CFM" finds the
    // unit whose specification says so rather than only matching a title.
    // ROW #5 §15 §4 — THE AI EMPLOYEE. "Why am I losing RFQs?" answered from real columns.
    //
    // The loss BREAKDOWN is empty on purpose while there are 0 quotes estate-wide, and the payload
    // says `basis: 'no_completed_opportunities'` so an empty array is never mistaken for a failed
    // computation. The RECOMMENDATIONS half is real today: every gap is derived from a column the
    // supplier can act on, and impact_rfqs counts live inquiries rather than quoting the spec's
    // illustrative "32 more projects".
    // ROW #5 §19 — THE SUPPLIER NETWORK MAP. Supplier density by emirate from 20,464 real leads;
    // demand, projects and shipments return EMPTY with a stated basis, because there are 0
    // inquiries and no shipments relation at all. A globe speckled with invented demand looks like
    // market intelligence and is nothing.
    // ROW #5 §14 — MARKET INTELLIGENCE. Competitor counts and supply composition are real (20,464
    // leads with sectors and emirates). Demand trend, most-requested and average price are COMPUTED
    // from their populations and fall back to available:false with the empty population named — the
    // availability flag is derived from a count, not hard-coded, so the routine tells the truth on
    // both sides of the day a category starts trading. An arrow reading "HVAC demand up 18%" against
    // zero inquiries would be indistinguishable from real market intelligence on screen, so the
    // percentage stays NULL whenever the prior period is empty rather than being computed from zero.
    // Demo fixtures and live rows are partitioned symmetrically inside the routine, so the demo
    // market cannot move a real supplier's competitor count or market price.
    // ROW #5 §18 — COLLABORATION WORKSPACES, one per customer relationship. Seeded on both projects
    // with one fenced demo relationship (scripts/sql/demo_inquiry_row5.sql) under the founder's
    // standing "create demo for whatever is needed". The cost was stated rather than hidden: each
    // inquiry insert fires fn_emit_event('inquiry','rfq.created'), which injects a synthetic row
    // into row #2's separately-measured event backbone for that row's next run to subtract.
    if (action === 'workspaces') {
      const { data: ws, error } = await admin.rpc('fn_supplier_workspaces', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...ws });
    }

    if (action === 'market') {
      const { data: mkt, error } = await admin.rpc('fn_supplier_market', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...mkt });
    }

    // ROW #5 §11 — THE AI QUOTE BUILDER. fn_supplier_quote_recommend proposes the price, delivery,
    // warranty, terms, market position and risk for THIS supplier on ONE enquiry, computed from the
    // competing bids on that same enquiry. p_lead_id is the authenticated supplier, never a
    // parameter — a supplier must not be able to ask what someone else should charge, and the
    // routine's `your_index` leg reads that supplier's own pricing history.
    if (action === 'quote_recommend') {
      const inqId = String(b.inquiry_id || '');
      if (!inqId) return J({ error: 'inquiry_id required' }, 400);
      const { data: rec, error } = await admin.rpc('fn_supplier_quote_recommend',
        { p_lead_id: supId, p_inquiry_id: inqId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...rec });
    }

    // ROW #5 §16 §4 — WHAT EACH DOCUMENT IS EARNING, AND WHAT THE MISSING ONE IS COSTING.
    if (action === 'document_impact') {
      const { data: di, error } = await admin.rpc('fn_supplier_document_impact', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...di });
    }

    // ROW #5 §23 — THE KNOWLEDGE GRAPH, READ RATHER THAN REBUILT NIGHTLY AND IGNORED.
    // fn_supplier_knowledge_graph returns CATEGORY structure only: the categories this company is
    // listed in and the adjacent ones its competitors also serve, computed from lead_category's
    // 17,107 rows. Employee, department and goal nodes are QuotesDone's internal org chart and the
    // routine never selects them — a supplier is not an audience for our reporting lines.
    if (action === 'knowledge_graph') {
      const { data: kg, error } = await admin.rpc('fn_supplier_knowledge_graph', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...kg });
    }

    // §10 — RANKED OPPORTUNITIES. "Recommended for you", ordered by fit score and never by date.
    //
    // The ranking itself is fn_supplier_opportunities: it is a query over inquiries, leads and
    // quotes, so it belongs in SQL where the planner can see the indexes, not in a loop here
    // pulling rows across the wire to sort them. What this action must NOT do is re-sort the
    // result — a browser or an edge function reordering a list it already holds is not ranking,
    // and the routine has already ordered by fit_score desc.
    //
    // The reasons ride along with each opportunity: trade, location, capacity fits, and previous
    // similar project — each carrying whether it applied and, when it could not be asked at all,
    // why. With 0 completed jobs the history reason is unanswerable for EVERY supplier, and it
    // says so rather than reading as "you have no relevant experience".
    // §12 (the negotiation assistant) and the 3D network map action were removed 21 Sep 2026 — founder
    // instructions 525/526. fn_supplier_negotiation and fn_supplier_network_map are dropped by
    // scripts/sql/the_last_traces_of_bank_details_negotiations_and_the_network_map_leave.sql.

    if (action === 'product_match') {
      const inquiryId = String(b.inquiry_id || '');
      if (!inquiryId) return J({ error: 'inquiry_id required' }, 400);
      // WHICH OF HIS PRODUCTS THE ENQUIRY ASKS FOR IS REASONED, not counted in shared words (founder_instruction
      // 886-903; decision point 26): the routine hands back the enquiry and his products, think() reads them
      // (reasoned_matching.ts productsAsked), and the routine is asked again with the answer. Held: the list is
      // shown unscored with status 'needs_reasoning' — never a word-count percentage.
      const { data: pm, error } = await admin.rpc('fn_supplier_product_match',
        { p_inquiry_id: inquiryId, p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      // deno-lint-ignore no-explicit-any
      const tr: any = (pm as any)?.to_reason;
      if (!tr?.products?.length || !tr.want) return J({ ok: true, ...pm, to_reason: undefined });
      const asked = await productsAsked(defaultDeps(admin, 'supplier_portal'), { want: String(tr.want), products: tr.products, inquiryId, leadId: Number(supId) });
      if (asked.value == null) return J({ ok: true, ...pm, to_reason: undefined, held: true });
      const { data: pm2, error: e2 } = await admin.rpc('fn_supplier_product_match',
        { p_inquiry_id: inquiryId, p_lead_id: supId, p_asked: asked.value });
      if (e2) return loadFailed(String(action), e2);
      return J({ ok: true, ...pm2 });
    }

    // §16 §24 — every certificate with its validity status and what it gates.
    if (action === 'certifications') {
      const { data: certs, error } = await admin.rpc('fn_supplier_certifications', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...certs });
    }

    // §20 — the QuotesDone supplier tier and the ladder above it.
    if (action === 'tier') {
      const { data: tier, error } = await admin.rpc('fn_supplier_tier', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...tier });
    }

    if (action === 'opportunities') {
      const { data: opps, error } = await admin.rpc('fn_supplier_opportunities', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...opps });
    }

    if (action === 'advisor') {
      const { data: advice, error } = await admin.rpc('fn_supplier_advisor', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...advice });
    }

    if (action === 'products') {
      const { data: prods, error } = await admin.rpc('fn_supplier_products', {
        p_lead_id: supId,
        p_query: typeof b.q === 'string' && b.q.trim() ? b.q.trim().slice(0, 120) : null,
      });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...prods });
    }

    // WHICH INTELLIGENCE PANELS HAVE ANYTHING TO SAY (14 Sep 2026).
    //
    // The dashboard showed 24 equal tabs; twelve were panels over populations their own routines
    // report as empty (0 quotes and 0 inquiries estate-wide — see the ROW #5 notes above), and on a
    // 375px phone the strip alone was 366px tall. The portal now shows a journey and ONE "Insights"
    // section that lists only the panels answered here as available.
    //
    // Only two of these routines return a top-level `available` at all (grep of
    // scripts/sql/the_portals_come_back.sql, 14 Sep), so the rule is stated rather than assumed: a
    // panel is available when its routine answered without error, did not say `available:false`, and
    // its answer holds at least one non-empty list or positive number within two levels. The
    // routines express an empty population as zeros and empty arrays, never as a failure, so this is
    // the same fact they already report, read the same way for every panel.
    if (action === 'insights') {
      const hasSignal = (v: unknown, depth: number): boolean => {
        if (v == null || typeof v === 'string' || typeof v === 'boolean') return false;
        if (typeof v === 'number') return v > 0;
        if (Array.isArray(v)) return v.length > 0;
        if (depth <= 0) return false;
        return Object.values(v as Record<string, unknown>).some((x) => hasSignal(x, depth - 1));
      };
      const panels: [string, string, Record<string, unknown>][] = [
        ['twin', 'fn_supplier_twin', { p_lead_id: supId }],
        ['market', 'fn_supplier_market', { p_lead_id: supId }],
        ['network', 'fn_supplier_knowledge_graph', { p_lead_id: supId }],
        ['workspaces', 'fn_supplier_workspaces', { p_lead_id: supId }],
        ['recommended', 'fn_supplier_opportunities', { p_lead_id: supId }],
        ['ranking', 'fn_supplier_tier', { p_lead_id: supId }],
        ['certifications', 'fn_supplier_certifications', { p_lead_id: supId }],
        ['products', 'fn_supplier_products', { p_lead_id: supId, p_query: null }],
        ['assistant', 'fn_supplier_advisor', { p_lead_id: supId }],
      ];
      const out = await Promise.all(panels.map(async ([key, fn, args]) => {
        try {
          const { data, error } = await admin.rpc(fn, args);
          if (error) return { key, available: false, basis: 'routine_error' };
          const d = data as Record<string, unknown> | null;
          if (d && typeof d === 'object' && d.available === false) return { key, available: false, basis: String(d.basis || 'routine_reports_unavailable') };
          const ok = hasSignal(d, 2);
          return { key, available: ok, basis: ok ? 'data' : 'empty_population' };
        } catch (_e) { return { key, available: false, basis: 'routine_error' }; }
      }));
      return J({ ok: true, panels: out });
    }

    // ONE LIST, READ AFTER EVERY WRITE (audit 21 Sep 2026, finding 16). The Documents tab used to ask
    // for this list in a second round trip after each upload, and rendered the answer over its own
    // staged state; save_documents, remove_document and set_expiry now return the fresh list in the
    // same response, so the card, the counter and the unlock panel are painted from one read.
    if (action === 'documents') return J(await listDocuments(sup.id));

    if (action === 'save_documents') {
      // Capped (15 Sep 2026): every item is malware-scanned and licence/profile/catalogues are now
      // also read by code, one after another, inside an edge function's CPU budget. Nine document
      // kinds plus a handful of catalogues fits; supplier_api.process_docs is bounded to 7 the same way.
      const items = Array.isArray(b.items) ? b.items.slice(0, 15) : [];
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const saved: string[] = [];
      let licenceNotice = false;
      const failedUploads: { kind: string; reason: string }[] = [];  // NOT 'failed' - that name belongs to the module-level refusal helper above, and shadowing it here is how the raw Postgres message stayed in this reply until 22 Sep 2026.
      const { data: _isec } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_supplier_portal').maybeSingle();
      const INBOUND_SECRET = (_isec?.value as string) || '';
      // What each column holds BEFORE this save: a replaced file becomes a doc_versions row after the
      // write succeeds (instruction 524 — Replace keeps the previous version).
      const beforeCols = new Set<string>(); for (const k of Object.values(DOC_KINDS)) { beforeCols.add(k.pathCol); if (k.nameCol) beforeCols.add(k.nameCol); if (k.expCol) beforeCols.add(k.expCol); }
      const { data: beforeRow } = await admin.from('leads').select([...beforeCols].join(',')).eq('id', sup.id).maybeSingle();
      const before = (beforeRow || {}) as Record<string, unknown>;
      const aiOn = await flagOn('document_expiry_ai');
      const read: Record<string, ExpiryNote> = {};
      let catAppend: string[] = [];
      // Licence, profile and catalogues are also read by code into a trade proposal (15 Sep 2026,
      // _shared/supplier_doc_trades.ts) — the same reading supplier_api.process_docs does.
      const readQueue: DocIn[] = [];
      for (const it of items) {
        const kindStr = String(it.kind || '');
        if (kindStr === 'catalogs') {
          if (it.original_b64) {
            // AUDIT 9.1 (3 Aug 2026). Sanitised from the bytes before storage; see
            // supabase/functions/_shared/attachment.ts. A rejection is reported to the supplier
            // in `failed` rather than swallowed, so they are never told a document is on file
            // when it was refused.
            try {
              const sc = await sanitizeAndScan({ input: String(it.original_b64), declaredMime: it.mime, filename: it.filename || 'catalog', allow: SAFE_UPLOAD,
                                                 scan: { source: 'supplier_portal.catalogs', subject: String(sup.id), filename: it.filename, bucket: 'supplier-docs' } });
              if (!sc.ok) { failedUploads.push({ kind: 'catalogs', reason: String(sc.body.detail || sc.body.error) }); continue; }
              const s = sc.result;
              const p = `catalogs/${sup.id}/${Date.now()}_${safeFilename(it.filename || 'catalog', s.mime)}`;
              const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
              if (upErr) { failedUploads.push({ kind: 'catalogs', reason: upErr.message }); continue; }
              catAppend.push(p); saved.push('catalogs');
              readQueue.push({ path: p, name: String(it.filename || 'catalogue'), kind: 'catalogue', bytes: s.bytes, mime: s.mime });
            } catch (e) { failedUploads.push({ kind: 'catalogs', reason: String((e as Error)?.message || e).slice(0, 200) }); }
          }
          continue;
        }
        const kind = DOC_KINDS[kindStr]; if (!kind) continue;
        // The sanitised bytes, kept for the expiry read below; null when nothing was uploaded.
        let stored: { bytes: Uint8Array; mime: string } | null = null;
        if (it.original_b64) {
          // Previously any upload failure was swallowed and the kind was still reported as
          // saved, so a supplier could be told their trade licence was on file when the
          // storage write had failed. Failures are now returned to the caller.
          try {
            // AUDIT 9.1 (3 Aug 2026). These are trade licences, insurance certificates and ISO
            // certificates - documents an admin opens in a browser during review. Before this they
            // were stored as whatever the caller declared, defaulting to application/octet-stream,
            // with the extension taken from the caller's filename. The type is now decided from the
            // bytes and the extension is forced to match it.
            const sc = await sanitizeAndScan({ input: String(it.original_b64), declaredMime: it.mime, filename: it.filename || kindStr, allow: SAFE_UPLOAD,
                                               scan: { source: 'supplier_portal.' + kindStr, subject: String(sup.id), filename: it.filename, bucket: 'supplier-docs' } });
            if (!sc.ok) { failedUploads.push({ kind: kindStr, reason: String(sc.body.detail || sc.body.error) }); continue; }
            const s = sc.result;
            const clean = safeFilename(it.filename || kindStr, s.mime);
            const p = `${kind.folder}/${sup.id}/${Date.now()}_${clean}`;
            const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
            if (upErr) { failedUploads.push({ kind: kindStr, reason: upErr.message }); continue; }
            upd[kind.pathCol] = p;
            if (kind.nameCol) upd[kind.nameCol] = clean.slice(0, 200);
            stored = { bytes: s.bytes, mime: s.mime };
            if (kindStr === 'license' || kindStr === 'profile') readQueue.push({ path: p, name: clean, kind: kindStr === 'license' ? 'licence' : 'profile', bytes: s.bytes, mime: s.mime });
          } catch (e) { failedUploads.push({ kind: kindStr, reason: String((e as Error)?.message || e).slice(0, 200) }); continue; }
        }
        // #86: read the trade-licence expiry (and licence no / authority) SERVER-SIDE from the
        // uploaded document, so the expiry gate can't be bypassed with a self-typed date. The typed
        // value is used only as a fallback when extraction fails or the document has no clear date.
        let licExpiryFromDoc = false;
        // INSTRUCTION 524: code reads the date first. For every kind that carries an expiry the
        // stored bytes are read by _shared/document_expiry.ts (text-stream PDFs; a scan returns
        // null and is said so). The licence keeps #86 — a read date is written, a typed one never
        // is. Insurance / ISO / manufacturer: a typed date is written as before; a date read off
        // the document is RETURNED for the supplier to confirm (set_expiry) and never written
        // unconfirmed. Nothing is ever invented.
        let docRead: ExpiryRead | null = null;
        if (kind.expCol && stored) { try { docRead = await readExpiry(stored.bytes, stored.mime); } catch (_e) { docRead = null; } }
        if (kindStr === 'license' && docRead) {
          upd.license_expiry = docRead.expiry; licExpiryFromDoc = true; upd.doc_extracted_at = new Date().toISOString();
          read.license = { kind: 'license', expiry: docRead.expiry, source: 'text', needs_confirm: false, typed: null };
        } else if (kind.expCol && kindStr !== 'license' && stored) {
          const typed = it.expiry ? String(it.expiry).slice(0, 10) : null;
          if (docRead) read[kindStr] = { kind: kindStr, expiry: docRead.expiry, source: 'text', needs_confirm: !typed || typed !== docRead.expiry, typed };
          else if (aiOn && INBOUND_SECRET) {
            // The model path, only behind the flag: license_extract 'cert' mode already pulls the
            // governing date off an insurance schedule, ISO certificate or dealer letter.
            try {
              const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: INBOUND_SECRET, mode: 'cert', file_b64: String(it.original_b64), mime: it.mime, filename: it.filename }) });
              const jd = await r.json();
              if (jd?.ok && jd.found_expiry && jd.cert?.expiry_date) read[kindStr] = { kind: kindStr, expiry: String(jd.cert.expiry_date), source: 'ai', needs_confirm: true, typed };
            } catch (_e) { /* the honest 'unread' note below */ }
            if (!read[kindStr]) read[kindStr] = { kind: kindStr, expiry: null, source: null, needs_confirm: false, typed, unread: true };
          } else read[kindStr] = { kind: kindStr, expiry: null, source: null, needs_confirm: false, typed, unread: true };
        }
        if (kindStr === 'license' && !licExpiryFromDoc && it.original_b64 && !(aiOn && INBOUND_SECRET)) {
          read.license = { kind: 'license', expiry: null, source: null, needs_confirm: false, typed: null, unread: true };
        }
        if (kindStr === 'license' && !licExpiryFromDoc && it.original_b64 && aiOn && INBOUND_SECRET) {
          try {
            const isImg = /^image\//.test(String(it.mime || ''));
            const payload: Record<string, unknown> = isImg
              ? { __secret: INBOUND_SECRET, mode: 'license', images: [{ b64: String(it.original_b64), mime: it.mime }] }
              : { __secret: INBOUND_SECRET, mode: 'license', file_b64: String(it.original_b64), mime: it.mime, filename: it.filename };
            const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
            const jd = await r.json();
            if (jd?.ok && jd.doc) {
              const d = jd.doc;
              if (d.expiry_date) { upd.license_expiry = d.expiry_date; licExpiryFromDoc = true; read.license = { kind: 'license', expiry: String(d.expiry_date), source: 'ai', needs_confirm: false, typed: null }; }
              if (d.license_number) upd.trade_license_no = d.license_number;
              if (d.license_authority) upd.license_authority = d.license_authority;
              if (d.city) upd.license_city = d.city;
              upd.doc_extracted_at = new Date().toISOString();
            }
          } catch (_e) { /* fall back to the typed value below */ }
          if (!licExpiryFromDoc) read.license = { kind: 'license', expiry: null, source: null, needs_confirm: false, typed: null, unread: true };
        }
        // LICENCE EXPIRY FIX 27 Jul 2026. The fallback above ran whenever extraction had not produced
        // a date - including when NO document was attached at all, since the extraction block requires
        // it.original_b64. A supplier could therefore POST { kind:'license', expiry:'2030-01-01' } with
        // no file and push their own licence expiry three years out, which defeats the whole point of
        // #86 and of fn_reconcile_doc_blocks (the daily job that suspends matching on an expired
        // licence). license_expiry is now only ever written from what license_extract read off the
        // document; a typed licence expiry is never trusted. Other kinds keep the typed value - none of
        // them is read server-side and none of them is self-asserted against an automatic suspension.
        if (kindStr === 'license') {
          if (!licExpiryFromDoc && it.expiry) {
            failedUploads.push(it.original_b64
              ? { kind: kindStr, reason: 'Your trade licence file was saved, but we could not read the expiry date from it, so the expiry on file is unchanged. Please upload a clear copy of the full licence page (PDF or a sharp photo).' }
              : { kind: kindStr, reason: 'A trade licence document is required. The licence expiry is read from the licence itself and cannot be entered by hand — please attach your current trade licence.' });
            if (!it.original_b64) continue;
          }
        } else if (kind.expCol && it.expiry) upd[kind.expCol] = String(it.expiry).slice(0, 10);
        saved.push(kindStr);
      }
      if (catAppend.length) {
        const { data: cur } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const existing: string[] = Array.isArray(cur?.catalog_doc_paths) ? (cur!.catalog_doc_paths as string[]) : [];
        upd.catalog_doc_paths = [...existing, ...catAppend].slice(0, 20);
      }
      // 5 Aug 2026. The uploads above report per-file outcomes in `saved`/`failed`, but THIS write
      // is what attaches any of them to the supplier. Its result was discarded, so a failed write
      // reported every file as saved while no path ever reached the row — the same defect as
      // supplier_api's process_docs and save_profile.
      if (Object.keys(upd).length > 1) {
        // A licence number another claimed company holds is set aside, the rest of the row is written,
        // and the clash goes to a human (_shared/duplicate_company.ts, review of #962).
        const { error: updErr, licenceSetAside } = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, sup.id, upd, 'supplier_portal.save_documents');
        if (licenceSetAside) { licenceNotice = true; failedUploads.push({ kind: 'license', reason: COMPANY_ALREADY_REGISTERED.error }); }
        if (updErr) {
          // SP-I-01, the one that survived #858 (review, 22 Sep 2026): this still put the raw
          // Postgres text in `detail` for the browser. Same treatment as the other thirteen — the
          // real message goes to the function log, the supplier gets the stable code.
          return failed('save_documents', 'save_failed', 'Your files were uploaded but could not be attached to your profile. Please try again.', updErr, 502);
        }
      }
      // REPLACE KEEPS THE PREVIOUS VERSION. After the row write succeeded, every column that held a
      // file and now holds another becomes a doc_versions row (entity 'supplier_document',
      // '<lead>:<kind>'). The old object stays in storage and in the Dropbox backup.
      const versioned: string[] = [];
      for (const [kindStr, k] of Object.entries(DOC_KINDS)) {
        const prev = before[k.pathCol] as string | null;
        if (!prev || upd[k.pathCol] === undefined || upd[k.pathCol] === prev) continue;
        const snap: VersionSnapshot = { event: 'replaced', kind: kindStr, path: prev, name: (k.nameCol ? (before[k.nameCol] as string) : null) || prev.split('/').pop() || null,
          expiry: k.expCol ? ((before[k.expCol] as string) || null) : null, at: new Date().toISOString() };
        const { data: v } = await admin.rpc('_next_docver', { p_type: 'supplier_document', p_id: `${sup.id}:${kindStr}` });
        const { error: vErr } = await admin.from('doc_versions').insert(versionRow(Number(sup.id), snap, Number(v || 1)));
        if (!vErr) versioned.push(kindStr); else console.error('save_documents: version row failed —', vErr.message);
      }
      const documents_read = readQueue.length ? await proposeTradesFromDocs(admin, Number(sup.id), readQueue.slice(0, 7)) : undefined;
      // The fresh list rides on the answer (finding 16): what the row holds NOW, not what the tab guessed.
      const fresh = await listDocuments(Number(sup.id));
      return J({ ok:true, saved, failed: failedUploads, ...(licenceNotice ? { licence_set_aside: true, licence_notice: COMPANY_ALREADY_REGISTERED } : {}), read, versioned, documents: fresh.documents, expiries: fresh.expiries, summary: fresh.summary, ...(documents_read ? { documents_read } : {}) });
    }

    // REMOVE HIDES, NEVER DESTROYS (instruction 524). The column is cleared and what it held goes to
    // doc_versions; the storage object and its backup stay. Refused, with a readable reason, on a
    // mandatory-six document of an approved supplier (./document_actions.ts). A sanctioned party is
    // refused above the switch. Catalogues: one path out of the array, the same way.
    if (action === 'remove_document') {
      const kindStr = String(b.kind || '');
      const ar = String(b.lang || '') === 'ar';
      if (kindStr === 'catalogs') {
        const path = String(b.path || '');
        const { data: cur } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const list: string[] = Array.isArray(cur?.catalog_doc_paths) ? (cur!.catalog_doc_paths as string[]) : [];
        if (!path || !list.includes(path)) { const r = removeRefusal({ kind: kindStr, known: true, onFile: false, required: false, approval_status: sup.approval_status })!; return J({ ok: false, error: 'remove_refused', code: r.code, message: ar ? r.message_ar : r.message }, 409); }
        const { error } = await admin.from('leads').update({ catalog_doc_paths: list.filter((p) => p !== path), portal_updated_at: new Date().toISOString() }).eq('id', sup.id);
        if (error) return failed('remove_document', 'remove_failed', 'We could not remove that document. Please try again.', error, 502);
        const snap: VersionSnapshot = { event: 'removed', kind: 'catalogs', path, name: path.split('/').pop() || null, expiry: null, at: new Date().toISOString() };
        const { data: v } = await admin.rpc('_next_docver', { p_type: 'supplier_document', p_id: `${sup.id}:catalogs` });
        await admin.from('doc_versions').insert(versionRow(Number(sup.id), snap, Number(v || 1)));
        return J({ ok: true, removed: 'catalogs', path });
      }
      const kind = DOC_KINDS[kindStr];
      const cols = kind ? [kind.pathCol, kind.nameCol, kind.expCol].filter(Boolean) as string[] : [];
      const { data: cur } = kind ? await admin.from('leads').select(cols.join(',')).eq('id', sup.id).maybeSingle() : { data: null };
      const row = (cur || {}) as Record<string, unknown>;
      const prev = kind ? (row[kind.pathCol] as string | null) : null;
      const refusal = removeRefusal({ kind: kindStr, known: !!kind, onFile: !!prev, required: REQUIRED_DOC_KEYS.includes(kindStr), approval_status: sup.approval_status });
      if (refusal || !kind || !prev) { const r = refusal!; return J({ ok: false, error: 'remove_refused', code: r.code, message: ar ? r.message_ar : r.message }, r.code === 'mandatory_of_approved' ? 409 : 400); }
      const clear: Record<string, unknown> = { [kind.pathCol]: null, portal_updated_at: new Date().toISOString() };
      if (kind.nameCol) clear[kind.nameCol] = null;
      if (kind.expCol) clear[kind.expCol] = null;
      const { error } = await admin.from('leads').update(clear).eq('id', sup.id);
      if (error) return failed('remove_document', 'remove_failed', 'We could not remove that document. Please try again.', error, 502);
      const snap: VersionSnapshot = { event: 'removed', kind: kindStr, path: prev, name: (kind.nameCol ? (row[kind.nameCol] as string) : null) || prev.split('/').pop() || null,
        expiry: kind.expCol ? ((row[kind.expCol] as string) || null) : null, at: new Date().toISOString() };
      const { data: v } = await admin.rpc('_next_docver', { p_type: 'supplier_document', p_id: `${sup.id}:${kindStr}` });
      await admin.from('doc_versions').insert(versionRow(Number(sup.id), snap, Number(v || 1)));
      const fresh = await listDocuments(Number(sup.id));
      return J({ ok: true, removed: kindStr, documents: fresh.documents, expiries: fresh.expiries, summary: fresh.summary });
    }

    // THE SUPPLIER CONFIRMS A DATE THE DOCUMENT WAS READ TO SAY (instruction 524). Only for the kinds
    // whose expiry a supplier may state — never the licence, whose date is written from the licence
    // alone (#86). The value is what the portal showed them, or what they corrected it to.
    if (action === 'set_expiry') {
      const kindStr = String(b.kind || '');
      const kind = DOC_KINDS[kindStr];
      if (!kind || !kind.expCol || kindStr === 'license') return J({ error: 'expiry_not_settable', kind: kindStr }, 400);
      const expiry = String(b.expiry || '').slice(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(expiry) || isNaN(Date.parse(expiry))) return J({ error: 'bad_expiry' }, 400);
      const { data: cur } = await admin.from('leads').select(kind.pathCol).eq('id', sup.id).maybeSingle();
      if (!(cur as Record<string, unknown> | null)?.[kind.pathCol]) return J({ error: 'nothing_on_file', kind: kindStr }, 409);
      const { error } = await admin.from('leads').update({ [kind.expCol]: expiry, portal_updated_at: new Date().toISOString() }).eq('id', sup.id);
      if (error) return failed('set_expiry', 'expiry_save_failed', 'We could not save that expiry date. Please try again.', error, 502);
      const fresh = await listDocuments(Number(sup.id));
      return J({ ok: true, kind: kindStr, expiry, documents: fresh.documents, expiries: fresh.expiries, summary: fresh.summary });
    }

    // Why am I not being matched? The builder and the reasoning behind every item: ./overview.ts.
    if (action === 'eligibility') return J(await buildEligibility(admin, supId));

    // THE INSIGHTS TAB AS DATA (15 Sep 2026): totals, price position, funnel, 12-month series and
    // coded hints. ./insights_summary.ts; the contract is docs/api/supplier_portal_messages_documents_insights.md.
    if (action === 'insights_summary') {
      const r = await buildInsightsSummary(admin, supId, buildEligibility(admin, supId).then((e) => !!e.eligible));
      return J(r.body, r.status);
    }

    // SUPPORTING COMPANY DOCUMENTS (15 Sep 2026): any document besides the fixed kinds above.
    // ./supporting_documents.ts says where each file goes and why it reaches Dropbox.
    if (action === 'supporting_documents' || action === 'supporting_document_save' || action === 'supporting_document_delete' || action === 'supporting_document_url') {
      const signOne = (p: string) => sign('supplier-docs', p);
      let r;
      if (action === 'supporting_documents') r = await listSupporting(admin, supId, signOne);
      else if (action === 'supporting_document_delete') r = await deleteSupporting(admin, supId, b.id);
      else if (action === 'supporting_document_url') r = await urlSupporting(admin, supId, b.id, signOne);
      else r = await saveSupporting(admin, supId, b, {
        sign: signOne, safeFilename,
        scan: async ({ b64, mime, filename }) => {
          const sc = await sanitizeAndScan({ input: b64, declaredMime: mime, filename, allow: SAFE_UPLOAD,
                                             scan: { source: 'supplier_portal.supporting', subject: String(supId), filename, bucket: 'supplier-docs' } });
          return sc.ok ? { ok: true, bytes: sc.result.bytes, mime: sc.result.mime } : { ok: false, reason: String(sc.body.detail || sc.body.error) };
        },
        upload: async (path, bytes, mime) => {
          const { error } = await admin.storage.from('supplier-docs').upload(path, bytes, { contentType: mime, upsert: false });
          return { error: error ? error.message : null };
        },
      });
      return J(r.body, r.status);
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return failed('request', 'unexpected_error', 'Something went wrong. Please try again.', e as Error); }
}));
