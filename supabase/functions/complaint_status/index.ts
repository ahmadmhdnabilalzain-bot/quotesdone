// complaint_status - public complaint ticket lookup behind /complaints/status. verify_jwt=false.
// POST { ticket, email } -> fn_complaint_lookup (service role). A wrong email and a missing ticket
// get the SAME answer, so the endpoint never confirms a ticket exists. Rate limited through the
// estate's rl_check: 10 lookups per 10 minutes per IP and per ticket number.
// Tickets live in public.complaint_tickets (scripts/sql/complaints_get_a_ticket_number_and_a_status_the_customer_can_watch.sql).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const LIMIT = 10, WINDOW_S = 600;
const TICKET_RE = /^QD-C-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
async function rl(key: string): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: LIMIT, p_seconds: WINDOW_S }); if (error) return true; return data !== false; }
  catch (_e) { return true; } // limiter unavailable must not hide a customer's own ticket from them
}
Deno.serve(observe('complaint_status', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return J({ ok: false, error: 'method_not_allowed' }, 405);
  try {
    const b = await req.json().catch(() => ({} as any));
    const ticket = String(b.ticket || '').trim().toUpperCase().slice(0, 20);
    const email = String(b.email || '').trim().toLowerCase().slice(0, 160);
    if (!TICKET_RE.test(ticket) || !EMAIL_RE.test(email)) return J({ ok: false, error: 'invalid_input' }, 400);
    const ip = String(req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
    if (!(await rl('complaint_status_ip:' + ip)) || !(await rl('complaint_status_ticket:' + ticket))) {
      return J({ ok: false, error: 'rate_limited' }, 429);
    }
    const { data, error } = await admin.rpc('fn_complaint_lookup', { p_ticket_no: ticket, p_email: email });
    if (error) return J({ ok: false, error: 'unavailable' }, 500);
    if (!data) return J({ ok: false, error: 'not_found' }, 404);
    const d = data as Record<string, unknown>;
    return J({ ok: true, ticket: d.ticket, status: d.status, created_at: d.created_at,
      acknowledge_due: d.acknowledge_due, respond_due: d.respond_due,
      acknowledged_at: d.acknowledged_at, in_review_at: d.in_review_at,
      final_response_at: d.final_response_at, final_response: d.final_response,
      decision_ref: d.decision_ref ?? null, decided_by: d.decided_by ?? null,
      acknowledge_days_left: d.acknowledge_days_left, respond_days_left: d.respond_days_left });
  } catch (_e) { return J({ ok: false, error: 'unavailable' }, 500); }
}));
