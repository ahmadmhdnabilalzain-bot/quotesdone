// copilot — AI Marketplace Copilot (#4/#5). Role-aware assistant over platform data.
// Roles: admin (marketplace analytics), customer (own procurement), supplier (own performance/why-not-invited).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function llm(sys: string, msgs: { role: string; content: string }[], max = 1200): Promise<string | null> {
  const key = await sec('openrouter_api_key'); if (!key) return null;
  const MODELS = ['anthropic/claude-opus-4.8', 'anthropic/claude-sonnet-5'];
  for (const model of MODELS) { for (let at = 0; at < 2; at++) { try {
    const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model, max_tokens: max, temperature: 0.2, messages: [{ role: 'system', content: sys }, ...msgs] }) });
    const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c;
  } catch (_e) { /* next */ } } }
  return null;
}

async function identify(req: Request): Promise<{ role: string; id?: string; email: string } | null> {
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user?.email) return null;
  const email = user.email.toLowerCase();
  const admins = String((await sec('admin_emails')) || 'management@quotesdone.com').toLowerCase().split(',').map((s) => s.trim());
  if (admins.includes(email)) return { role: 'admin', email };
  const { data: c } = await admin.from('customers').select('id,banned').eq('email', email).maybeSingle();
  if (c && !c.banned) return { role: 'customer', id: c.id as string, email };
  const { data: l } = await admin.from('leads').select('id').eq('claimed_by', email).eq('claimed', true).maybeSingle();
  if (l) return { role: 'supplier', id: String(l.id), email };
  return null;
}

function toCats(v: unknown): string[] {
  if (Array.isArray(v)) return v.map((x) => String(x).trim()).filter(Boolean);
  return String(v || '').split(/[,;]/).map((s) => s.trim()).filter(Boolean);
}

async function snapshot(who: { role: string; id?: string }): Promise<any> {
  try {
    if (who.role === 'admin') { const { data } = await admin.rpc('fn_marketplace_analytics'); return { marketplace: data }; }
    if (who.role === 'customer') {
      const cid = who.id;
      const { data: inq } = await admin.from('inquiries').select('id,category,status,expected_value,hired_supplier_id,created_at').eq('customer_id', cid).order('created_at', { ascending: false }).limit(200);
      const { data: tx } = await admin.from('transactions').select('supplier_id,reveal_fee,quote_amount,revealed_at').eq('customer_id', cid);
      const { data: projs } = await admin.from('project_summary').select('*').eq('customer_id', cid);
      const suppliers = [...new Set((tx || []).map((t: any) => t.supplier_id).filter(Boolean))];
      const spend = (tx || []).reduce((a: number, t: any) => a + (Number(t.reveal_fee) || 0), 0);
      const byStatus: Record<string, number> = {}; for (const i of inq || []) byStatus[i.status || 'unknown'] = (byStatus[i.status || 'unknown'] || 0) + 1;
      return { rfqs_total: (inq || []).length, rfqs_by_status: byStatus, reveals: (tx || []).length, fees_paid_aed: Math.round(spend), suppliers_engaged: suppliers.length, projects: projs || [] };
    }
    if (who.role === 'supplier') {
      const sid = Number(who.id);
      const { data: twin } = await admin.from('supplier_twin').select('*').eq('supplier_id', sid).maybeSingle();
      const { data: lead } = await admin.from('leads').select('categories,sector,emirate,approval_status').eq('id', sid).maybeSingle();
      // leads.categories is a comma-separated string; the supplier's sector is also a valid category.
      const cats = Array.from(new Set([ ...toCats(lead?.categories), ...(lead?.sector ? [String(lead.sector).trim()] : []) ].filter(Boolean)));
      let missed = 0, matchedRecent = 0;
      if (cats.length) {
        const since = new Date(Date.now() - 30 * 864e5).toISOString();
        const { data: rfqs } = await admin.from('inquiries').select('id').in('category', cats).gte('created_at', since);
        const ids = (rfqs || []).map((r: any) => r.id);
        if (ids.length) { const { data: m } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sid).in('inquiry_id', ids); matchedRecent = (m || []).length; missed = ids.length - matchedRecent; }
      }
      return { twin: twin || null, approval_status: lead?.approval_status, categories: cats, recent_rfqs_in_your_categories_30d: matchedRecent + missed, you_were_matched: matchedRecent, you_were_not_matched: missed };
    }
  } catch (_e) { return { error: 'snapshot_unavailable' }; }
  return {};
}

const ROLE_GUIDE: Record<string, string> = {
  admin: 'You are the QuotesDone Marketplace Copilot for the founder/admin. Answer operational and analytical questions using the SNAPSHOT (live marketplace analytics). Cite concrete numbers from the snapshot; if something is not in the snapshot, say so plainly rather than guessing. Be concise and decision-useful.',
  customer: 'You are the QuotesDone Copilot helping a business customer manage their procurement. Use ONLY their own SNAPSHOT (their RFQs, spend, suppliers, projects). Answer their questions and suggest concrete next steps such as grouping RFQs into a project or chasing a stalled RFQ. Never reveal the private data of other customers or suppliers.',
  supplier: 'You are the QuotesDone Copilot helping a supplier win more work. Use ONLY their own SNAPSHOT (their performance twin, categories, and how many recent RFQs in their categories they were or were not matched to). If they ask why they are not getting invited, explain the likely reasons from the snapshot (approval status, category coverage, response rate, win rate, reputation) and give specific improvement steps. Never reveal customer contact details or competitor quotes.'
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const who = await identify(req);
    if (!who) return J({ error: 'unauthorized' }, 401);
    const msg = String(body.message || '').trim();
    if (!msg) return J({ error: 'message required' }, 400);
    const history = Array.isArray(body.history) ? body.history.slice(-6).map((h: any) => ({ role: h.role === 'assistant' ? 'assistant' : 'user', content: String(h.content || '').slice(0, 1500) })) : [];
    const snap = await snapshot(who);
    const sys = ROLE_GUIDE[who.role] + '\n\nSNAPSHOT (read-only, just captured):\n' + JSON.stringify(snap).slice(0, 6500);
    const reply = await llm(sys, [...history, { role: 'user', content: msg }], 1200) || 'I could not reach the AI service just now — please try again in a moment.';
    try { await admin.from('agent_runs').insert({ agent: 'copilot', started_at: new Date().toISOString(), finished_at: new Date().toISOString(), status: 'ok', counts: { role: who.role } }); } catch (_e) {}
    return J({ ok: true, role: who.role, reply });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
