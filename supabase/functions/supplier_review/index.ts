import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const CLAUDE_MODELS = ['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8'];

const SYS = `You are a data-quality reviewer for QuotesDone, a UAE supplier marketplace. A supplier has just submitted their registration. Your job is to catch obvious mistakes BEFORE a human admin reviews it, so the admin's job is easy.

Check the provided fields for problems such as:
- Spelling mistakes or garbled text in the company name, services, or products.
- Placeholder / junk values (e.g. 'asdf', 'test', 'N/A', 'none', '123', random characters).
- Format issues: UAE TRN (VAT) should be 15 digits; UAE IBAN should start with 'AE' and be 23 characters; UAE mobile usually starts +9715 / 05; trade licence numbers are typically numeric.
- Mismatches: services/products that don't match the stated trade/sector; emirate that isn't a real UAE emirate.
- Missing critical info for matching (no services/products described).
- Anything that looks copy-pasted wrong or internally inconsistent.

Be practical, not pedantic — minor stylistic things are fine. Only flag things a human should actually look at or fix.

Return STRICT JSON only (no markdown), exact shape:
{"ok": boolean,                      // true if the registration looks clean enough to approve
 "severity": "clean"|"minor"|"review",  // clean = no issues, minor = small fixable issues, review = needs human attention
 "issues": [ {"field": string, "note": string} ],   // each problem found, empty array if none
 "summary": string }                  // one short sentence an admin reads at a glance`;

function parseJson(txt: string) { try { return JSON.parse(txt); } catch { const m = txt.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } throw new Error('AI returned non-JSON'); } }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const { data: sec } = await admin.from('app_secrets').select('value').eq('key', 'inbound_secret').maybeSingle();
    if (!sec?.value || body.__secret !== sec.value) return J({ error: 'forbidden' }, 403);
    const { data: keyRow } = await admin.from('app_secrets').select('value').eq('key', 'openrouter_api_key').maybeSingle();
    if (!keyRow?.value) return J({ ok: true, severity: 'clean', issues: [], summary: 'AI review unavailable (not configured).', fallback: true });

    const p = body.profile || {};
    const fields = ['company_name','sector','emirate','service_emirates','contact_name','signatory_name','phone','services','products','description','trade_license_no','license_authority','license_expiry','trn','egr_number','bank_name','bank_account_name','bank_iban'];
    const lines = fields.filter((f) => p[f] !== undefined && p[f] !== null && String(p[f]).trim() !== '').map((f) => `${f}: ${Array.isArray(p[f]) ? p[f].join(', ') : p[f]}`);
    const userMsg = 'SUPPLIER REGISTRATION TO REVIEW:\n' + lines.join('\n');

    const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${keyRow.value}`, 'Content-Type': 'application/json', 'HTTP-Referer': 'https://quotesdone.com', 'X-Title': 'QuotesDone' },
      body: JSON.stringify({ models: CLAUDE_MODELS, max_tokens: 800, temperature: 0.1, messages: [{ role: 'system', content: SYS }, { role: 'user', content: userMsg }] }),
    });
    const d = await r.json();
    if (!r.ok) return J({ ok: true, severity: 'clean', issues: [], summary: 'AI review failed; manual check advised.', fallback: true });
    let review;
    try { review = parseJson(d?.choices?.[0]?.message?.content || '{}'); }
    catch { return J({ ok: true, severity: 'clean', issues: [], summary: 'AI review unreadable; manual check advised.', fallback: true }); }
    if (!Array.isArray(review.issues)) review.issues = [];
    return J({ ok: review.ok !== false, severity: review.severity || (review.issues.length ? 'review' : 'clean'), issues: review.issues, summary: review.summary || '' });
  } catch (e) {
    return J({ ok: true, severity: 'clean', issues: [], summary: 'AI review error; manual check advised.', error: String((e as Error)?.message || e) });
  }
});