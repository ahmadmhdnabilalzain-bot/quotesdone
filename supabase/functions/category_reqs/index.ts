// category_reqs — AI category generator extension (#1): generate per-category supplier requirements
// + compliance checklists (UAE) into category_specs. Auth: __secret == inbound_secret.
// Actions: 'generate' {category}, 'backfill' {limit}.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function llm(sys: string, user: string, max = 1400): Promise<string | null> {
  const key = await sec('openrouter_api_key'); if (!key) return null;
  const MODELS = ['anthropic/claude-opus-4.8', 'anthropic/claude-sonnet-5'];
  for (const model of MODELS) { for (let at = 0; at < 2; at++) { try {
    const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model, max_tokens: max, temperature: 0.2, messages: [{ role: 'system', content: sys }, { role: 'user', content: user }] }) });
    const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c;
  } catch (_e) {} } }
  return null;
}
function parseJson(s: string): any { if (!s) return null; const m = s.match(/\{[\s\S]*\}/); if (!m) return null; try { return JSON.parse(m[0]); } catch { return null; } }

async function genOne(category: string, label: string): Promise<boolean> {
  const sys = 'You define onboarding standards for a UAE B2B services marketplace. For the given service category, produce (1) SUPPLIER REQUIREMENTS: what a legitimate supplier in this trade must have to be approved and to quote credibly in the UAE (licences, trade-licence activity, certifications, insurances, technical staff/tickets, equipment, portfolio, approvals from authorities), and (2) a COMPLIANCE CHECKLIST: the UAE regulatory / safety / documentation items relevant to delivering this service (e.g. Dubai Municipality, Civil Defence, DEWA, ADDC, ESMA, HACCP, third-party inspections, warranties, insurances, permits). Be specific and realistic to the UAE. Return ONLY JSON: {"supplier_requirements":[{"item":string,"why":string,"mandatory":boolean}],"compliance_checklist":[{"item":string,"authority":string|null,"notes":string|null}]}.';
  const raw = await llm(sys, 'Category: ' + category + (label ? ' (' + label + ')' : ''), 1500);
  const out = parseJson(raw || '');
  if (!out || !Array.isArray(out.supplier_requirements)) return false;
  const { error } = await admin.from('category_specs').update({
    supplier_requirements: out.supplier_requirements,
    compliance_checklist: out.compliance_checklist || [],
    reqs_updated_at: new Date().toISOString()
  }).eq('category', category);
  return !error;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
  const action = String(body.action || 'generate');

  if (action === 'generate') {
    const category = String(body.category || '').trim();
    if (!category) return J({ error: 'category required' }, 400);
    const { data: cs } = await admin.from('category_specs').select('category,label').eq('category', category).maybeSingle();
    if (!cs) return J({ error: 'unknown category' }, 404);
    const ok = await genOne(category, cs.label || '');
    return J({ ok, category });
  }

  if (action === 'backfill') {
    const limit = Math.min(Math.max(parseInt(String(body.limit || '3'), 10) || 3, 1), 8);
    const { data: rows } = await admin.from('category_specs').select('category,label').is('supplier_requirements', null).limit(limit);
    const done: string[] = [];
    for (const r of rows || []) { if (await genOne(r.category, (r as any).label || '')) done.push(r.category); }
    return J({ ok: true, generated: done, remaining_unfilled: 'run again to continue' });
  }

  return J({ error: 'unknown action' }, 400);
});
