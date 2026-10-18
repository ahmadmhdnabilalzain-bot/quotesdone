import { siteCors } from '../_shared/site_origins.ts';
// customer_intelligence — spec §11 (procurement forecast, savings by category, supplier
// performance figures), §13 (per-customer supplier relationship) and §20 (predictive intelligence).
//
// Auth: customer Supabase JWT -> customers row, the same model as project_api and customer_api.
// Every routine behind these actions takes the caller's own customer id and nothing else.
//
// WHAT IT ADDS. fn_finance_forecast() takes no arguments and forecasts the COMPANY's cash;
// public.supplier_score is one global row per lead with no customer_id at all. Neither could answer
// "what will I need next" or "how has this supplier treated ME". fn_customer_forecast,
// fn_customer_supplier_score and fn_customer_savings are per-customer and this is how they are
// reached.
//
// ON EMPTY: production holds zero customers, so every action here answers with basis='no_history'
// (or by_category=[]) and an `empty_reason` sentence. No action ever returns a zeroed series or a
// zero-valued projection — a chart drawn from twelve zeroes is a claim about the customer, not an
// absence of data about them, and the surface must render the sentence instead.
//
// REVEAL GATE: supplier identity and platform-wide scores stay behind the same paywall
// customer_api action=supplier_history enforces — a revealed transaction between this customer and
// that supplier. The customer's OWN relationship figures are theirs either way.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
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

// Suppliers this customer has paid to reveal. Identity and platform-wide figures are gated on it.
async function revealed(customerId: string): Promise<number[]> {
  const { data } = await admin.from('transactions').select('supplier_id').eq('customer_id', customerId);
  return [...new Set((data || []).map((t: Record<string, unknown>) => Number(t.supplier_id)).filter(Boolean))];
}

Deno.serve(siteCors(observe('customer_intelligence', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const cust = await customer(req);
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const action = String(body.action || '');

    // §11 next-year procurement forecast + §20 "you will likely need X within N days".
    if (action === 'forecast') {
      const horizon = Number(body.horizon_days || 365);
      const { data, error } = await admin.rpc('fn_customer_forecast', {
        p_customer: cust.id,
        p_horizon_days: Number.isFinite(horizon) && horizon > 0 && horizon <= 1095 ? Math.round(horizon) : 365,
      });
      if (error) return J({ error: error.message }, 500);
      const f = (data || {}) as Record<string, unknown>;
      return J({
        ok: true,
        forecast: f,
        // The two things a surface renders first, lifted so it need not know the whole shape.
        predictions: f.predictions ?? [],
        empty_reason: f.empty_reason ?? null,
      });
    }

    // §13 the relationship score for ONE supplier, from this customer's own history.
    if (action === 'supplier_relationship') {
      const supplier_id = Number(body.supplier_id || 0);
      if (!(supplier_id > 0)) return J({ error: 'supplier_id required' }, 400);
      const { data, error } = await admin.rpc('fn_customer_supplier_score', { p_customer: cust.id, p_supplier: supplier_id });
      if (error) return J({ error: error.message }, 500);
      const r = (data || {}) as Record<string, unknown>;
      if (r.error) return J({ error: r.error }, 404);
      const seen = await revealed(cust.id);
      if (!seen.includes(supplier_id)) {
        // Their own numbers, without the supplier's identity or the platform-wide verdict.
        delete r.supplier_name;
        delete r.platform_wide;
        r.locked = 'Reveal this supplier to see their name and platform-wide performance. The figures below are your own history with them.';
      }
      return J({
        ok: true,
        relationship: r,
        relationship_score: r.relationship_score ?? null,
        empty_reason: r.empty_reason ?? null,
      });
    }

    // §11 supplier performance graphs: reliability, price, quality, response — for the suppliers
    // this customer has actually revealed, never the whole 20,464-row table.
    if (action === 'supplier_performance') {
      const seen = await revealed(cust.id);
      if (!seen.length) {
        return J({
          ok: true, suppliers: [],
          empty_reason: 'You have not revealed any suppliers yet. Performance figures are shown for the suppliers you have worked with.',
        });
      }
      const { data: perf, error } = await admin.from('supplier_score')
        .select('lead_id,reliability,quality_rating,price_index,response_rate,avg_response_hours,quotes_submitted,quotes_won,computed_at')
        .in('lead_id', seen);
      if (error) return J({ error: error.message }, 500);
      const { data: names } = await admin.from('leads').select('id,company_name').in('id', seen);
      const nameOf = new Map((names || []).map((l: Record<string, unknown>) => [Number(l.id), l.company_name]));
      return J({
        ok: true,
        suppliers: (perf || []).map((s: Record<string, unknown>) => ({ ...s, company_name: nameOf.get(Number(s.lead_id)) ?? null })),
        empty_reason: (perf || []).length ? null
          : 'No performance figures have been computed for your suppliers yet.',
      });
    }

    // §11 cost optimisation: potential savings, broken down by category, plus the totals.
    if (action === 'savings') {
      const { data, error } = await admin.rpc('fn_customer_savings', { p_customer: cust.id });
      if (error) return J({ error: error.message }, 500);
      const s = (data || {}) as Record<string, unknown>;
      return J({
        ok: true,
        savings: s,
        by_category: s.by_category ?? [],
        total_spread_saving_aed: s.total_spread_saving_aed ?? null,
        total_benchmark_saving_aed: s.total_benchmark_saving_aed ?? null,
        empty_reason: s.empty_reason ?? null,
      });
    }

    return J({ error: 'unknown action', action }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
})));
