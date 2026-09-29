// quote_extract - reads a supplier's uploaded quotation (page images and/or PDF) and returns an
// ANONYMIZED standardized quote. Masks company identity AND brand/model/identity-revealing terms.
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
//
// A vision read of the supplier's own document. It returns ok:false with 'unreadable_quotation' or
// 'no_amount' rather than an empty proposal dressed as a success, and supplier_api:789 already has
// the fallback for that ("Could not read the quotation. Please fill the form instead."). Masking is
// best-effort text rewriting by the same model; masked_terms:0 is reported as something to check,
// not as proof nothing needed masking.
//
// Restored 9 Sep 2026 (deleted by the 137-function sweep, 182308b). Of the five this one degraded
// best: supplier_api saw a 502 and showed the manual form.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted, quoteText } from './quote_from_document.ts';
import { defaultDeps } from '../_shared/think.ts';
import { quoteTerms } from '../_shared/reasoned_suppliers.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'quote_extract', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
function scrub(s: unknown): string {
  let t = String(s == null ? '' : s);
  t = t.replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '█');
  t = t.replace(/https?:\/\/\S+|www\.[\w.-]+\.[a-z]{2,}/gi, '█');
  t = t.replace(/(?:\+?\d[\d\s().-]{6,}\d)/g, (m) => (m.replace(/\D/g,'').length >= 7 ? '█' : m));
  return t.trim();
}
const SYS = `You read a supplier's price QUOTATION for a UAE building / fit-out job and convert it into an ANONYMOUS standardized quote for QuotesDone, a marketplace where the customer must PAY to reveal the supplier. The customer must NOT be able to identify the supplier from anything you output.\n\nRead EVERY page and EVERY line item carefully. Extract all commercial figures, then REWRITE every text field so it cannot reveal who the supplier is.\n\nMASK / REMOVE:\n- Company name, logo wording, letterhead, slogan, person names, signatures, stamps.\n- Phone, email, website, address, social handles, trade-license / TRN / VAT numbers, bank details.\n- Brand names, manufacturer names, product model names or numbers, and any proprietary or exclusive product line a customer could search online to identify a specific seller (e.g. a named ceramic line, a named tap/mixer brand, a named pump model). Replace with a neutral equivalent that preserves the spec and quality tier, e.g. 'premium branded 120x60 porcelain', 'premium branded mixer', 'premium variable-speed pump'.\n- Any unusually distinctive wording that could fingerprint the supplier.\n\nKEEP (these matter for comparing quotes): amounts, currency, quantities, dimensions/sizes, generic material & spec, quality tier (standard / premium), finish, lead time, validity, payment terms, warranty, scope, conditions, exclusions.\n\nReturn STRICT JSON only, no prose:\n{\"amount\":number,\"currency\":\"AED\",\"line_items\":[{\"description\":string,\"qty\":string,\"amount\":number}],\"lead_time\":string,\"validity\":string,\"payment_terms\":string,\"warranty\":string,\"scope\":string,\"conditions\":string,\"exclusions\":string,\"notes\":string,\"description_anonymized\":string,\"masked_terms\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\namount = the GRAND TOTAL of the whole quotation (sum / stated total), not a single line. Every string field must ALREADY be anonymized. masked_terms = the original identity-revealing strings you removed (shown ONLY to the supplier for review, never to the customer). If a value is absent, use an empty string (or [] for line_items).`;

function dataUrl(b64: string, mime: string){ return `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/,'')}`; }

Deno.serve(observe('quote_extract', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'quote_extract');
    if (!__auth.ok) { await logRun('error', { forbidden: 1, quote_extracted: 0, credential_presented: body?.__secret ? 1 : 0, auth_status: __auth.status }, 'quote_extract rejected a caller with a missing/wrong inbound secret (' + __auth.status + ', credential ' + (body?.__secret ? 'presented but not accepted' : 'absent') + '; the reason is in internal_credential_audit). A supplier quotation was not parsed — that supplier\'s price will be missing from the comparison the customer sees, which looks like the supplier simply never quoted.'); return J({ error: 'forbidden' }, 403); }
    // 14 Sep 2026. THE DETERMINISTIC PATH. Under the model hold every quotation failed here. When the
    // supplier's ORIGINAL file is supplied (file_b64), _shared/doc_read reads it with no model and
    // quote_from_document turns it into the same proposal shape; prices kept, supplier identity masked.
    const detQuote = async (why: string) => {
      if (!body.file_b64) return null;
      try {
        const rd = await readDocument(String(body.file_b64), String(body.filename || 'quotation'), String(body.mime || ''));
        if (!rd.ok) return null;
        // The PRICES are read from the file's layout; the TERMS are what it means, so they are reasoned
        // (think(), founder_instruction 886-903). Held: they are left empty and the supplier types them.
        const masks = Array.isArray(body.supplier_terms) ? body.supplier_terms.map((s: unknown) => String(s)) : [];
        const priced = quoteFromExtracted(rd, masks);
        if (priced.amount == null && !priced.line_items.length) return null;   // no model is asked about a file with no price
        const terms = await quoteTerms(defaultDeps(admin, 'quote_extract'), { text: quoteText(rd) });
        const p = terms.value ? quoteFromExtracted(rd, masks, terms.value) : priced;
        if (!terms.value) p.notes += ' The lead time, validity, payment terms, warranty and exclusions were not read from the file: please type them in the form. / لم تُقرأ مدة التسليم وصلاحية العرض وشروط الدفع والضمان والاستثناءات من الملف: يُرجى كتابتها في النموذج.';
        await logRun(p.amount != null ? 'ok' : 'error', { quote_extracted: p.amount != null ? 1 : 0, deterministic: 1, line_items: p.line_items.length, masked_terms: p.masked_terms.length }, `quote_extract read the supplier's ${rd.kind} file with no model (${why}): ${p.line_items.length} priced line(s), total ${p.amount ?? 'not found'}.`);
        return J({ ok: p.amount != null, proposal: { ...p, fallback_reason: why }, extracted_by_model: 'deterministic', error: p.amount != null ? undefined : 'no_amount' });
      } catch (_e) { return null; }
    };
    const secret = await sec('cred_fn_ai');
    if (!secret || body.deterministic === true) { const d = await detQuote(secret ? 'requested' : 'no_ai_key'); if (d) return d; }
    if (!secret) { await logRun('error', { quote_extracted: 0, ai_key_present: 0 }, 'quote_extract aborted: the cred_fn_ai credential is missing, so the AI gateway cannot be called and no supplier quotation can be read at all. Every quote uploaded while this persists is silently dropped and the customer sees fewer (or zero) quotes to compare.'); return J({ error: 'no ai key' }, 500); }
    const inq = body.inquiry || {};

    const content: any[] = [{ type: 'text', text: `Job context (for understanding only): category ${inq.category||'-'}${inq.summary?(', summary: '+inq.summary):''}. Read the attached supplier quotation (all pages) and return the anonymized standardized JSON.` }];

    const imgs: any[] = Array.isArray(body.images) ? body.images : [];
    if (imgs.length) {
      for (const im of imgs.slice(0, 8)) { const b = im?.b64 || im; const m = im?.mime || 'image/jpeg'; if (b) content.push({ type: 'image_url', image_url: { url: dataUrl(String(b), String(m)) } }); }
    } else if (body.file_b64) {
      const mime = String(body.mime || 'application/octet-stream');
      if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
      else content.push({ type: 'file', file: { filename: String(body.filename||'quotation.pdf'), file_data: dataUrl(String(body.file_b64), mime||'application/pdf') } });
    } else { await logRun('error', { quote_extracted: 0, file_present: 0 }, 'quote_extract was called with no image pages and no file payload (400). A supplier attempted to submit a quotation and nothing was extracted — their price will be absent from the customer\'s comparison as if they never responded.'); return J({ error: 'no file' }, 400); }

    let ai: any = {};
    let aiParseOk = false;
    // The model that read the quotation. supplier_api records it against the file, the submitted quote carries it, and
    // quote_compare names it as counterpart_model so the comparison is never on the reader's family (instruction ~891).
    let extractedBy = 'unknown';
    const aiPages = imgs.length ? Math.min(imgs.length, 8) : (body.file_b64 ? 1 : 0);
    try {
      // 5 Aug 2026. This asked for 2000 output tokens. Measured against deployed staging on a
      // single-page, seven-line quotation: the call returned 1996 tokens with finish_reason
      // 'length' and unparseable output, while the same call at 4000 finished at 2407 and parsed
      // correctly. gemini-3.5-flash spends most of the budget on reasoning tokens - 1996 output
      // tokens carried only 206 characters of visible JSON - so 2000 could not fit even the
      // smallest real quotation. parseJson then returned {}, every text field was scrubbed to '',
      // and the function reported ok:true with an empty proposal: the supplier's real price was
      // silently dropped from the customer's comparison. 6000 covers a multi-page quotation.
      const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, fn: 'quote_extract', subject: body.subject ?? null, max: 6000, temperature: 0.1, sys: SYS, input: [{ role: 'user', content }], client_timeout_ms: 100000 }) });
      const jd = await r.json();
      if (!r.ok || jd?.ok === false) { const d = await detQuote('ai_gateway_refused'); if (d) return d; await logRun('error', { quote_extracted: 0, pages: aiPages, ai_ok: 0 }, 'quote_extract could not read a supplier quotation because the vision model call returned an error (' + String(jd?.detail || jd?.error || ('http ' + r.status)).slice(0, 140) + '). The supplier\'s quotation exists but produced no structured quote, so the customer\'s comparison is missing a real price.'); return J({ error: 'ai_error', detail: jd?.detail || jd?.error || JSON.stringify(jd).slice(0,300) }, 502); }
      extractedBy = typeof jd?.model === 'string' && jd.model ? jd.model : 'unknown';
      const _rawContent = jd?.content || '{}';
      ai = parseJson(_rawContent);
      aiParseOk = !!(ai && typeof ai === 'object' && Object.keys(ai).length > 0);
    } catch (e) { const d = await detQuote('ai_exception'); if (d) return d; await logRun('error', { quote_extracted: 0, pages: aiPages, ai_ok: 0 }, 'quote_extract threw while calling the vision model (' + String((e as Error)?.message || e).slice(0, 140) + '), so a supplier quotation was never converted into a comparable quote — the customer will see one fewer price and assume that supplier did not respond.'); return J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502); }

    const textFields = ['lead_time','validity','payment_terms','warranty','scope','conditions','exclusions','notes','description_anonymized'];
    for (const f of textFields) ai[f] = scrub(ai[f]);
    if (Array.isArray(ai.line_items)) ai.line_items = ai.line_items.map((li: any) => ({ description: scrub(li?.description), qty: String(li?.qty||''), amount: Number(li?.amount)||null }));
    else ai.line_items = [];
    ai.amount = Number(ai.amount) || null;
    ai.currency = 'AED';
    if (!Array.isArray(ai.masked_terms)) ai.masked_terms = [];
    const _amountOk = ai.amount != null;
    const _okRun = aiParseOk && _amountOk;
    let _note = '';
    if (!aiParseOk) _note = 'quote_extract returned an EMPTY quote because the model output could not be parsed as JSON, not because the quotation was blank — the supplier\'s real price is silently lost and the customer will compare quotes with this supplier missing or showing no amount.';
    else if (!_amountOk) _note = 'quote_extract parsed the model output but no grand-total amount could be read from the supplier quotation (' + ai.line_items.length + ' line items, confidence ' + String(ai.confidence || 'unknown') + '). A quote with no price cannot be ranked or compared, so this supplier effectively drops out of the customer\'s comparison.';
    else _note = 'Supplier quotation extracted and anonymized: total AED ' + String(ai.amount) + ', ' + ai.line_items.length + ' line item(s), ' + ai.masked_terms.length + ' identity-revealing term(s) masked, confidence ' + String(ai.confidence || 'unknown') + '.' + (ai.masked_terms.length === 0 ? ' NOTE: zero terms were masked — verify the anonymisation actually ran, since leaking supplier identity would let the customer bypass the paywall.' : '');
    await logRun(_okRun ? 'ok' : 'error', { quote_extracted: _okRun ? 1 : 0, parse_ok: aiParseOk ? 1 : 0, amount_present: _amountOk ? 1 : 0, line_items: ai.line_items.length, masked_terms: ai.masked_terms.length, pages: aiPages, confidence: ai.confidence || null }, _note);
    // 5 Aug 2026. This returned ok:true unconditionally - including when parseJson had returned {}
    // and every field had just been scrubbed to ''. supplier_api already has the correct fallback
    // for that case ("Could not read the quotation. Please fill the form instead.") but it is gated
    // on !jd.ok, so it could never fire: the supplier was handed a blank form with no explanation
    // and their real price silently left the customer's comparison. Report the outcome truthfully;
    // an extraction that produced no parseable JSON or no total is a failure, not a success.
    return J({ ok: _okRun, proposal: ai, extracted_by_model: extractedBy, error: _okRun ? undefined : (aiParseOk ? 'no_amount' : 'unreadable_quotation'), detail: _okRun ? undefined : _note.slice(0, 200) });
  } catch (e) { await logRun('error', { quote_extracted: 0, unhandled_exception: 1 }, 'quote_extract threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e).slice(0, 200) + ' — a supplier quotation was not converted into a comparable quote and will be missing from the customer\'s comparison.'); return J({ error: String((e as Error)?.message || e) }, 500); }
}));
