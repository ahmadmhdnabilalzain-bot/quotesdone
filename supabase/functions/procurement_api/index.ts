// procurement_api — the customer-authed surface for spec §12 (Purchase Approval System) and the
// §22 Orders module. Auth: customer Supabase JWT -> email -> customers row (same model as
// customer_api and project_api).
//
// It serves procurement_approval_request / procurement_approval_policy and the customer-scoped
// slice of po_orders. Every table read goes through a SECURITY DEFINER routine or is scoped to the
// caller's own organization in the same statement — the service role client below can see every
// row in the database, so nothing here may take an id from the request body and trust it.
//
// ACTIONS
//   approvals  {}                                  -> { ok, organizations[], policies[], requests[] }
//                                                     each request carries steps[] already projected
//                                                     as Approved / Pending / Waiting / Rejected.
//   trace      { request_id }                      -> { ok, request, steps[] }
//   decide     { request_id, decision, note? }     -> { ok, status, decided_step, current_step, ... }
//                                                     decision is 'approved' | 'rejected'.
//   orders     {}                                  -> { ok, orders[] } (this customer's orders only)
//
// HONEST EMPTY STATE: a customer with no organization gets organizations: [], policies: [],
// requests: [] and no invented chain. A customer with no orders gets orders: []. Nothing here
// implies a workflow that does not exist.
import { createClient } from 'jsr:@supabase/supabase-js@2';

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

// The organizations this customer owns or is an active member of. Everything else in this file is
// filtered on the result, so an id supplied by the caller can never widen what they see.
async function orgIds(customerId: string): Promise<string[]> {
  const [{ data: owned }, { data: member }] = await Promise.all([
    admin.from('customer_organization').select('id').eq('owner_customer_id', customerId),
    admin.from('customer_organization_member').select('organization_id').eq('user_id', customerId).eq('active', true),
  ]);
  return [...new Set([...(owned || []).map((o: any) => o.id), ...(member || []).map((m: any) => m.organization_id)])];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const cust = await customer(req);
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const action = String(body.action || '');

    if (action === 'approvals') {
      const { data, error } = await admin.rpc('fn_approval_list', { p_customer: cust.id });
      if (error) return J({ error: error.message }, 500);
      const d = (data || {}) as Record<string, unknown>;
      return J({ ok: true, organizations: d.organizations || [], policies: d.policies || [], requests: d.requests || [] });
    }

    if (action === 'trace') {
      const rid = String(body.request_id || '');
      if (!rid) return J({ error: 'request_id required' }, 400);
      const orgs = await orgIds(cust.id);
      if (!orgs.length) return J({ error: 'not your approval request' }, 403);
      const { data: r } = await admin.from('procurement_approval_request')
        .select('id,organization_id,entity_type,entity_id,policy_id,status,current_step,created_at')
        .eq('id', rid).in('organization_id', orgs).maybeSingle();
      if (!r) return J({ error: 'not your approval request' }, 403);
      const { data: steps } = await admin.from('v_approval_trace')
        .select('step,step_key,step_label,step_role,step_status,decided_by,decided_at,decision_note')
        .eq('request_id', rid).order('step');
      return J({ ok: true, request: r, steps: steps || [] });
    }

    if (action === 'decide') {
      const rid = String(body.request_id || '');
      const decision = String(body.decision || '');
      if (!rid) return J({ error: 'request_id required' }, 400);
      if (decision !== 'approved' && decision !== 'rejected') return J({ error: "decision must be 'approved' or 'rejected'" }, 400);
      // fn_approval_decide is the guard: it refuses an actor who is not an active member of the
      // owning organization, and refuses a step whose policy names a different role.
      const { data, error } = await admin.rpc('fn_approval_decide', {
        p_request: rid, p_actor: cust.id, p_decision: decision,
        p_note: body.note ? String(body.note).slice(0, 2000) : null,
      });
      if (error) return J({ error: error.message }, 403);
      return J({ ...(data as Record<string, unknown>) });
    }

    if (action === 'orders') {
      const { data, error } = await admin.rpc('fn_customer_orders', { p_customer: cust.id });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, orders: data || [] });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
});
