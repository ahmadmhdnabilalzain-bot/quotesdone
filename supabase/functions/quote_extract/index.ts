// quote_extract - reads a supplier's uploaded quotation (page images and/or PDF) and returns an
// ANONYMIZED standardized quote. Masks company identity AND brand/model/identity-revealing terms; a brand becomes
// '<tier> <origin> brand' (_shared/quote_generalise.ts, founder ledger 1589).
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
import { requireInternal, secretOk } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { scrubIdentityText } from '../_shared/identity_text.ts';
import { generaliseText, type GeneraliseCtx } from '../_shared/quote_generalise.ts';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted } from './quote_from_document.ts';
import { checkReading, documentText, proposalFromModel } from './model_reading.ts';
import { pageB64, pageMime } from '../_shared/licence_extract.ts';
import { DATA_NOT_INSTRUCTIONS, untrustedBlock } from '../_shared/untrusted.ts';
import { J } from '../_shared/json_response.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'quote_extract', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
// secretOk() is the shared one, in ../_shared/internal_auth.ts.
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
function scrub(s: unknown): string {
  let t = String(s == null ? '' : s);
  t = t.replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '█');
  t = t.replace(/https?:\/\/\S+|www\.[\w.-]+\.[a-z]{2,}/gi, '█');
  t = t.replace(/(?:\+?\d[\d\s().-]{6,}\d)/g, (m) => (m.replace(/\D/g,'').length >= 7 ? '█' : m));
  // 3 Nov 2026: the shared identity shapes too (_shared/identity_text.ts), whatever the model left in.
  return scrubIdentityText(t, '█').trim();
}
// 10 Nov 2026 (founder ledger 1588-1590, sales_engineer): the replacement rule names ORIGIN and TIER. It said
// "premium branded mixer", which kept the tier and lost the origin, so a customer who asked for Italian origin could
// not see that the supplier quoted Chinese; and it was written for "a UAE building / fit-out job" while the estate
// serves every trade except food and beverage. Whatever the model returns is generalised again by
// _shared/quote_generalise.ts below (the same module the deterministic path and every pre-reveal surface run).
const SYS = `You read a document a supplier sent in answer to a request for a price QUOTATION for a UAE business purchase and convert it into an ANONYMOUS standardized quote for QuotesDone, a B2B procurement marketplace for every trade except food and beverage: building and fit-out works, MEP, equipment and machinery, materials, chemicals, packaging, vehicles and staff transport, IT and telecom, facilities services, and professional services (consultancy, accounting, legal, marketing). The customer must PAY to reveal the supplier, so the customer must NOT be able to identify the supplier from anything you output.\n\nRead EVERY page and EVERY line item carefully. Extract all commercial figures, then REWRITE every text field so it cannot reveal who the supplier is.\n\nMASK / REMOVE:\n- Company name, logo wording, letterhead, slogan, person names, signatures, stamps.\n- Phone, email, website, address, social handles, trade-license / TRN / VAT numbers, bank details.\n- Brand names, manufacturer names, product model names or numbers, catalogue / SKU / part codes, and any proprietary or exclusive product line or service programme a customer could search online to identify a specific seller (a named tile collection, a named tap or mixer brand, a named pump model, a branded consultancy method).\n- Any unusually distinctive wording that could fingerprint the supplier.\n\nTHE REPLACEMENT MUST BE FACTUALLY CORRECT AND KEEP ORIGIN AND TIER. Replace each brand with '<tier> <origin> brand' where origin is the country the BRAND comes from and tier is its market position (premium / mid-range / economy): a named German premium mixer becomes 'premium German brand mixer'; a named Italian porcelain collection becomes 'premium Italian brand 120x60 porcelain'; a named Japanese inverter becomes 'Japanese brand inverter'; a named Chinese panel becomes 'Chinese brand 550 W solar panel'. NEVER guess an origin: if you are not certain where a brand comes from, write 'branded' with the tier only if the quotation itself states it ('premium branded mixer'). A model number or SKU becomes nothing (keep the product noun and its specification). Keep the country of MANUFACTURE exactly as the quotation states it ('made in China', 'origin: Italy') in that line's country_of_origin.\n\nKEEP (these matter for comparing quotes): amounts, currency, quantities, units, dimensions/sizes, generic material & spec, grades and standards (SS316, C40, IP65, EN/BS/ISO numbers), quality tier, finish, origin, lead time, validity, payment terms, warranty, scope, conditions, exclusions.\n\nFIRST DECIDE WHETHER IT IS A QUOTATION. A quotation is the supplier's priced offer for the work, goods or service a customer asked for: what he will supply or do, and for how much. NOT a quotation (is_quotation false, and say why in not_a_quotation_reason): an invoice or tax invoice, a receipt or statement of account, a payment request, a price list or catalogue that answers no particular job, a company profile, a licence or certificate, a message arranging a site visit or stating a call-out, inspection or visit charge, a question back to the customer, a delivery note, or a document for another job. Its layout does not decide this; what it says does.\n\nTHE FIGURES, exactly as the quotation states them, never computed by you: total = the final price of the whole offer as written (with VAT when the quotation adds VAT). It is NEVER a deposit, advance, down payment, instalment, retention, a payment-term percentage, or a single line. subtotal = the price before VAT (after any discount) when written. vat_amount = the VAT written. vat_treatment = 'exclusive' when VAT is added on top or prices are stated as excluding VAT, 'inclusive' when the total includes VAT, 'not_registered' when the supplier says he is not VAT registered or charges no VAT, '' when the quotation does not say. discount_amount and gross_amount (the price before the discount) only when a discount is written. currency = the currency the prices are written in (AED when AED, Dhs or dirham). When the quotation offers ALTERNATIVES the customer chooses between (Option A / Option B, two brands, two scopes), list each in options with its own total, give each line its option number, and set total to the first option's total; a single offer has options []. request_reference = the request or enquiry number the document itself cites (for example RFQ-164810), or ''.\n\nReturn STRICT JSON only, no prose:\n{\"is_quotation\":boolean,\"not_a_quotation_reason\":string,\"request_reference\":string,\"currency\":string,\"total\":number,\"subtotal\":number,\"vat_amount\":number,\"vat_treatment\":string,\"discount_amount\":number,\"gross_amount\":number,\"options\":[{\"label\":string,\"total\":number}],\"line_items\":[{\"description\":string,\"qty\":string,\"quantity\":number,\"unit\":string,\"unit_price\":number,\"amount\":number,\"option\":number,\"country_of_origin\":string}],\"lead_time\":string,\"validity\":string,\"payment_terms\":string,\"warranty\":string,\"scope\":string,\"conditions\":string,\"exclusions\":string,\"notes\":string,\"description_anonymized\":string,\"masked_terms\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\nUse null for a figure the quotation does not state. Every string field must ALREADY be anonymized. masked_terms = the original identity-revealing strings you removed, brands and model numbers included (shown ONLY to the supplier for review, never to the customer). If a value is absent, use an empty string (or [] for line_items and options).`;

function dataUrl(b64: string, mime: string){ return `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/,'')}`; }

Deno.serve(observe('quote_extract', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'quote_extract');
    if (!__auth.ok) { await logRun('error', { forbidden: 1, quote_extracted: 0, credential_presented: body?.__secret ? 1 : 0, auth_status: __auth.status }, 'quote_extract rejected a caller with a missing/wrong inbound secret (' + __auth.status + ', credential ' + (body?.__secret ? 'presented but not accepted' : 'absent') + '; the reason is in internal_credential_audit). A supplier quotation was not parsed — that supplier\'s price will be missing from the comparison the customer sees, which looks like the supplier simply never quoted.'); return J({ error: 'forbidden' }, 403); }
    // THE MODEL READS THE QUOTATION; CODE CHECKS IT (sales_engineer, 12 Nov 2026; founder rulings 1663, 1664, 1666; LLM-first
    // audit A2). Until today the supplied file was priced by code first (doc_read + quote_from_document) and the model was
    // asked only when code found no total, and a model that did not answer was replaced by that same code reading. Now the
    // model reads every quotation, the code money reader only CHECKS what it read (./model_reading.ts), and a model that
    // does not answer leaves the quotation unread and retryable: it is never priced by code instead.
    const secret = await sec('cred_fn_ai');
    if (!secret) { await logRun('error', { quote_extracted: 0, ai_key_present: 0 }, 'quote_extract could not ask the model: the cred_fn_ai credential is missing. The quotation was not read and not priced by code; the supplier is told it is being read and may try again.'); return J({ ok: false, error: 'model_unavailable', retryable: true, detail: 'no ai key' }, 503); }
    // The file as doc_read transcribes it: what the model is given for a spreadsheet, a Word file, a CSV or an e-mail
    // body (a provider takes a PDF or a picture, not an .xlsx), and the text the checks compare the model's figures with.
    // Transcription, not meaning: nothing here reads a figure into the proposal.
    const rd = body.file_b64 ? await readDocument(String(body.file_b64), String(body.filename || 'quotation'), String(body.mime || '')).catch(() => null) : null;
    // A plain-text file (an e-mail body) AS WRITTEN; any other as doc_read's transcription (./model_reading.ts documentText).
    const docText = documentText(body.file_b64, String(body.filename || ''), String(body.mime || ''), rd);
    const masks = Array.isArray(body.supplier_terms) ? body.supplier_terms.map((s: unknown) => String(s)) : [];
    const inq = body.inquiry || {};

    // the quotation's printed text and the customer's summary are data, never instructions (untrusted.ts, 3 Nov 2026)
    // `requests`: the supplier's open requests on the e-mail route, so the model can say which one the quotation names.
    const reqs = Array.isArray(body.requests) ? body.requests.slice(0, 10).map((q: { job_no?: unknown; category?: unknown } | null) => `RFQ-${String(q?.job_no ?? '').replace(/\D/g, '')} (${String(q?.category ?? '-').slice(0, 60)})`).join(', ') : '';
    const content: any[] = [{ type: 'text', text: `Read the attached supplier document (all pages): say whether it is a quotation, and if it is, return the anonymized standardized JSON. ${DATA_NOT_INSTRUCTIONS}\nJob context (for understanding only): category ${inq.category||'-'}.` + (reqs ? ` The supplier's open requests on QuotesDone: ${reqs}.` : '') + (inq.summary ? ' The customer\'s summary:' + untrustedBlock(String(inq.summary), 'NOTE') : '') }];

    const imgs: any[] = Array.isArray(body.images) ? body.images : [];
    // THE PORTAL'S PAGE SHAPE (review of #1707, 28 Oct 2026, sales_engineer). SupplierPortal's fileToImages sends each
    // quotation page as { mime, data }; this read only `b64`, so a page went out as the text of an object and the
    // provider refused it - the defect that failed license_extract 38 of 38 calls on 27-28 Oct. One reader for both.
    const pages = imgs.slice(0, 8).filter((im) => !!pageB64(im));
    if (pages.length) {
      for (const im of pages) content.push({ type: 'image_url', image_url: { url: dataUrl(pageB64(im), pageMime(im)) } });
    } else if (body.file_b64) {
      const mime = String(body.mime || 'application/octet-stream');
      if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
      else if (/pdf/i.test(mime) || /\.pdf$/i.test(String(body.filename || ''))) content.push({ type: 'file', file: { filename: String(body.filename||'quotation.pdf'), file_data: dataUrl(String(body.file_b64), 'application/pdf') } });
      // A spreadsheet, a Word file, a CSV or an e-mail body: the model is given doc_read's transcription (12 Nov 2026).
      else if (docText.trim()) content.push({ type: 'text', text: 'The document, transcribed (' + String(rd?.ok ? rd.kind : 'text') + '):' + untrustedBlock(docText.slice(0, 60000), 'ATTACHMENT') });
      else { await logRun('error', { quote_extracted: 0, transcribed: 0 }, 'quote_extract could not open a ' + mime + ' file to give it to the model; the supplier is asked for a PDF or a photo.'); return J({ ok: false, error: 'unreadable_quotation', detail: 'the file could not be opened' }); }
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
      // ONE MORE ASKING (ruling 1177): an answer with no parseable JSON or no total is asked once more before the
      // quotation is called unreadable; the gateway itself falls to the route's second model on a provider failure.
      let r!: Response; let jd: any;
      for (let attempt = 1; attempt <= 2; attempt++) {
        r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, fn: 'quote_extract', subject: body.subject ?? null, max: 6000, temperature: 0.1, sys: SYS, input: [{ role: 'user', content }], client_timeout_ms: 100000 }) });
        jd = await r.json().catch(() => ({ ok: false, error: "gateway_reply_not_json" }));
        // asked once more only when the answer was neither "not a quotation" nor a total (12 Nov 2026)
        const a1 = parseJson(jd?.content || '{}');
        if (!r.ok || jd?.ok === false || a1?.is_quotation === false || Number(a1?.total ?? a1?.amount) > 0) break;
      }
      // NO MODEL ANSWER IS NEVER A CODE PRICE (12 Nov 2026, ruling 1664): the quotation stays unread and retryable.
      if (!r.ok || jd?.ok === false) { await logRun('error', { quote_extracted: 0, pages: aiPages, ai_ok: 0, model_unavailable: 1 }, 'quote_extract could not read a supplier quotation: the model call returned an error (' + String(jd?.detail || jd?.error || ('http ' + r.status)).slice(0, 140) + '). It was not priced by code; the supplier is told it is being read.'); return J({ ok: false, error: 'model_unavailable', retryable: true, detail: String(jd?.detail || jd?.error || ('http ' + r.status)).slice(0, 300) }, 503); }
      extractedBy = typeof jd?.model === 'string' && jd.model ? jd.model : 'unknown';
      const _rawContent = jd?.content || '{}';
      ai = parseJson(_rawContent);
      aiParseOk = !!(ai && typeof ai === 'object' && Object.keys(ai).length > 0);
    } catch (e) { await logRun('error', { quote_extracted: 0, pages: aiPages, ai_ok: 0, model_unavailable: 1 }, 'quote_extract threw while calling the model (' + String((e as Error)?.message || e).slice(0, 140) + '). The quotation was not priced by code; the supplier is told it is being read.'); return J({ ok: false, error: 'model_unavailable', retryable: true, detail: String((e as Error)?.message || e).slice(0, 300) }, 503); }

    // THE MODEL'S MASKING IS CHECKED, NOT TRUSTED (10 Nov 2026, ledger 1589). Every field it returns runs the shared
    // generaliser: a brand it left in becomes "<tier> <origin> brand", a model number is withheld, and the terms it
    // reported as masked are themselves searched for (a residue of "Grohe Eurosmart" in another field is caught).
    if (!Array.isArray(ai.masked_terms)) ai.masked_terms = [];
    // A reported term that reads as a make (words, no contact shape) is searched for as a brand; a short code as a model.
    const reported = ai.masked_terms.map((x: unknown) => String(x).trim()).filter((x: string) => x.length >= 3 && x.length <= 60 && !/[@:/]|\d{7,}/.test(x));
    const genCtx: GeneraliseCtx = { supplierNames: Array.isArray(body.supplier_terms) ? body.supplier_terms.map((x: unknown) => String(x)) : [],
      brands: reported.filter((x: string) => !/\d/.test(x) && x.split(/\s+/).length <= 4), models: reported.filter((x: string) => /\d/.test(x) && /[A-Za-z]/.test(x) && x.length <= 30) };
    const gen = (v: unknown) => { const r = generaliseText(scrub(v), genCtx); for (const t of r.replaced) if (!ai.masked_terms.includes(t.term)) ai.masked_terms.push(t.term); return r.text; };
    // The model's answer in the proposal shape, then the code checks (./model_reading.ts): the arithmetic, the code money
    // reader as the checker, options, and a note where a figure is not in the text layer. No figure is changed by a check.
    const codeRead = rd?.ok ? quoteFromExtracted(rd, masks) : null;
    const read = checkReading(proposalFromModel(ai, gen), docText, codeRead);
    read.masked_terms = [...ai.masked_terms];
    const _amountOk = read.amount != null;
    const _okRun = aiParseOk && read.is_quotation && _amountOk && !read.review_reason;
    let _note = '';
    if (!aiParseOk) _note = 'quote_extract returned an EMPTY quote because the model output could not be parsed as JSON, not because the quotation was blank — the supplier\'s real price is silently lost and the customer will compare quotes with this supplier missing or showing no amount.';
    else if (!read.is_quotation) _note = 'The model read the document and it is not a quotation (' + (read.not_a_quotation_reason || 'no reason given').slice(0, 160) + ').';
    else if (read.review_reason === 'foreign_currency') _note = 'The model read a quotation priced in ' + read.currency_stated + ': it is not read as AED; the supplier types the AED total.';
    else if (!_amountOk) _note = 'quote_extract parsed the model output but no grand-total amount could be read from the supplier quotation (' + read.line_items.length + ' line items, confidence ' + String(ai.confidence || 'unknown') + '). A quote with no price cannot be ranked or compared, so this supplier effectively drops out of the customer\'s comparison.';
    else _note = 'Supplier quotation read by the model and anonymized: price ex VAT AED ' + String(read.amount) + ', ' + read.line_items.length + ' line item(s), ' + read.masked_terms.length + ' identity-revealing term(s) masked, confidence ' + String(ai.confidence || 'unknown') + '; ' + (read.warnings?.length ?? 0) + ' point(s) for the supplier to confirm.' + (read.check_notes.length ? ' Notes: ' + read.check_notes.join(' ') : '') + (read.masked_terms.length === 0 ? ' NOTE: zero terms were masked — verify the anonymisation actually ran, since leaking supplier identity would let the customer bypass the paywall.' : '');
    await logRun(_okRun ? 'ok' : 'error', { quote_extracted: _okRun ? 1 : 0, parse_ok: aiParseOk ? 1 : 0, is_quotation: read.is_quotation ? 1 : 0, amount_present: _amountOk ? 1 : 0, line_items: read.line_items.length, masked_terms: read.masked_terms.length, pages: aiPages, confidence: ai.confidence || null, to_confirm: read.warnings?.length ?? 0, check_notes: read.check_notes.length }, _note);
    // 5 Aug 2026. This returned ok:true unconditionally - including when parseJson had returned {}
    // and every field had just been scrubbed to ''. supplier_api already has the correct fallback
    // for that case ("Could not read the quotation. Please fill the form instead.") but it is gated
    // on !jd.ok, so it could never fire: the supplier was handed a blank form with no explanation
    // and their real price silently left the customer's comparison. Report the outcome truthfully;
    // an extraction that produced no parseable JSON or no total is a failure, not a success.
    // 12 Nov 2026: 'not_a_quotation' (the model read it: an invoice, a site-visit note...) and 'total_ambiguous' with
    // review_reason 'foreign_currency' (the shape supplier_api already words for the supplier) are failures too.
    const error = _okRun ? undefined : !aiParseOk ? 'unreadable_quotation' : !read.is_quotation ? 'not_a_quotation' : read.review_reason ? 'total_ambiguous' : 'no_amount';
    return J({ ok: _okRun, proposal: read, extracted_by_model: extractedBy, is_quotation: read.is_quotation, error, review_reason: read.review_reason ?? undefined, reason: read.is_quotation ? undefined : read.not_a_quotation_reason, detail: _okRun ? undefined : _note.slice(0, 200) });
  } catch (e) { await logRun('error', { quote_extracted: 0, unhandled_exception: 1 }, 'quote_extract threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e).slice(0, 200) + ' — a supplier quotation was not converted into a comparable quote and will be missing from the customer\'s comparison.'); return J({ error: String((e as Error)?.message || e) }, 500); }
}));
