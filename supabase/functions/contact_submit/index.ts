// contact_submit - public contact form handler. Stores the message and queues a notify to the inbox (app_secrets.admin_emails) in the outbox, which customer_support sends. Honeypot spam guard.
// kind='complaint' also opens a complaint ticket (fn_complaint_open) and returns its number and due dates for /complaints/status.
// config.toml sets verify_jwt = true for this function; the public form sends the anon key as Bearer, which passes.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { requestDelivery } from '../_shared/deliver.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function esc(s: string){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
Deno.serve(observe('contact_submit', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const b = await req.json().catch(()=>({} as any));
    // honeypot: hidden 'company' field must stay empty
    if (String(b.company||'').trim() !== '') return J({ ok: true });
    const name = String(b.name||'').trim().slice(0,120);
    const email = String(b.email||'').trim().slice(0,160);
    const phone = String(b.phone||'').trim().slice(0,40);
    const message = String(b.message||'').trim().slice(0,4000);
    if (message.length < 4) return J({ error: 'Please write a short message.' }, 400);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return J({ error: 'Please enter a valid email so we can reply.' }, 400);
    const ua = String(req.headers.get('user-agent')||'').slice(0,300);
    const isComplaint = String(b.kind || '') === 'complaint';
    const { data: row, error } = await admin.from('contact_messages').insert({ name, email, phone, message, user_agent: ua, ...(isComplaint ? { source: 'complaint' } : {}) }).select('id').maybeSingle();
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
    // THE NOTIFY GOES THROUGH THE OUTBOX, SENT BY customer_support (ruling of 14 Sep 2026: "the only
    // agent who uses the whatsapp and email is the customer support agent."). This handler used to build
    // its own provider call, the one email path outside notifications. It now queues a delivery request
    // like every other seat: send_outbox dispatches it as customer_support, applies email_suppressions
    // (so the 27 Jul suppression bypass is closed by the dispatcher rather than restated here), and
    // the a10 mail-policy trigger on notifications governs it by kind 'contact_message'. The contact_messages
    // row is stored either way, so nothing a customer wrote is lost.
    try {
      const to = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
      await requestDelivery(admin, {
        type: 'contact_message', kind: 'contact_message', to_email: to, to_role: 'admin', channel: 'email', status: 'queued',
        requested_by: 'customer_support',
        subject: (ticket?.ticket ? ('Complaint '+ticket.ticket+' - ') : '')+'New contact message'+(name?(' from '+name):''),
        body: 'New contact-form message\n\nName: '+(name||'—')+'\nEmail: '+(email||'—')+'\nPhone: '+(phone||'—')+'\n\n'+message+'\n\nRef #'+(row?.id||''),
        html: `<p><b>New contact-form message</b></p><p><b>Name:</b> ${esc(name)||'—'}<br><b>Email:</b> ${esc(email)||'—'}<br><b>Phone:</b> ${esc(phone)||'—'}</p><p style="white-space:pre-wrap">${esc(message)}</p><p style="color:#888;font-size:12px">Ref #${row?.id||''}</p>`,
      });
    } catch(_e){ /* the row is stored regardless */ }
    if (isComplaint) return J({ ok: true, ticket: ticket?.ticket ?? null, acknowledge_due: ticket?.acknowledge_due ?? null, respond_due: ticket?.respond_due ?? null, status_path: '/complaints/status' });
    return J({ ok: true });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
