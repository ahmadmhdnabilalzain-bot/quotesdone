// quote_extract - reads a supplier's uploaded quotation (page images and/or PDF) and returns an
// ANONYMIZED standardized quote. Masks company identity AND brand/model/identity-revealing terms.
import { createClient } from 'jsr:@supabase/supabase-js@2';
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
const FALLBACK_MODELS = ['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8'];
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

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) { await logRun('error', { forbidden: 1, quote_extracted: 0 }, 'quote_extract rejected a caller with a missing/wrong inbound secret (403). A supplier quotation was not parsed — that supplier\'s price will be missing from the comparison the customer sees, which looks like the supplier simply never quoted.'); return J({ error: 'forbidden' }, 403); }
    const key = await sec('openrouter_api_key');
    if (!key) { await logRun('error', { quote_extracted: 0, ai_key_present: 0 }, 'quote_extract aborted: the openrouter_api_key secret is missing, so no supplier quotation can be read at all. Every quote uploaded while this persists is silently dropped and the customer sees fewer (or zero) quotes to compare.'); return J({ error: 'no ai key' }, 500); }
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
    const aiPages = imgs.length ? Math.min(imgs.length, 8) : (body.file_b64 ? 1 : 0);
    try {
      const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ models: FALLBACK_MODELS, max_tokens: 2000, temperature: 0.1, messages: [{ role: 'system', content: SYS }, { role: 'user', content }] }) });
      const jd = await r.json();
      if (!r.ok) { await logRun('error', { quote_extracted: 0, pages: aiPages, ai_ok: 0 }, 'quote_extract could not read a supplier quotation because the vision model call returned an error (' + String(jd?.error?.message || ('http ' + r.status)).slice(0, 140) + '). The supplier\'s quotation exists but produced no structured quote, so the customer\'s comparison is missing a real price.'); return J({ error: 'ai_error', detail: jd?.error?.message || JSON.stringify(jd).slice(0,300) }, 502); }
      const _rawContent = jd?.choices?.[0]?.message?.content || '{}';
      ai = parseJson(_rawContent);
      aiParseOk = !!(ai && typeof ai === 'object' && Object.keys(ai).length > 0);
    } catch (e) { await logRun('error', { quote_extracted: 0, pages: aiPages, ai_ok: 0 }, 'quote_extract threw while calling the vision model (' + String((e as Error)?.message || e).slice(0, 140) + '), so a supplier quotation was never converted into a comparable quote — the customer will see one fewer price and assume that supplier did not respond.'); return J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502); }

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
    return J({ ok: true, proposal: ai });
  } catch (e) { await logRun('error', { quote_extracted: 0, unhandled_exception: 1 }, 'quote_extract threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e).slice(0, 200) + ' — a supplier quotation was not converted into a comparable quote and will be missing from the customer\'s comparison.'); return J({ error: String((e as Error)?.message || e) }, 500); }
});
