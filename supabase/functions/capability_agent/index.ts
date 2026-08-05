// capability_agent — reads a supplier's OWN documents (trade licence + company profile, and the
// catalogue when the first two are not enough), works out EXACTLY what work they can take on against
// the controlled vocabulary, tells them precisely what is missing if it cannot, and then records what
// THE SUPPLIER CONFIRMS as the source of truth.
//
// Why confirmation rather than pure extraction: the supplier is the only party who actually knows their
// scope. Having them confirm corrects extraction error at source, populates the negative scope
// (exclusions) that stops irrelevant inquiries, and gives us their explicit agreement to what they will
// receive — which matters the day a supplier disputes a match.
//
// Nothing here is wired into live matching. Secret-guarded; called server-side only.
// actions: analyze | confirm | state
// v2: probe_text — secret-guarded diagnostic that analyses supplied text instead of stored documents,
//     so extraction quality can be tested ("would this profile be enough?") without an upload. Never persists.
// v3: the model call goes through ai_gateway (multimodal passthrough), so the model ladder, routing,
//     budget and cost logging all live in one place instead of here.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
const AGENT_VERSION = 'capability_agent@2';
const BUCKET = 'supplier-docs';
const MAX_BYTES = 8 * 1024 * 1024;

async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t: string) { let s = String(t || '').trim(); const f = s.match(/```(?:json)?\s*([\s\S]*?)```/i); if (f) s = f[1].trim(); try { return JSON.parse(s); } catch { const m = s.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; } }
function clip(v: unknown, n: number) { return String(v == null ? '' : v).slice(0, n); }
function strArr(v: unknown, n: number, len = 120): string[] { return Array.isArray(v) ? v.map((x) => clip(x, len)).filter(Boolean).slice(0, n) : []; }
function num(v: unknown): number | null { const n = Number(v); return Number.isFinite(n) ? n : null; }
function conf(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : 0; }

async function b64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let s = ''; const CH = 0x8000;
  for (let i = 0; i < buf.length; i += CH) s += String.fromCharCode(...(buf.subarray(i, i + CH) as unknown as number[]));
  return btoa(s);
}
function mimeOf(path: string) {
  const e = String(path).toLowerCase().split('.').pop() || '';
  if (e === 'pdf') return 'application/pdf';
  if (e === 'png') return 'image/png';
  if (e === 'webp') return 'image/webp';
  if (e === 'jpg' || e === 'jpeg') return 'image/jpeg';
  return 'application/octet-stream';
}
async function attach(path: string, label: string, content: any[], used: string[]) {
  if (!path) return;
  try {
    const { data, error } = await admin.storage.from(BUCKET).download(path);
    if (error || !data) return;
    if (data.size > MAX_BYTES) return;
    const mime = mimeOf(path);
    const b = await b64(data);
    content.push({ type: 'text', text: `--- ${label} ---` });
    if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: `data:${mime};base64,${b}` } });
    else content.push({ type: 'file', file: { filename: path.split('/').pop() || 'document.pdf', file_data: `data:application/pdf;base64,${b}` } });
    used.push(label + ': ' + path);
  } catch (_e) { /* a single unreadable document must not abort the analysis */ }
}

async function vocabulary() {
  const { data: tr } = await admin.from('taxonomy_trade').select('code,label,authority_required').eq('active', true).order('sort');
  const { data: ro } = await admin.from('taxonomy_role').select('code,label,supplies,executes,whole_scope').eq('active', true).order('sort');
  return { trades: tr || [], roles: ro || [] };
}

const SYS = `You are QuotesDone's supplier capability analyst for the UAE construction, fit-out, MEP and building-services market. You read a supplier's own documents and determine EXACTLY what work they can take on, so that we only ever send them inquiries they can genuinely quote. A supplier who receives irrelevant inquiries leaves the platform, so precision matters more than coverage.

You MUST classify using ONLY the controlled vocabulary given in the user message. Never invent a code.

CRITICAL RULES
1. TRADE (what the work is) and ROLE (how they participate) are separate axes. A company that MANUFACTURES fire pumps is trade=fire_fighting, role=manufacturer. It is NOT plumbing, and it is NOT an installer. Getting role wrong is the most damaging error you can make, because it is what causes a supplier to receive work they cannot perform.
2. Assign a trade ONLY on real evidence of working in it. A passing mention of a material is not evidence: "we use stainless steel fittings" does NOT make them a steel fabricator. When in doubt, leave it out and say so in missing.
3. products = the specific product lines or systems they supply/install, generic and in their own words (no brand names). This is the strongest matching signal, so be concrete: "VRF indoor units", "chilled water pipework", not "HVAC solutions".
4. exclusions = anything the documents explicitly state they do NOT do or do not supply.
5. Be honest about insufficiency. Generic marketing copy with no concrete scope is NOT sufficient. Never pad the lists to look complete — an over-broad record causes exactly the spam we are preventing.

Return STRICT JSON only:
{"trades":[code],"roles":[code],"products":[string],"brands":[string],"project_types":[string],"exclusions":[string],"years_in_business":number|null,"team_size":number|null,"evidence":{"trades":string,"roles":string},"sufficient":boolean,"missing":[string],"confirm_summary":string,"confirm_questions":[string],"confidence":{"trades":0.0,"roles":0.0,"products":0.0}}

sufficient = true ONLY if the documents evidence at least one trade AND one role AND at least two concrete product lines or services.
missing = plain English, addressed to the supplier, naming exactly what they must provide. Not "insufficient data" but e.g. "a product catalogue, or a list of the air-conditioning systems you supply and install".
confirm_summary = one short paragraph written TO THE SUPPLIER in second person, in plain language with no codes, stating what we understood their business does, for them to confirm or correct.
confirm_questions = up to 3 short questions that would remove remaining ambiguity. ALWAYS include one asking what they do NOT take on.`;

// Signature unchanged; `key` is now the inbound_secret used to authenticate to ai_gateway.
// The model ladder and the retry live in the gateway now, so this is a single call.
async function callModel(key: string, content: any[]) {
  let last = '';
  try {
    const r = await fetch(GW, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      // `max: 2500` removed 5 Aug 2026. This function reads up to five supplier documents (trade
      // licence, company profile, three catalogues) as base64 vision parts and returns a 13-key JSON
      // with up to 40 products. Its peers on the same class and model measure 1,799-3,249 output
      // tokens (doc_extract / drawing_boq / quote_extract), so 2,500 sat MID-DISTRIBUTION - the §5
      // pattern that has now produced five separate defects. ai_gateway takes min(caller, policy),
      // so this could only ever lower document_extraction's 8000, never raise it.
      body: JSON.stringify({ __secret: key, fn: 'capability_agent', temperature: 0.1, sys: SYS, input: [{ role: 'user', content }] })
    });
    const jd = await r.json();
    if (!r.ok || jd?.ok === false) { last = 'http ' + r.status + ' ' + clip(jd?.detail || jd?.error, 140); }
    else {
      const p = parseJson(jd?.content || '');
      if (p && Object.keys(p).length) return { ai: p, err: '' };
      last = 'unparseable model output';
    }
  } catch (e) { last = clip((e as Error)?.message || e, 140); }
  return { ai: null, err: last };
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'capability_agent');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || 'analyze');
    const probeText = clip(body.probe_text || '', 20000);
    const supplierId = Number(body.supplier_id || 0);
    if (!supplierId && !probeText) return J({ error: 'supplier_id_required' }, 400);

    let lead: any = null;
    if (supplierId) {
      const { data } = await admin.from('leads')
        .select('id,company_name,sector,products,services,capability_summary,emirate,service_emirates,license_doc_path,company_profile_doc_path,catalog_doc_paths,catalogue_pdfs,license_expiry')
        .eq('id', supplierId).maybeSingle();
      lead = data;
      if (!lead && !probeText) return J({ error: 'supplier_not_found' }, 404);
    }

    // ---------------- state ----------------
    if (action === 'state') {
      const { data: cap } = await admin.from('supplier_capabilities').select('*').eq('supplier_id', supplierId).maybeSingle();
      const { data: hist } = await admin.from('supplier_capability_confirmation')
        .select('version,confirmed_at,confirmed_via').eq('supplier_id', supplierId).order('version', { ascending: false }).limit(5);
      return J({ ok: true, capability: cap || null, confirmed: !!cap?.confirmed_at, history: hist || [] });
    }

    // ---------------- confirm ----------------
    // What the supplier agrees to is what we store. Validated against the controlled vocabulary so a
    // bad client cannot inject codes that would silently never match.
    if (action === 'confirm') {
      const vocab = await vocabulary();
      const okTrade = new Set(vocab.trades.map((t: any) => t.code));
      const okRole = new Set(vocab.roles.map((r: any) => r.code));
      const trades = strArr(body.trades, 25, 40).filter((c) => okTrade.has(c));
      const roles = strArr(body.roles, 8, 40).filter((c) => okRole.has(c));
      if (!trades.length || !roles.length) return J({ error: 'need_at_least_one_trade_and_role', valid_trades: [...okTrade], valid_roles: [...okRole] }, 400);

      const products = strArr(body.products, 40);
      const exclusions = strArr(body.exclusions, 25);
      const brands = strArr(body.brands, 40, 60);
      const projectTypes = strArr(body.project_types, 12, 60);

      // 5 Aug 2026. min/max_project_value had NO writer anywhere - not here, not in the portal,
      // nowhere in src/. Only the raw SQL fixtures set them, so a supplier confirmed through the
      // only real endpoint scored w_size*0.5 instead of w_size in fn_match_capability and ranked
      // below an identical supplier created by a test.
      //
      // SUPPLIER-DECLARED ONLY, never model-extracted. These feed a HARD GATE in
      // fn_match_capability's cand CTE: a job outside the range removes the supplier from the
      // candidate set entirely rather than ranking it low. A wrong number is therefore far more
      // damaging than a missing one, and null stays null and stays permissive.
      const nv = (v: unknown) => (v === null || v === undefined || v === '') ? null : (Number.isFinite(Number(v)) ? Number(v) : null);
      const minVal = nv(body.min_project_value);
      const maxVal = nv(body.max_project_value);
      if ((minVal !== null && minVal < 0) || (maxVal !== null && maxVal < 0) ||
          (minVal !== null && maxVal !== null && minVal > maxVal)) {
        return J({ error: 'invalid_project_value_range', message: 'The project value range is not valid. The minimum cannot be negative or greater than the maximum.', min_project_value: minVal, max_project_value: maxVal }, 400);
      }

      const { data: prev } = await admin.from('supplier_capability_confirmation')
        .select('version').eq('supplier_id', supplierId).order('version', { ascending: false }).limit(1).maybeSingle();
      const version = Number(prev?.version || 0) + 1;
      const now = new Date().toISOString();

      const capRow: Record<string, unknown> = {
        supplier_id: supplierId,
        trades, roles, products_norm: products, brands, project_types: projectTypes, exclusions,
        services: strArr(body.services, 25),
        coverage_emirates: strArr(body.coverage_emirates, 8, 40),
        confidence: body.confidence && typeof body.confidence === 'object' ? body.confidence : {},
        source_docs: body.source_docs && typeof body.source_docs === 'object' ? body.source_docs : {},
        missing_fields: [],
        review_status: 'confirmed',
        confirmed_at: now,
        confirmed_version: version,
        extracted_at: now,
        extractor_version: AGENT_VERSION,
        updated_at: now,
      };
      // CONDITIONAL, not unconditional. supabase-js upserts with Prefer: resolution=merge-duplicates
      // and PostgREST builds DO UPDATE SET only for columns PRESENT in the payload. Including these
      // keys always would NULL an existing range on any confirm that omits them - e.g. a re-confirm
      // from a portal screen that does not collect them yet - silently widening that supplier's
      // eligibility back to "anything".
      if (minVal !== null) capRow.min_project_value = minVal;
      if (maxVal !== null) capRow.max_project_value = maxVal;

      const { error: upErr } = await admin.from('supplier_capabilities').upsert(capRow, { onConflict: 'supplier_id' });
      if (upErr) return J({ error: 'capability_write_failed', detail: upErr.message }, 500);

      await admin.from('supplier_capability_confirmation').insert({
        supplier_id: supplierId, version,
        proposed: body.proposed && typeof body.proposed === 'object' ? body.proposed : {},
        // The declared range is now a hard gate on what this supplier is ever shown, so it belongs
        // in the confirmation ledger - that row is the dispute record.
        confirmed: { trades, roles, products, brands, project_types: projectTypes, min_project_value: minVal, max_project_value: maxVal },
        supplier_added: body.supplier_added && typeof body.supplier_added === 'object' ? body.supplier_added : {},
        exclusions,
        source_docs: body.source_docs && typeof body.source_docs === 'object' ? body.source_docs : {},
        confirmed_at: now,
        confirmed_via: clip(body.confirmed_via || 'portal', 20),
        agent_version: AGENT_VERSION,
      });

      return J({ ok: true, confirmed: true, version, trades, roles, products_count: products.length, exclusions_count: exclusions.length });
    }

    // ---------------- analyze ----------------
    const key = await sec('cred_fn_ai');
    if (!key) return J({ error: 'no_ai_key' }, 500);

    const used: string[] = [];
    const vocab = await vocabulary();
    const vocabText =
      'CONTROLLED VOCABULARY — use ONLY these codes.\n\nTRADES:\n' +
      vocab.trades.map((t: any) => `  ${t.code} — ${t.label}` + (t.authority_required?.length ? ` [requires: ${t.authority_required.join(', ')}]` : '')).join('\n') +
      '\n\nROLES (supplies = can provide goods, executes = can perform site work, whole_scope = can take a multi-trade turnkey job):\n' +
      vocab.roles.map((r: any) => `  ${r.code} — ${r.label} [supplies=${r.supplies}, executes=${r.executes}, whole_scope=${r.whole_scope}]`).join('\n');

    const content: any[] = [];

    if (probeText) {
      // DIAGNOSTIC MODE: analyse supplied text, never touch storage, never persist.
      content.push({ type: 'text', text: vocabText + `\n\nSUPPLIER: ${clip(lead?.company_name || body.company_name || '(probe)', 120)}\n\nThe following is the content of their company documents. Read it and return the capability JSON.\n\n--- DOCUMENT CONTENT ---\n` + probeText });
      used.push('probe_text');
    } else {
      // Mandatory documents. Catalogue is NOT required up front — only asked for if the first two
      // do not carry enough concrete scope.
      const blocking: any[] = [];
      if (!lead.license_doc_path) blocking.push({ code: 'license_missing', ask: 'Attach your trade licence.' });
      if (!lead.company_profile_doc_path) blocking.push({ code: 'profile_missing', ask: 'Attach your company profile.' });
      if (blocking.length) {
        return J({ ok: true, sufficient: false, stage: 'documents', blocking,
          message: 'We need your trade licence and company profile before we can work out what to send you.' });
      }

      const cats: string[] = [];
      for (const c of ([] as any[]).concat(lead.catalog_doc_paths || [], lead.catalogue_pdfs || [])) {
        const p = typeof c === 'string' ? c : (c?.path || c?.url || '');
        if (p) cats.push(String(p));
      }

      content.push({ type: 'text', text: vocabText +
        `\n\nSUPPLIER: ${clip(lead.company_name, 120)}\nSelf-declared sector: ${clip(lead.sector, 60) || '(none)'}\nSelf-declared products: ${clip(lead.products, 400) || '(none)'}\nSelf-declared services: ${clip(lead.services, 400) || '(none)'}\n\nRead the attached documents and return the capability JSON. The self-declared text above is UNVERIFIED — treat the attached documents as the evidence.` });

      await attach(String(lead.license_doc_path || ''), 'TRADE LICENCE', content, used);
      await attach(String(lead.company_profile_doc_path || ''), 'COMPANY PROFILE', content, used);
      for (const p of cats.slice(0, 3)) await attach(p, 'PRODUCT CATALOGUE', content, used);

      if (used.length === 0) {
        return J({ ok: true, sufficient: false, stage: 'documents',
          blocking: [{ code: 'documents_unreadable', ask: 'We could not open your documents. Please re-upload your trade licence and company profile as PDF or image.' }],
          message: 'Your documents could not be read.' });
      }
    }

    const { ai, err } = await callModel(key, content);
    if (!ai) return J({ error: 'ai_failed', detail: err }, 502);

    const okTrade = new Set(vocab.trades.map((t: any) => t.code));
    const okRole = new Set(vocab.roles.map((r: any) => r.code));
    const trades = strArr(ai.trades, 25, 40).filter((c) => okTrade.has(c));
    const roles = strArr(ai.roles, 8, 40).filter((c) => okRole.has(c));
    const products = strArr(ai.products, 40);
    const dropped = strArr(ai.trades, 25, 40).filter((c) => !okTrade.has(c));

    // Sufficiency is decided HERE, not by the model — the model can be optimistic, and an
    // over-confident record is what produces irrelevant inquiries later.
    const missing = strArr(ai.missing, 8, 200);
    const hardEnough = trades.length >= 1 && roles.length >= 1 && products.length >= 2;
    const sufficient = hardEnough && ai.sufficient !== false;
    if (!hardEnough && !missing.length) {
      if (!trades.length) missing.push('a clearer description of the type of work you do');
      if (!roles.length) missing.push('whether you supply materials, install on site, or both');
      if (products.length < 2) missing.push('a product catalogue, or a list of the specific products and systems you supply');
    }

    const proposed = {
      trades, roles, products,
      brands: strArr(ai.brands, 40, 60),
      project_types: strArr(ai.project_types, 12, 60),
      exclusions: strArr(ai.exclusions, 25),
      years_in_business: num(ai.years_in_business),
      team_size: num(ai.team_size),
      evidence: { trades: clip(ai?.evidence?.trades, 500), roles: clip(ai?.evidence?.roles, 500) },
      confidence: { trades: conf(ai?.confidence?.trades), roles: conf(ai?.confidence?.roles), products: conf(ai?.confidence?.products) },
      source_docs: used,
    };

    // Persist the working extraction, but NEVER mark it confirmed — matching must require
    // supplier confirmation, so an unconfirmed extraction can never generate contact.
    // Probe mode is diagnostic and must not write.
    if (!probeText && supplierId) {
      try {
        await admin.from('supplier_capabilities').upsert({
          supplier_id: supplierId,
          trades, roles, products_norm: products,
          brands: proposed.brands, project_types: proposed.project_types, exclusions: proposed.exclusions,
          confidence: proposed.confidence,
          source_docs: { documents: used },
          missing_fields: missing,
          review_status: sufficient ? 'awaiting_confirmation' : 'insufficient',
          extracted_at: new Date().toISOString(),
          extractor_version: AGENT_VERSION,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'supplier_id' });
      } catch (_e) { /* analysis is still useful to return even if the cache write fails */ }
    }

    return J({
      ok: true,
      probe: !!probeText,
      stage: sufficient ? 'confirm' : 'need_more',
      sufficient,
      can_submit: sufficient,
      missing,
      proposed,
      confirm_summary: clip(ai.confirm_summary, 1200),
      confirm_questions: strArr(ai.confirm_questions, 3, 200),
      documents_read: used,
      vocabulary_rejected: dropped,
      agent_version: AGENT_VERSION,
    });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
