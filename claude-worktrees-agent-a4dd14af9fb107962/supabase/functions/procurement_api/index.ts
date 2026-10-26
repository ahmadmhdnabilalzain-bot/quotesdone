// procurement_api — the customer-authed surface for the spec §22 Orders module. Auth: customer
// Supabase JWT -> email -> customers row (same model as customer_api and project_api).
//
// It serves the customer-scoped slice of po_orders through fn_customer_orders, a SECURITY DEFINER
// routine that filters by the caller's own customer id — the service role client below can see every
// row in the database, so nothing here may take an id from the request body and trust it.
//
// ACTIONS
//   orders     {}                                  -> { ok, orders[] } (this customer's orders only)
//
// 14 SEP 2026 — THE §12 PURCHASE APPROVAL ACTIONS ARE GONE. `approvals`, `trace` and `decide` served
// the customer portal's Approvals tab, which the founder removed: "i think its better just to remove
// the approvals tab. cause even if a company signed up, we don't wanna interfere in their approvals
// process and they are treated like normal individuals". The routines they called were dropped in
// scripts/sql/a_company_buys_like_an_individual_so_the_approval_chain_is_dropped.sql, so a caller
// still sending them now gets `unknown action` rather than a 500 from a routine that does not exist.
//
// HONEST EMPTY STATE: a customer with no orders gets orders: []. Nothing here implies a workflow that
// does not exist.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';

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

Deno.serve(observe('procurement_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const cust = await customer(req);
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const action = String(body.action || '');

    if (action === 'orders') {
      const { data, error } = await admin.rpc('fn_customer_orders', { p_customer: cust.id });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, orders: data || [] });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
}));
