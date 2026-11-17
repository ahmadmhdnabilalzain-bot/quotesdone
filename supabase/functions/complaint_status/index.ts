import { siteCors } from '../_shared/site_origins.ts';
// complaint_status - public complaint ticket lookup behind /complaints/status. verify_jwt=false.
// POST { ticket, email } -> fn_complaint_lookup (service role). A wrong email and a missing ticket
// get the SAME answer, so the endpoint never confirms a ticket exists. Rate limited through the
// estate's rl_check: 10 lookups per 10 minutes per IP and per ticket number.
// Tickets live in public.complaint_tickets (scripts/sql/complaints_get_a_ticket_number_and_a_status_the_customer_can_watch.sql).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { rateGate } from '../_shared/rate_gate.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const LIMIT = 10, WINDOW_S = 600;
const TICKET_RE = /^QD-C-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
// FAILS CLOSED (17 Nov 2026, security audit finding 5). It used to answer "allowed" when rl_check errored, so a
// database fault lifted the cap on guessing a ticket's e-mail. A limiter that cannot answer now gets a 503 "try again".
const rl = (key: string) => rateGate((fn, args) => admin.rpc(fn, args), key, LIMIT, WINDOW_S);
Deno.serve(siteCors(observe('complaint_status', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return J({ ok: false, error: 'method_not_allowed' }, 405);
  try {
    const b = await req.json().catch(() => ({} as any));
    const ticket = String(b.ticket || '').trim().toUpperCase().slice(0, 20);
    const email = String(b.email || '').trim().toLowerCase().slice(0, 160);
    if (!TICKET_RE.test(ticket) || !EMAIL_RE.test(email)) return J({ ok: false, error: 'invalid_input' }, 400);
    const ip = String(req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
    const gate = await rl('complaint_status_ip:' + ip);
    const gate2 = gate === 'ok' ? await rl('complaint_status_ticket:' + ticket) : gate;
    if (gate2 === 'down') return J({ ok: false, error: 'unavailable' }, 503);
    if (gate2 === 'limited') return J({ ok: false, error: 'rate_limited' }, 429);
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
})));
