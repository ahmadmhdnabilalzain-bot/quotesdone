import { siteCors } from '../_shared/site_origins.ts';
// project_api — Procurement Projects for customers. Groups multiple RFQs (inquiries) under a project.
// Auth: customer Supabase JWT -> email -> customers row (same model as customer_api).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { parseBudget } from '../_shared/project_budget.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function customer(req: Request): Promise<{ id: string; email: string } | null> {
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user?.email) return null;
  const { data: c } = await admin.from('customers').select('id,email,banned').eq('email', user.email.toLowerCase()).maybeSingle();
  if (!c || c.banned) return null;
  return { id: c.id as string, email: c.email as string };
}

Deno.serve(siteCors(observe('project_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // KEEP-WARM (resilience_ping, 14 Sep 2026). No auth, no DB, before anything else: the isolate is
  // what needs exercising, not a real answer. See the header of resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    const body = await req.json().catch(() => ({} as any));
    const cust = await customer(req);
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const action = String(body.action || '');

    // 21 Sep 2026 (customer audit, finding 19): a project with a revealed AED 25,920 quote showed
    // "pipeline AED 0" and "no cost recorded". Nothing writes inquiries.expected_value, so the view's
    // sum was always 0. The cost of an RFQ is expected_value when set, else the quote the customer
    // paid to reveal (transactions.quote_amount; the latest reveal when there are several).
    const revealedValueByInquiry = async (): Promise<Record<string, number>> => {
      const { data } = await admin.from('transactions').select('inquiry_id,quote_amount,revealed_at').eq('customer_id', cust.id).order('revealed_at', { ascending: true });
      const out: Record<string, number> = {};
      for (const t of data || []) { const a = Number((t as any).quote_amount); if (a > 0) out[String((t as any).inquiry_id)] = a; }
      return out;
    };

    if (action === 'list') {
      const [{ data }, rv, { data: inqRows }] = await Promise.all([
        admin.from('project_summary').select('*').eq('customer_id', cust.id).order('created_at', { ascending: false }),
        revealedValueByInquiry(),
        admin.from('inquiries').select('id,project_id,expected_value').eq('customer_id', cust.id).not('project_id', 'is', null),
      ]);
      const pipeline: Record<string, number> = {};
      for (const i of inqRows || []) { const v = Number((i as any).expected_value) || rv[String((i as any).id)] || 0; pipeline[String((i as any).project_id)] = (pipeline[String((i as any).project_id)] || 0) + v; }
      return J({ ok: true, projects: (data || []).map((p: any) => ({ ...p, pipeline_value: Math.round(pipeline[String(p.project_id)] || 0) })) });
    }

    if (action === 'dashboard') {
      const cid = cust.id;
      // ONE WAVE, NOT TWO (coordinator ruling G5, 19 Oct 2026). The quotes read used to wait for the
      // inquiries read so it could pass their ids. Every read here is sub-millisecond in Postgres
      // (EXPLAIN of the joined quotes read: 0.16 ms), so what it cost was one more edge-to-database
      // round trip on the overview's critical path. The quotes are joined to their inquiry by customer
      // and start with the other three; the 300-inquiry window is applied in memory, so the answer is
      // unchanged.
      const [{ data: inq }, { data: tx }, { data: projs }, { data: qAll }] = await Promise.all([
        admin.from('inquiries').select('id,category,status,expected_value,hired_supplier_id,created_at').eq('customer_id', cid).order('created_at', { ascending: false }).limit(300),
        admin.from('transactions').select('supplier_id,reveal_fee,quote_amount,revealed_at').eq('customer_id', cid),
        admin.from('project_summary').select('*').eq('customer_id', cid),
        admin.from('quotes').select('inquiry_id,quote_amount,created_at,inquiries!inner(customer_id)').eq('inquiries.customer_id', cid),
      ]);
      const inqs = inq || []; const txs = tx || [];
      const closed = ['completed', 'cancelled', 'closed', 'won', 'lost'];
      const active = inqs.filter((i: any) => !closed.includes(String(i.status || ''))).length;
      const suppliers = [...new Set(txs.map((t: any) => t.supplier_id).filter(Boolean))];
      const spend = txs.reduce((a: number, t: any) => a + (Number(t.reveal_fee) || 0), 0);
      const byStatus: Record<string, number> = {}; for (const i of inqs) { const k = i.status || 'unknown'; byStatus[k] = (byStatus[k] || 0) + 1; }
      let avgResp: number | null = null; let savingsPct: number | null = null;
      try {
        const inWindow = new Set(inqs.map((i: any) => String(i.id)));
        if (inWindow.size) {
          const q = (qAll || []).filter((r: any) => inWindow.has(String(r.inquiry_id)));
          const first: Record<string, number> = {}; const byRfq: Record<string, number[]> = {};
          for (const r of (q || [])) {
            const t = +new Date((r as any).created_at); const iid = (r as any).inquiry_id;
            if (!first[iid] || t < first[iid]) first[iid] = t;
            const a = Number((r as any).quote_amount); if (a > 0) (byRfq[iid] = byRfq[iid] || []).push(a);
          }
          const created: Record<string, number> = {}; for (const i of inqs) created[i.id] = +new Date(i.created_at);
          const diffs = Object.keys(first).map((id) => (first[id] - created[id]) / 3.6e6).filter((h) => h >= 0 && h < 24 * 90);
          if (diffs.length) avgResp = Math.round(diffs.reduce((a, b) => a + b, 0) / diffs.length * 10) / 10;
          const spreads = Object.values(byRfq).filter((arr) => arr.length >= 2).map((arr) => { const hi = Math.max(...arr), lo = Math.min(...arr); return hi > 0 ? 100 * (hi - lo) / hi : 0; });
          if (spreads.length) savingsPct = Math.round(spreads.reduce((a, b) => a + b, 0) / spreads.length * 10) / 10;
        }
      } catch (_e) { /* metrics best-effort */ }
      const recent = inqs.slice(0, 12).map((i: any) => ({ id: i.id, category: i.category, status: i.status, expected_value: i.expected_value, created_at: i.created_at }));
      return J({ ok: true, dashboard: {
        rfqs_total: inqs.length, active_rfqs: active, rfqs_by_status: byStatus,
        reveals: txs.length, fees_paid_aed: Math.round(spend), suppliers_engaged: suppliers.length,
        awarded: inqs.filter((i: any) => i.hired_supplier_id).length,
        avg_first_response_hours: avgResp, avg_savings_pct: savingsPct,
        projects: projs || [], recent
      } });
    }

    if (action === 'create') {
      const name = String(body.name || '').trim().slice(0, 160);
      if (!name) return J({ error: 'name required' }, 400);
      // The budget is bounded HERE, the trust boundary (_shared/project_budget.ts); the form only says it sooner.
      const budget = parseBudget(body.budget_total);
      if (!budget.ok) return J({ error: budget.code, message: budget.en, message_ar: budget.ar }, 400);
      const row: Record<string, unknown> = { customer_id: cust.id, name,
        description: String(body.description || '').slice(0, 4000) || null,
        target_open_date: /^\d{4}-\d{2}-\d{2}$/.test(String(body.target_open_date || '')) ? body.target_open_date : null,
        budget_total: budget.value };
      const { data, error } = await admin.from('projects').insert(row).select('*').maybeSingle();
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, project: data });
    }

    if (action === 'update') {
      const id = String(body.id || ''); if (!id) return J({ error: 'id required' }, 400);
      const { data: p } = await admin.from('projects').select('id').eq('id', id).eq('customer_id', cust.id).maybeSingle();
      if (!p) return J({ error: 'not_found' }, 404);
      const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
      if (body.name !== undefined) patch.name = String(body.name).slice(0, 160);
      if (body.description !== undefined) patch.description = String(body.description).slice(0, 4000);
      if (body.status !== undefined && ['active','completed','archived'].includes(String(body.status))) patch.status = body.status;
      if (body.target_open_date !== undefined) patch.target_open_date = /^\d{4}-\d{2}-\d{2}$/.test(String(body.target_open_date)) ? body.target_open_date : null;
      if (body.budget_total !== undefined) {
        const budget = parseBudget(body.budget_total);
        if (!budget.ok) return J({ error: budget.code, message: budget.en, message_ar: budget.ar }, 400);
        patch.budget_total = budget.value;
      }
      const { error } = await admin.from('projects').update(patch).eq('id', id);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true });
    }

    if (action === 'detail') {
      const id = String(body.id || ''); if (!id) return J({ error: 'id required' }, 400);
      const { data: p } = await admin.from('projects').select('*').eq('id', id).eq('customer_id', cust.id).maybeSingle();
      if (!p) return J({ error: 'not_found' }, 404);
      const { data: rfqs } = await admin.from('inquiries')
        .select('id,rfq_no,category,emirate,summary,status,pipeline_stage,budget,expected_value,hired_supplier_id,created_at')
        .eq('project_id', id).eq('customer_id', cust.id).order('created_at', { ascending: false });
      // The COMPUTED figures live on the project_summary view, not on the projects row: the trade
      // breakdown, the suppliers engaged on THIS project, and how far through its timeline it is.
      // detail returned the raw row only, so a caller that opened one project saw fewer numbers than
      // the list it came from. timeline_pct is null when the project has no target open date — a
      // project with no deadline has no timeline completion and must not be drawn as 0%.
      const [{ data: summary }, rv] = await Promise.all([admin.from('project_summary').select('*').eq('project_id', id).maybeSingle(), revealedValueByInquiry()]);
      return J({
        ok: true, project: p, summary: summary || null, rfqs: (rfqs || []).map((r: any) => ({ ...r, revealed_value: rv[String(r.id)] ?? null })),
        trade_breakdown: summary?.trade_breakdown ?? [],
        supplier_count: summary?.supplier_count ?? 0,
        timeline_pct: summary?.timeline_pct ?? null,
      });
    }

    if (action === 'link' || action === 'unlink') {
      const inquiry_id = String(body.inquiry_id || ''); if (!inquiry_id) return J({ error: 'inquiry_id required' }, 400);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id').eq('id', inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'rfq_not_found' }, 404);
      let project_id: string | null = null;
      if (action === 'link') {
        project_id = String(body.project_id || ''); if (!project_id) return J({ error: 'project_id required' }, 400);
        const { data: p } = await admin.from('projects').select('id').eq('id', project_id).eq('customer_id', cust.id).maybeSingle();
        if (!p) return J({ error: 'project_not_found' }, 404);
      }
      const { error } = await admin.from('inquiries').update({ project_id }).eq('id', inquiry_id);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
})));
