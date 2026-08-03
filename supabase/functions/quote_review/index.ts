// quote_review - supplier-side quote-detailing agent. Audits an uploaded quotation's extracted line
// items, drives an agent<->supplier Q&A to capture brand/model/spec/qty/price/warranty, handles
// OUTSOURCED lines (attached sub-quote + markup %), and returns confirmed committed items + the next
// question + whether the quote is complete. Never blindly accepts a vague line. Auth: inbound_secret.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t: string) { try { return JSON.parse(t); } catch { /* */ } const m = t.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; }
function num(v: unknown): number | null { const n = Number(v); return Number.isFinite(n) ? n : null; }
function round2(n: number) { return Math.round(n * 100) / 100; }

const SYS = `You are QuotesDone's senior quotation auditor for the UAE building / fit-out / MEP market. A verified supplier has uploaded a price quotation in response to a customer job. Your job is to turn it into a DETAILED, COMPARABLE, BINDING line-item spec sheet by talking to the supplier - NOT by blindly accepting what they wrote.

Why this matters: competing suppliers' quotes are compared side by side, and the winning supplier must deliver EXACTLY what they quoted. So every priced line must name the actual brand, model, and specification - never a vague lump like "CCTV system - AED 10,000". A supplier cannot hide a cheap 2MP camera behind a round number.

For EACH line item decide if it is COMPLETE enough to be binding and comparable. A line is complete only when it has, as applicable to that trade:
- a clear description of what it is,
- the BRAND and MODEL / part reference (or an explicit generic spec if the item is genuinely unbranded, e.g. "gypsum board 12.5mm"),
- the technical SPEC that drives price and quality (e.g. camera resolution + storage/retention; tile material + size; paint type + coats; AC tonnage; cable category),
- quantity,
- unit price and/or line total (must reconcile with the line amount),
- warranty where a customer would expect one (electronics, equipment, workmanship).

OUTSOURCED lines: some trades sub-contract part of the scope (e.g. a fit-out company outsources acoustic panels or CCTV to a specialist) and add a markup. If a line looks outsourced, or the supplier says it is, mark source="outsourced" and require: (1) the attached sub-supplier quotation, and (2) the markup percent the supplier wants to add. Then compute line_amount = round(sub_cost * (1 + markup_pct/100)). Confirm the maths back to the supplier.

ANONYMITY: the customer sees these lines BEFORE paying to reveal the supplier, so nothing may identify WHO the supplier is. Commodity brands that many UAE suppliers resell (common camera, ceramic, paint, AC, cable brands) are fine to show - they do not reveal the seller. But if a brand/line is EXCLUSIVE to one distributor (sole-agent, a supplier's own private label, or wording that fingerprints the company), set hide_brand=true and write customer_description with the spec/quality tier only (e.g. "premium branded 4MP dome cameras"). Never put the supplier's company name, phone, email, website, or licence number into any field.

TONE: talk to the supplier like a sharp, respectful estimator colleague. Ask only what is genuinely missing, batched into ONE concise message (a short intro + a bullet per open line). Never re-ask something already answered in the conversation. If everything is complete, say so briefly and set status="complete". Mirror the supplier's language.

You are given: the customer job context, the raw extracted quotation, the committed items so far, the full conversation, and the supplier's latest reply (which may include extracted totals from attached sub-quotes). Merge the latest reply into the items.

Return STRICT JSON ONLY (no markdown):
{
  "status": "incomplete" | "complete",
  "message": "your next message to the supplier (their language; concise). Empty allowed only when complete.",
  "items": [
    {"seq":number,"description":string,"brand":string,"model":string,"spec":string,"qty":string,
     "unit_price":number|null,"line_amount":number|null,"warranty":string,
     "source":"own"|"outsourced","sub_cost":number|null,"markup_pct":number|null,
     "customer_description":string,"hide_brand":boolean,"confirmed":boolean}
  ],
  "total": number|null
}
Rules: include EVERY line from the quotation in items (confirmed true/false). confirmed=true only when that line meets the completeness bar above. status="complete" only when ALL lines are confirmed and the item totals reconcile to the grand total. customer_description must always be filled (anonymized). Keep brand/model/spec factual - never invent details the supplier did not give; if unknown, leave "" and keep confirmed=false.`;

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'quote_review');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    const inq = body.inquiry || {};
    const extracted = body.extracted || {};
    const committed = Array.isArray(body.committed) ? body.committed : [];
    const history = Array.isArray(body.history) ? body.history : [];
    const reply = body.supplier_reply || null;

    const ctx: string[] = [];
    ctx.push('CUSTOMER JOB: ' + [inq.category && ('category ' + inq.category), inq.summary && ('scope: ' + inq.summary)].filter(Boolean).join(' | '));
    ctx.push('RAW EXTRACTED QUOTATION (grand total ' + (extracted.amount ?? '?') + ' ' + (extracted.currency || 'AED') + '):\n' + JSON.stringify({ amount: extracted.amount, line_items: extracted.line_items || [], warranty: extracted.warranty, scope: extracted.scope, lead_time: extracted.lead_time }));
    ctx.push('COMMITTED ITEMS SO FAR:\n' + JSON.stringify(committed));
    if (history.length) ctx.push('CONVERSATION SO FAR:\n' + history.map((m: any) => (m.role === 'agent' ? 'AGENT' : 'SUPPLIER') + ': ' + String(m.body || '')).join('\n'));
    if (reply) {
      let r = 'SUPPLIER LATEST REPLY: ' + String(reply.body || '');
      if (Array.isArray(reply.sub_quotes) && reply.sub_quotes.length) r += '\nATTACHED SUB-QUOTE(S) (extracted): ' + JSON.stringify(reply.sub_quotes.map((s: any) => ({ name: s.name, total: s.total, line_items: s.line_items || [] })));
      ctx.push(r);
    } else if (!history.length) {
      ctx.push('This is the FIRST pass - audit the raw quotation and open the conversation.');
    }

    let ai: any = null;
    for (let at = 0; at < 2 && !ai; at++) { try {
      const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: __exp, fn: 'quote_review', sys: SYS, input: ctx.join('\n\n'), max: 2600, temperature: 0.15 }) });
      const jd = await r.json(); const c = jd?.content; if (c) { const p = parseJson(c); if (p && Array.isArray(p.items)) { ai = p; break; } }
    } catch (_e) { /* try next */ } }
    if (!ai) return J({ error: 'ai_unavailable' }, 502);

    const items = (ai.items || []).map((it: any, i: number) => {
      const source = it.source === 'outsourced' ? 'outsourced' : 'own';
      const sub = num(it.sub_cost); const mk = num(it.markup_pct); let line = num(it.line_amount); const unit = num(it.unit_price);
      if (source === 'outsourced' && sub != null && mk != null) line = round2(sub * (1 + mk / 100));
      return {
        seq: Number(it.seq) || i + 1,
        description: String(it.description || '').slice(0, 300),
        brand: String(it.brand || '').slice(0, 120),
        model: String(it.model || '').slice(0, 120),
        spec: String(it.spec || '').slice(0, 600),
        qty: String(it.qty || '').slice(0, 60),
        unit_price: unit,
        line_amount: line,
        warranty: String(it.warranty || '').slice(0, 200),
        source,
        sub_cost: source === 'outsourced' ? sub : null,
        markup_pct: source === 'outsourced' ? mk : null,
        customer_description: String(it.customer_description || it.description || '').slice(0, 400),
        hide_brand: it.hide_brand === true,
        confirmed: it.confirmed === true,
      };
    });
    const allConfirmed = items.length > 0 && items.every((x: any) => x.confirmed);
    const status = (ai.status === 'complete' && allConfirmed) ? 'complete' : 'incomplete';
    let total = num(ai.total);
    if (total == null) { const s = items.reduce((a: number, x: any) => a + (x.line_amount || 0), 0); total = s > 0 ? round2(s) : null; }

    return J({ ok: true, status, message: String(ai.message || '').slice(0, 3000), items, total });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
