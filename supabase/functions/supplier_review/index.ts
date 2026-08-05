import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

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
    const { data: sec } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'supplier_review');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    if (!sec?.value) return J({ ok: true, severity: 'clean', issues: [], summary: 'AI review unavailable (not configured).', fallback: true });

    const p = body.profile || {};
    const fields = ['company_name','sector','emirate','service_emirates','contact_name','signatory_name','phone','services','products','description','trade_license_no','license_authority','license_expiry','trn','egr_number','bank_name','bank_account_name','bank_iban'];
    const lines = fields.filter((f) => p[f] !== undefined && p[f] !== null && String(p[f]).trim() !== '').map((f) => `${f}: ${Array.isArray(p[f]) ? p[f].join(', ') : p[f]}`);
    const userMsg = 'SUPPLIER REGISTRATION TO REVIEW:\n' + lines.join('\n');

    const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: sec.value, fn: 'supplier_review', sys: SYS, input: userMsg, max: 800, temperature: 0.1 }),
    });
    const d = await r.json();
    if (!r.ok) return J({ ok: true, severity: 'review', issues: ['ai_review_unavailable'], summary: 'AI review failed; manual check advised.', fallback: true });
    // THE LAUNDERED REFUSAL (found 5 Aug 2026). This read `parseJson(d?.content || '{}')`, and the
    // `catch` below is the ONLY branch that sets fallback:true. But `'{}'` is VALID JSON - it does
    // not throw - so whenever the gateway returned no `content` at all, review became {}, issues
    // became [], and this function answered severity:'clean' WITH NO FALLBACK FLAG. supplier_api
    // then wrote that into leads.ai_review_notes and emailed the founder "AI check: clean".
    //
    // For months that was every single registration: supplier_review resolved to a task class with
    // tier='none', so fn_ai_route returned use_llm:false and ai_gateway answered 200 with no body.
    // Re-routing it to json_extraction fixes the cause, but NOT this: a budget halt, a rate limit or
    // a deterministic refusal all still produce an empty content and would read as "clean" forever.
    //
    // So absence of an answer is now 'review', never 'clean'. It still does not BLOCK registration -
    // the founder wants full automation and supplier_api only records flags - but a human is told
    // the machine did not look, instead of being told it looked and found nothing.
    const content = typeof d?.content === 'string' ? d.content.trim() : '';
    if (!content) return J({ ok: true, severity: 'review', issues: ['ai_review_did_not_run'], summary: 'The automated check did not run for this registration (no model response), so nothing has been verified. Please review manually.', fallback: true });
    let review;
    try { review = parseJson(content); }
    catch { return J({ ok: true, severity: 'review', issues: ['ai_review_unreadable'], summary: 'AI review unreadable; manual check advised.', fallback: true }); }
    if (!Array.isArray(review.issues)) review.issues = [];
    return J({ ok: review.ok !== false, severity: review.severity || (review.issues.length ? 'review' : 'clean'), issues: review.issues, summary: review.summary || '' });
  } catch (e) {
    return J({ ok: true, severity: 'clean', issues: [], summary: 'AI review error; manual check advised.', error: String((e as Error)?.message || e) });
  }
});