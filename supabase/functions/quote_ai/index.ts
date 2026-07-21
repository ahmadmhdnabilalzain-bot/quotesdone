// quote_ai - reads a supplier's PASTED quotation TEXT and returns an ANONYMIZED standardized quote,
// in the same {ok, proposal, masked_terms} shape the supplier portal consumes for the file/image path.
// Restored 2026-07-19: the portal's paste-text path called this function, which had been deleted (404).
// Text-mode sibling of quote_extract; reuses its masking contract so supplier identity cannot leak (ADR-010).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const FALLBACK_MODELS = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8'];
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'quote_ai', status, counts, note: String(note || '').slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() }); } catch (_e) { /* logging must never break the function */ }
}
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function parseJson(t: string) { try { return JSON.parse(t); } catch { const m = t.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return {}; } }
function scrub(s: unknown): string {
  let t = String(s == null ? '' : s);
  t = t.replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '█');
  t = t.replace(/https?:\/\/\S+|www\.[\w.-]+\.[a-z]{2,}/gi, '█');
  t = t.replace(/(?:\+?\d[\d\s().-]{6,}\d)/g, (m) => (m.replace(/\D/g, '').length >= 7 ? '█' : m));
  return t.trim();
}
const SYS = `You read a supplier's price QUOTATION (pasted as plain text) for a UAE building / fit-out job and convert it into an ANONYMOUS standardized quote for QuotesDone, a marketplace where the customer must PAY to reveal the supplier. The customer must NOT be able to identify the supplier from anything you output.\n\nRead every line carefully. Extract all commercial figures, then REWRITE every text field so it cannot reveal who the supplier is.\n\nMASK / REMOVE: company name, letterhead, slogan, person names, signatures; phone, email, website, address, social handles, trade-license / TRN / VAT numbers, bank details; brand names, manufacturer names, product model names or numbers, and any proprietary product line a customer could search online to identify a specific seller. Replace with a neutral equivalent that preserves spec and quality tier (e.g. 'premium branded 120x60 porcelain', 'premium branded mixer'). Remove any unusually distinctive wording that could fingerprint the supplier.\n\nKEEP (these matter for comparing quotes): amounts, currency, quantities, dimensions/sizes, generic material & spec, quality tier, finish, lead time, validity, payment terms, warranty, scope, conditions, exclusions.\n\nReturn STRICT JSON only, no prose:\n{\"amount\":number,\"currency\":\"AED\",\"line_items\":[{\"description\":string,\"qty\":string,\"amount\":number}],\"lead_time\":string,\"validity\":string,\"payment_terms\":string,\"warranty\":string,\"scope\":string,\"conditions\":string,\"exclusions\":string,\"notes\":string,\"description_anonymized\":string,\"masked_terms\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\namount = the GRAND TOTAL of the whole quotation, not a single line. Every string field must ALREADY be anonymized. masked_terms = the original identity-revealing strings you removed (shown ONLY to the supplier for review, never to the customer). If a value is absent, use an empty string (or [] for line_items).`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Please sign in to your supplier account first.' }, 401);
    const email = user.email.toLowerCase();
    const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
    if (!sup) return J({ error: 'Claim your company first.' }, 400);
    const body = await req.json().catch(() => ({} as any));
    const text = String(body.text || '').trim();
    if (text.length < 10) return J({ error: 'Paste the quotation text so we can read and anonymise it.' }, 400);
    const key = await sec('openrouter_api_key');
    if (!key) { await logRun('error', { extracted: 0, ai_key_present: 0 }, 'quote_ai aborted: openrouter_api_key missing; the supplier pasted a quotation but nothing could be anonymised.'); return J({ error: 'AI is temporarily unavailable - please fill the form or upload the file instead.' }, 500); }
    let ai: any = {}; let parseOk = false;
    try {
      const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ models: FALLBACK_MODELS, max_tokens: 2000, temperature: 0.1, messages: [{ role: 'system', content: SYS }, { role: 'user', content: `Supplier's pasted quotation text:\n\n${text.slice(0, 12000)}` }] }) });
      const jd = await r.json();
      if (!r.ok) { await logRun('error', { extracted: 0, ai_ok: 0 }, 'quote_ai: model call error ' + String(jd?.error?.message || ('http ' + r.status)).slice(0, 140)); return J({ error: 'Could not read the quotation. Please fill the form instead.', detail: jd?.error?.message || ('http ' + r.status) }, 502); }
      ai = parseJson(jd?.choices?.[0]?.message?.content || '{}');
      parseOk = !!(ai && typeof ai === 'object' && Object.keys(ai).length > 0);
    } catch (e) { await logRun('error', { extracted: 0, ai_ok: 0 }, 'quote_ai threw calling the model: ' + String((e as Error)?.message || e).slice(0, 140)); return J({ error: 'Reading failed, please try again or fill the form.', detail: String((e as Error)?.message || e) }, 502); }
    const textFields = ['lead_time', 'validity', 'payment_terms', 'warranty', 'scope', 'conditions', 'exclusions', 'notes', 'description_anonymized'];
    for (const f of textFields) ai[f] = scrub(ai[f]);
    if (Array.isArray(ai.line_items)) ai.line_items = ai.line_items.map((li: any) => ({ description: scrub(li?.description), qty: String(li?.qty || ''), amount: Number(li?.amount) || null })); else ai.line_items = [];
    ai.amount = Number(ai.amount) || null; ai.currency = 'AED';
    if (!Array.isArray(ai.masked_terms)) ai.masked_terms = [];
    if (!parseOk) { await logRun('error', { extracted: 0, parse_ok: 0 }, 'quote_ai: model output was not parseable JSON; supplier asked to use the form.'); return J({ error: 'Could not read the quotation clearly. Please fill the form instead.' }, 200); }
    await logRun(ai.amount != null ? 'ok' : 'error', { extracted: ai.amount != null ? 1 : 0, line_items: ai.line_items.length, masked_terms: ai.masked_terms.length, confidence: ai.confidence || null }, 'quote_ai anonymised a pasted quotation: total AED ' + String(ai.amount) + ', ' + ai.line_items.length + ' line item(s), ' + ai.masked_terms.length + ' term(s) masked.' + (ai.masked_terms.length === 0 ? ' NOTE: 0 masked - verify anonymisation ran.' : ''));
    return J({ ok: true, proposal: ai, masked_terms: ai.masked_terms });
  } catch (e) { await logRun('error', { extracted: 0, unhandled: 1 }, 'quote_ai 500: ' + String((e as Error)?.message || e).slice(0, 200)); return J({ error: String((e as Error)?.message || e) }, 500); }
});