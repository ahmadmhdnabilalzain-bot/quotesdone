// project_consultant — AI Project Consultant (#7) + AI Scope Builder (#8).
// Customer Supabase JWT auth (email->customers). Actions: plan, scope, create.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

const llm = makeLlm(SONNET_FIRST, { max: 2200, temperature: 0.3 }); // shared OpenRouter client (Sonnet-first + 25s timeout)
function parseJson(s: string): any { if (!s) return null; const m = s.match(/\{[\s\S]*\}/); if (!m) return null; try { return JSON.parse(m[0]); } catch { return null; } }

async function customer(req: Request): Promise<{ id: string; email: string } | null> {
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user?.email) return null;
  const { data: c } = await admin.from('customers').select('id,email,banned').eq('email', user.email.toLowerCase()).maybeSingle();
  if (!c || c.banned) return null;
  return { id: c.id as string, email: c.email as string };
}
async function categoryList(): Promise<string> {
  const { data } = await admin.from('category_specs').select('category,label');
  return (data || []).map((r: any) => r.category + (r.label ? ' (' + r.label + ')' : '')).join(', ');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const cust = await customer(req);
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const action = String(body.action || 'plan');

    if (action === 'plan') {
      const desc = String(body.description || '').trim();
      if (desc.length < 8) return J({ error: 'Please describe your project.' }, 400);
      const cats = await categoryList();
      const sys = 'You are a senior procurement consultant for QuotesDone, the UAE B2B services marketplace. A business customer describes a project in plain language. Act like a seasoned consultant, not a form. Decompose the project into the distinct services (RFQs) they will need, each mapped to ONE of the platform categories below when possible. For each RFQ write a clear, supplier-quotable scope. Identify missing information and ask concise follow-up questions. Estimate a realistic AED budget range and timeline for the whole project, flag any UAE permits/approvals likely required (e.g., Dubai Municipality, Civil Defence, DEWA, free-zone approvals), and suggest optional services often forgotten. Use realistic UAE market context. Do NOT invent supplier names or exact prices as facts — give ranges.\n\nPLATFORM CATEGORIES: ' + cats + '\n\nReturn ONLY valid minified JSON with this shape: {"project":{"name":string,"summary":string,"target_open_date":string|null,"budget_range_aed":{"low":number,"high":number},"timeline":string},"rfqs":[{"category":string,"title":string,"scope":string,"est_budget_aed":{"low":number,"high":number},"priority":"high"|"medium"|"low"}],"questions":[string],"permits":[string],"optional_services":[string]}. No prose outside the JSON.';
      const raw = await llm(sys, desc, 2600);
      if (!raw) return J({ error: 'ai_unavailable', message: 'The consultant is busy — please try again in a moment.' }, 200);
      const plan = parseJson(raw);
      if (!plan || !Array.isArray(plan.rfqs)) return J({ error: 'parse_failed', raw: raw.slice(0, 500) }, 200);
      return J({ ok: true, plan });
    }

    if (action === 'scope') {
      const category = String(body.category || '').trim();
      const brief = String(body.description || body.brief || '').trim();
      if (brief.length < 4) return J({ error: 'Describe what you need.' }, 400);
      const sys = 'You are a senior ' + (category || 'services') + ' scoping expert for a UAE B2B marketplace. Turn the buyer\'s short brief into a precise, itemized, supplier-quotable scope of work: quantities, specs, materials, applicable standards, and the full delivery checklist (supply, installation, testing, commissioning, training, warranty, handover documents) as applicable to this trade. Use UAE norms. Do NOT invent prices. Return ONLY JSON: {"title":string,"items":[{"item":string,"qty":string|null,"spec":string|null}],"inclusions":[string],"exclusions":[string],"assumptions":[string]}.';
      const raw = await llm(sys, (category ? ('Category: ' + category + '\n') : '') + brief, 1900);
      const out = parseJson(raw || '');
      if (!out) return J({ error: 'ai_unavailable_or_parse', raw: (raw || '').slice(0, 400) }, 200);
      return J({ ok: true, scope: out });
    }

    if (action === 'create') {
      const plan = body.plan || {};
      const pj = plan.project || {};
      const name = String(pj.name || body.name || 'New project').slice(0, 160);
      const rfqs = Array.isArray(plan.rfqs) ? plan.rfqs.slice(0, 25) : [];
      const budget = pj?.budget_range_aed?.high ? Number(pj.budget_range_aed.high) : null;
      const { data: proj, error: pe } = await admin.from('projects').insert({
        customer_id: cust.id, name, description: String(pj.summary || '').slice(0, 4000) || null,
        target_open_date: /^\d{4}-\d{2}-\d{2}$/.test(String(pj.target_open_date || '')) ? pj.target_open_date : null,
        budget_total: budget, meta: { source: 'project_consultant', permits: plan.permits || [], optional_services: plan.optional_services || [] }
      }).select('*').maybeSingle();
      if (pe || !proj) return J({ error: pe?.message || 'create_failed' }, 500);
      let created = 0;
      for (const r of rfqs) {
        const cat = String(r.category || '').split(' ')[0];
        const scope = String(r.scope || r.title || '').slice(0, 6000);
        const { error } = await admin.from('inquiries').insert({
          customer_id: cust.id, project_id: proj.id, category: cat || null,
          summary: String(r.title || cat || 'Service').slice(0, 300), raw_input: scope,
          spec: { scope, est_budget_aed: r.est_budget_aed || null, priority: r.priority || 'medium', from_project: proj.id },
          status: 'draft', brief_source: 'project_consultant', scope_type: 'project_rfq'
        });
        if (!error) created++;
      }
      return J({ ok: true, project_id: proj.id, rfqs_created: created });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
