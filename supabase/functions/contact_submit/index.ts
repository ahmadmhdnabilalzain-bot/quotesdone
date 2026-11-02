// contact_submit - public contact form handler. Stores the message; a trigger hands it to customer_support. Honeypot spam guard.
// kind='complaint' also opens a complaint ticket (fn_complaint_open) and returns its number and due dates for /complaints/status.
// config.toml sets verify_jwt = true for this function; the public form sends the anon key as Bearer, which passes.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { contactMessageError } from '../_shared/contact_limits.ts';
import { answerHold } from '../_shared/contact_answer_gate.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
// RATE LIMIT (15 Sep 2026). The form had only a honeypot, which a script that leaves the hidden field
// empty walks straight past, and every accepted post writes a row and queues a mail to the inbox. It now
// uses the estate's rl_check, as complaint_status does: 10 posts an hour per IP and 5 per address.
const IP_LIMIT = 10, EMAIL_LIMIT = 5, WINDOW_S = 3600;
async function rl(key: string, limit: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: WINDOW_S }); if (error) return true; return data !== false; }
  catch (_e) { return true; } // the limiter being down must not lose a customer's message
}
// The limiter for AUTOMATIC ANSWERS fails CLOSED: if it cannot count, the message is held for the seat, never answered.
async function allow(key: string, limit: number, seconds: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); return !error && data !== false; }
  catch (_e) { return false; }
}
Deno.serve(observe('contact_submit', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const b = await req.json().catch(()=>({} as any));
    // honeypot: hidden 'company' field must stay empty
    if (String(b.company||'').trim() !== '') return J({ ok: true });
    const name = String(b.name||'').trim().slice(0,120);
    const email = String(b.email||'').trim().slice(0,160);
    const phone = String(b.phone||'').trim().slice(0,40);
    const message = String(b.message||'').trim();
    const bad = contactMessageError(message); // too short or over the cap: rejected, never silently truncated
    if (bad) return J(bad, 400);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return J({ error: 'Please enter a valid email so we can reply.' }, 400);
    const ip = String(req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
    if (!(await rl('contact_submit_ip:' + ip, IP_LIMIT)) || !(await rl('contact_submit_email:' + email.toLowerCase(), EMAIL_LIMIT))) {
      return J({ error: 'Too many messages. Please try again in an hour, or email us directly.' }, 429);
    }
    const ua = String(req.headers.get('user-agent')||'').slice(0,300);
    const isComplaint = String(b.kind || '') === 'complaint';
    // Whether we may ANSWER this stranger by mail; the message is stored either way (source 'held:<reason>' -> z55 holds it).
    const hold = isComplaint ? null : await answerHold(email, ip, allow).catch(() => 'gate_error');
    const { data: row, error } = await admin.from('contact_messages').insert({ name, email, phone, message, user_agent: ua, ...(isComplaint ? { source: 'complaint' } : hold ? { source: 'held:' + hold } : {}) }).select('id').maybeSingle();
    if (error) return J({ error: 'Could not send. Please try again.' }, 500);
    // A complaint gets a ticket number and the two policy clocks (2 and 10 working days).
    type Ticket = { ticket?: string; acknowledge_due?: string; respond_due?: string };
    let ticket: Ticket | null = null;
    if (isComplaint) {
      const { data: t, error: te } = await admin.rpc('fn_complaint_open', { p_email: email, p_name: name, p_message: message, p_contact_message_id: row?.id ?? null });
      if (te || !t) {
        try { await admin.from('agent_runs').insert({ agent:'contact_submit', status:'error', counts:{ complaint_ticket_failed:1 }, note:'contact_submit stored a complaint (contact_messages #'+(row?.id||'')+') but fn_complaint_open failed: '+String(te?.message||'no row').slice(0,300)+'. customer_support must open the ticket by hand.', finished_at:new Date().toISOString() }); } catch(_e3){ /* */ }
      } else ticket = t as Ticket;
    }
    // NO NOTICE MAIL (ledger 1436/1447). The trigger z55 on contact_messages
    // (scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts.sql) hands a message to customer_support as an
    // inbound row, which email_triage answers; a complaint keeps its ticket and its two clocks.
    if (isComplaint) return J({ ok: true, ticket: ticket?.ticket ?? null, acknowledge_due: ticket?.acknowledge_due ?? null, respond_due: ticket?.respond_due ?? null, status_path: '/complaints/status' });
    return J({ ok: true });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
