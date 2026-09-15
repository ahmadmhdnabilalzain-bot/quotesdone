// supplier_portal v5 — advanced supplier dashboard API. Supplier-authed (own leads row via claimed_by).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD } from '../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. A refused file is reported in `failed`
// exactly as a refused SHAPE already was, so a supplier is never told a document is on file when
// the scanner refused it.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { REQUIRED_DOC_KEYS } from '../_shared/supplier_registration.ts';
import { buildAlerts, buildDashboard, buildEligibility, buildNotifications, supplierCard, type Supplier } from './overview.ts';
import { proposeTradesFromDocs, type DocIn } from '../_shared/supplier_doc_trades.ts';
// SUPPLIER-FACING TEXT CARRIES A CODE (14 Sep 2026). Every sentence below that reaches a supplier
// (document hints, alerts, eligibility titles/details) now travels with a stable `code` and `params`;
// the portal renders the EN/AR wording from src/components/portal/supplier/serverCopy.ts and falls
// back to the English here, which is kept verbatim for emails and older clients.
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
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
  license:      { pathCol:'license_doc_path',           nameCol:'license_doc_name', expCol:'license_expiry',            label:'Trade licence',              folder:'licence',   hint:'Required. Your current DED / free-zone trade licence.' },
  profile:      { pathCol:'company_profile_doc_path',                               expCol:null,                        label:'Company profile',            folder:'profile',   hint:'Required. Your company introduction deck or PDF. Shown to customers after a reveal.' },
  vat:          { pathCol:'vat_doc_path',                                           expCol:null,                        label:'VAT certificate',            folder:'certs',     hint:'Your TRN certificate. Needed before you can invoice with VAT.' },
  insurance:    { pathCol:'insurance_doc_path',                                     expCol:'insurance_expiry',          label:'Insurance',                  folder:'certs',     hint:'Public liability or contractor all-risk cover.' },
  iso:          { pathCol:'iso_doc_path',                                           expCol:'iso_expiry',                label:'ISO certification',          folder:'certs',     hint:'Any ISO certificate you hold. Strengthens your capability score.' },
  manufacturer: { pathCol:'manufacturer_auth_doc_path',                             expCol:'manufacturer_auth_expiry',  label:'Manufacturer authorisation', folder:'certs',     hint:'Authorised-dealer letters from the brands you carry.' },
  egr:          { pathCol:'egr_doc_path',               nameCol:'egr_doc_name',     expCol:null,                        label:'Establishment card',         folder:'certs',     hint:'Your immigration establishment card (EGR).' },
  iban:         { pathCol:'iban_doc_path',              nameCol:'iban_doc_name',    expCol:null,                        label:'Bank details (IBAN)',        folder:'certs',     hint:'Bank letter confirming your IBAN. Used to pay you.' },
};
const DOC_ORDER = ['license','profile','catalogs','vat','insurance','iso','manufacturer','egr','iban'];

Deno.serve(observe('supplier_portal', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,registration_status,license_expiry,name_corrected_from').eq('claimed_by', email).maybeSingle();
    if (!sup) return J({ error: 'no_company', hint: 'claim your company first' }, 400);
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
      if (error) return J({ error: error.message }, 500);
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
      const { data: twin, error } = await admin.rpc('fn_supplier_twin', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
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
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...ws });
    }

    if (action === 'market') {
      const { data: mkt, error } = await admin.rpc('fn_supplier_market', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
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
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...rec });
    }

    // ROW #5 §16 §4 — WHAT EACH DOCUMENT IS EARNING, AND WHAT THE MISSING ONE IS COSTING.
    if (action === 'document_impact') {
      const { data: di, error } = await admin.rpc('fn_supplier_document_impact', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...di });
    }

    // ROW #5 §23 — THE KNOWLEDGE GRAPH, READ RATHER THAN REBUILT NIGHTLY AND IGNORED.
    // fn_supplier_knowledge_graph returns CATEGORY structure only: the categories this company is
    // listed in and the adjacent ones its competitors also serve, computed from lead_category's
    // 17,107 rows. Employee, department and goal nodes are QuotesDone's internal org chart and the
    // routine never selects them — a supplier is not an audience for our reporting lines.
    if (action === 'knowledge_graph') {
      const { data: kg, error } = await admin.rpc('fn_supplier_knowledge_graph', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...kg });
    }

    if (action === 'network_map') {
      const { data: map, error } = await admin.rpc('fn_supplier_network_map');
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...map });
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
    // §12 — THE NEGOTIATION ASSISTANT. Detect a discount request, show the arithmetic, draft a reply.
    //
    // Two halves, deliberately split. fn_supplier_negotiation does the ARITHMETIC — quote, app fee,
    // customer price, reduction scenarios — because it is a query and it must be exact. The DETECTION
    // is a language problem ("can you sharpen that?", "the other guy is cheaper", "budget is 170")
    // and goes to the model.
    //
    // WHAT THE DRAFT MAY NOT DO IS CONCEDE. QuotesDone does not know what the job costs the supplier,
    // so any draft that names a discount would be advising a cut against a floor nobody knows. The
    // prompt forbids proposing a number; the draft acknowledges the request and puts the decision
    // back to the supplier, who is the only party holding the cost.
    if (action === 'negotiation') {
      // quote_id is optional: with none given this analyses the supplier's most recent quote, which
      // is the one a customer is almost certainly pushing back on. Ownership is enforced either way
      // — the lookup is always scoped to supId, so a supplier can only ever analyse their own.
      let quoteId = String(b.quote_id || '');
      if (quoteId) {
        const { data: own } = await admin.from('quotes').select('id').eq('id', quoteId).eq('supplier_id', supId).maybeSingle();
        if (!own) return J({ error: 'not your quote' }, 403);
      } else {
        const { data: latest } = await admin.from('quotes').select('id')
          .eq('supplier_id', supId).order('created_at', { ascending: false }).limit(1).maybeSingle();
        if (!latest) return J({ ok: true, quote_id: null, population: { customer_messages: 0, note: 'you have not submitted a quote yet, so there is nothing to negotiate' } });
        quoteId = latest.id;
      }

      const { data: neg, error } = await admin.rpc('fn_supplier_negotiation', { p_quote_id: quoteId });
      if (error) return J({ error: error.message }, 500);

      const inbound = (neg?.inbound_messages || []) as { body: string }[];
      let analysis: Record<string, unknown> = {
        price_pressure_detected: false,
        detection: 'no customer message to read yet',
        recommended_response: null,
      };
      if (inbound.length) {
        const { data: keyRow } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
        if (keyRow?.value) {
          const SYS = `You read a UAE construction customer's messages to a supplier and classify whether they are asking for a DISCOUNT or applying price pressure.
Return STRICT JSON only: {"price_pressure_detected":boolean,"detection":string,"signals":[string],"recommended_response":string}
- price_pressure_detected: true only if they actually push on price — a request to lower it, a competitor comparison, a stated budget below the quote. Asking what something costs is not pressure.
- detection: one sentence naming what you saw, quoting their words.
- signals: the exact phrases that made you decide. Empty if none.
- recommended_response: a short, warm reply the supplier could send. NEVER propose a discount, a percentage or a new price — you do not know what this job costs them. Acknowledge the request, restate the value in their quote (lead time, warranty, scope), and ask what is driving the number. If there is no price pressure, reply to what they actually asked instead.`;
          try {
            const r = await fetch(SUPA_URL + '/functions/v1/ai_gateway', {
              method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                __secret: keyRow.value, fn: 'supplier_negotiation', max: 700, temperature: 0.2,
                sys: SYS, response_format: 'json',
                input: [{ role: 'user', content: inbound.map((m) => m.body).join('\n---\n').slice(0, 6000) }],
              }),
            });
            const d = await r.json();
            const txt = String(d?.content || '{}');
            analysis = JSON.parse(txt.match(/\{[\s\S]*\}/)?.[0] || '{}');
          } catch (e) {
            // A model failure must not read as "no discount was requested" — that is the one wrong
            // answer that costs the supplier money.
            analysis = { price_pressure_detected: null, detection: 'the analysis could not run: ' + String((e as Error)?.message || e), recommended_response: null };
          }
        }
      }
      return J({ ok: true, ...neg, analysis });
    }

    // §8 — which of MY products answers this enquiry, and how well. The match_pct on a product card
    // is computed by fn_supplier_product_match and never in the browser: a percentage the client
    // invents is a decoration, and the supplier cannot tell the difference by looking.
    if (action === 'product_match') {
      const inquiryId = String(b.inquiry_id || '');
      if (!inquiryId) return J({ error: 'inquiry_id required' }, 400);
      const { data: pm, error } = await admin.rpc('fn_supplier_product_match',
        { p_inquiry_id: inquiryId, p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...pm });
    }

    // §16 §24 — every certificate with its validity status and what it gates.
    if (action === 'certifications') {
      const { data: certs, error } = await admin.rpc('fn_supplier_certifications', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...certs });
    }

    // §20 — the QuotesDone supplier tier and the ladder above it.
    if (action === 'tier') {
      const { data: tier, error } = await admin.rpc('fn_supplier_tier', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...tier });
    }

    if (action === 'opportunities') {
      const { data: opps, error } = await admin.rpc('fn_supplier_opportunities', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...opps });
    }

    if (action === 'advisor') {
      const { data: advice, error } = await admin.rpc('fn_supplier_advisor', { p_lead_id: supId });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, ...advice });
    }

    if (action === 'products') {
      const { data: prods, error } = await admin.rpc('fn_supplier_products', {
        p_lead_id: supId,
        p_query: typeof b.q === 'string' && b.q.trim() ? b.q.trim().slice(0, 120) : null,
      });
      if (error) return J({ error: error.message }, 500);
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
        ['network', 'fn_supplier_network_map', {}],
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
      // Negotiation reads one of this supplier's quotes; with none there is nothing to negotiate.
      const { count: myQuotes } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('supplier_id', supId);
      out.push({ key: 'negotiation', available: (myQuotes || 0) > 0, basis: (myQuotes || 0) > 0 ? 'data' : 'no_quotes' });
      return J({ ok: true, panels: out });
    }

    if (action === 'documents') {
      // Column list is derived from DOC_KINDS so adding a document type here needs no edit below.
      const cols = new Set<string>(['catalog_doc_paths']);
      for (const k of Object.values(DOC_KINDS)) { cols.add(k.pathCol); if (k.nameCol) cols.add(k.nameCol); if (k.expCol) cols.add(k.expCol); }
      const { data: l } = await admin.from('leads').select([...cols].join(',')).eq('id', sup.id).maybeSingle();
      const row = (l || {}) as Record<string, unknown>;

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
        const path = (row[k.pathCol] as string) || null;
        const expiry = k.expCol ? ((row[k.expCol] as string) || null) : null;
        // Filename falls back to the stored path's tail so the supplier always sees which file is on record.
        const name = (k.nameCol ? (row[k.nameCol] as string) : null) || (path ? String(path).split('/').pop() : null) || null;
        let status = 'missing';
        if (path) {
          status = 'on_file';
          if (expiry) {
            const d = Math.round((new Date(expiry).getTime() - today.getTime()) / 864e5);
            status = d < 0 ? 'expired' : d <= 30 ? 'expiring' : 'valid';
          }
        }
        docs.push({ key, label: k.label, hint: k.hint, path, name, expiry, has_expiry: !!k.expCol,
          // The mandatory six (_shared/supplier_registration.ts): licence AND company profile. This
          // said `key === 'license'` while the same tab's heading listed three required documents.
          required: REQUIRED_DOC_KEYS.includes(key), hint_code: 'doc_hint_' + key, status, url: await sign('supplier-docs', path) });
      }

      const required = docs.filter((d) => d.required);
      const complete = docs.filter((d) => d.status !== 'missing').length;
      const expiries = await admin.rpc('fn_supplier_expiries', { p_supplier_id: sup.id });
      return J({ ok:true, documents: docs, expiries: expiries.data || [],
        summary: { total: docs.length, on_file: complete, missing: docs.length - complete,
          required_missing: required.filter((d) => d.status === 'missing').length,
          attention: docs.filter((d) => d.status === 'expired' || d.status === 'expiring').length } });
    }

    if (action === 'save_documents') {
      // Capped (15 Sep 2026): every item is malware-scanned and licence/profile/catalogues are now
      // also read by code, one after another, inside an edge function's CPU budget. Nine document
      // kinds plus a handful of catalogues fits; supplier_api.process_docs is bounded to 7 the same way.
      const items = Array.isArray(b.items) ? b.items.slice(0, 15) : [];
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const saved: string[] = [];
      const failed: { kind: string; reason: string }[] = [];
      const { data: _isec } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_supplier_portal').maybeSingle();
      const INBOUND_SECRET = (_isec?.value as string) || '';
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
              if (!sc.ok) { failed.push({ kind: 'catalogs', reason: String(sc.body.detail || sc.body.error) }); continue; }
              const s = sc.result;
              const p = `catalogs/${sup.id}/${Date.now()}_${safeFilename(it.filename || 'catalog', s.mime)}`;
              const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
              if (upErr) { failed.push({ kind: 'catalogs', reason: upErr.message }); continue; }
              catAppend.push(p); saved.push('catalogs');
              readQueue.push({ path: p, name: String(it.filename || 'catalogue'), kind: 'catalogue', bytes: s.bytes, mime: s.mime });
            } catch (e) { failed.push({ kind: 'catalogs', reason: String((e as Error)?.message || e).slice(0, 200) }); }
          }
          continue;
        }
        const kind = DOC_KINDS[kindStr]; if (!kind) continue;
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
            if (!sc.ok) { failed.push({ kind: kindStr, reason: String(sc.body.detail || sc.body.error) }); continue; }
            const s = sc.result;
            const clean = safeFilename(it.filename || kindStr, s.mime);
            const p = `${kind.folder}/${sup.id}/${Date.now()}_${clean}`;
            const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
            if (upErr) { failed.push({ kind: kindStr, reason: upErr.message }); continue; }
            upd[kind.pathCol] = p;
            if (kind.nameCol) upd[kind.nameCol] = clean.slice(0, 200);
            if (kindStr === 'license' || kindStr === 'profile') readQueue.push({ path: p, name: clean, kind: kindStr === 'license' ? 'licence' : 'profile', bytes: s.bytes, mime: s.mime });
          } catch (e) { failed.push({ kind: kindStr, reason: String((e as Error)?.message || e).slice(0, 200) }); continue; }
        }
        // #86: read the trade-licence expiry (and licence no / authority) SERVER-SIDE from the
        // uploaded document, so the expiry gate can't be bypassed with a self-typed date. The typed
        // value is used only as a fallback when extraction fails or the document has no clear date.
        let licExpiryFromDoc = false;
        if (kindStr === 'license' && it.original_b64 && INBOUND_SECRET) {
          try {
            const isImg = /^image\//.test(String(it.mime || ''));
            const payload: Record<string, unknown> = isImg
              ? { __secret: INBOUND_SECRET, mode: 'license', images: [{ b64: String(it.original_b64), mime: it.mime }] }
              : { __secret: INBOUND_SECRET, mode: 'license', file_b64: String(it.original_b64), mime: it.mime, filename: it.filename };
            const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
            const jd = await r.json();
            if (jd?.ok && jd.doc) {
              const d = jd.doc;
              if (d.expiry_date) { upd.license_expiry = d.expiry_date; licExpiryFromDoc = true; }
              if (d.license_number) upd.trade_license_no = d.license_number;
              if (d.license_authority) upd.license_authority = d.license_authority;
              if (d.city) upd.license_city = d.city;
              upd.doc_extracted_at = new Date().toISOString();
            }
          } catch (_e) { /* fall back to the typed value below */ }
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
            failed.push(it.original_b64
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
        const { error: updErr } = await admin.from('leads').update(upd).eq('id', sup.id);
        if (updErr) {
          console.error('save_documents: leads update failed —', updErr.message);
          return J({ error:'save_failed', detail: updErr.message, saved, failed, message:'Your files were uploaded but could not be attached to your profile. Please try again.' }, 502);
        }
      }
      const documents_read = readQueue.length ? await proposeTradesFromDocs(admin, Number(sup.id), readQueue.slice(0, 7)) : undefined;
      return J({ ok:true, saved, failed, ...(documents_read ? { documents_read } : {}) });
    }

    // Why am I not being matched? The builder and the reasoning behind every item: ./overview.ts.
    if (action === 'eligibility') return J(await buildEligibility(admin, supId));

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
