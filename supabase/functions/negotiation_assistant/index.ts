// negotiation_assistant — spec §15, the AI negotiation assistant.
//
// Auth: customer Supabase JWT -> customers row, the same model as project_api and customer_api.
// Every action is scoped to the caller's own rows; fn_negotiation_guidance re-checks quote
// ownership in SQL, so a quote id belonging to someone else is refused by the database, not only
// by this handler.
//
// WHAT IT ADDS THAT WAS NOT REACHABLE BEFORE. public.category_price_stats has computed the market
// median, p25, p75 and mean per category all along and had ZERO customer-authed readers;
// public.supplier_negotiation_policy existed with zero rows. This is the first endpoint through
// which a customer can see their quote against the market, the house policy's recommended action,
// and a message drafted to send.
//
// ON EMPTY: production holds zero quotes, so category_price_stats is empty and every guidance call
// answers band=insufficient_data with NO target price and NO discount figure. That is deliberate.
// The response always carries `empty_reason` when a figure is withheld, and the surface must render
// that sentence rather than a zero.
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

Deno.serve(observe('negotiation_assistant', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const cust = await customer(req);
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const action = String(body.action || '');

    // Guidance on ONE quote the caller owns: market position, recommended action, target price and
    // a ready-to-send draft.
    if (action === 'guidance') {
      const quote_id = String(body.quote_id || '');
      if (!quote_id) return J({ error: 'quote_id required' }, 400);
      const { data, error } = await admin.rpc('fn_negotiation_guidance', { p_customer: cust.id, p_quote: quote_id });
      if (error) return J({ error: error.message }, 500);
      const g = (data || {}) as Record<string, unknown>;
      if (g.error === 'not_your_quote') return J({ error: 'not_your_quote' }, 403);
      return J({
        ok: true,
        negotiation: g,
        // Lifted out of the payload so a surface can render the three headline facts without
        // knowing the shape of the rest.
        recommended_action: g.recommended_action ?? null,
        target_price: g.target_price ?? null,
        suggested_message: g.suggested_message ?? null,
        suggested_message_ar: g.suggested_message_ar ?? null,
        empty_reason: g.empty_reason ?? null,
      });
    }

    // The market position of an amount the customer is CONSIDERING, before any quote exists.
    if (action === 'market') {
      const category = String(body.category || '');
      const amount = Number(body.amount || 0);
      if (!category) return J({ error: 'category required' }, 400);
      if (!(amount > 0)) return J({ error: 'amount required' }, 400);
      const { data: confidence, error } = await admin.rpc('fn_price_confidence', { p_category: category, p_amount: amount });
      if (error) return J({ error: error.message }, 500);
      const { data: stats } = await admin.from('category_price_stats').select('*').eq('category', category).maybeSingle();
      return J({
        ok: true, category, amount,
        market: confidence ?? null,
        category_price_stats: stats ?? null,
        empty_reason: stats ? null
          : 'No quotes have been recorded in this category yet, so there is no market average to compare against.',
      });
    }

    // The house policy itself, so the customer can see the rule the recommendation came from.
    if (action === 'policy') {
      const { data } = await admin.from('supplier_negotiation_policy')
        .select('scope,supplier_id,policy,approved_by,approved_at,updated_at').eq('scope', 'default').maybeSingle();
      return J({
        ok: true, policy: data ?? null,
        empty_reason: data ? null : 'No default negotiation policy is configured.',
      });
    }

    return J({ error: 'unknown action', action }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
}));
