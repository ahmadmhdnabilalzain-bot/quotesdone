// contact_submit - public contact form handler. Stores the message, emails the founder (best-effort). Honeypot spam guard. verify_jwt=false.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
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
    const { data: row, error } = await admin.from('contact_messages').insert({ name, email, phone, message, user_agent: ua }).select('id').maybeSingle();
    if (error) return J({ error: 'Could not send. Please try again.' }, 500);
    // best-effort email notify
    try {
      const key = await sec('resend_api_key');
      const to = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
      const from = (await sec('resend_from')) || 'QuotesDone <noreply@quotesdone.com>';
      // SUPPRESSION BYPASS 27 Jul 2026 ------------------------------------------------------------
      // This handler built its own Resend call and never consulted email_suppressions - send_outbox
      // was the only sender that did. The moment the admin notify inbox lands on that list (one
      // hard bounce from resend_webhook is enough) we would keep pushing every contact-form message
      // at a mailbox Resend has already told us rejects mail, damaging the sending domain for the
      // supplier and customer mail that shares it. Check the RECIPIENT first. The contact_messages
      // row is stored either way so nothing a customer wrote is lost, but the skipped notification
      // is written to agent_runs rather than disappearing into the best-effort catch below.
      const { data: supRow } = await admin.from('email_suppressions').select('email').eq('email', to.toLowerCase()).maybeSingle();
      if (supRow) {
        try { await admin.from('agent_runs').insert({ agent:'contact_submit', status:'error', counts:{ suppressed:1 }, note:'contact_submit did NOT email the new contact message: the admin notify address ('+to+') is in email_suppressions. The message is safe in contact_messages (ref #'+(row?.id||'')+') - read it there, then fix the mailbox and delete its email_suppressions row.', finished_at:new Date().toISOString() }); } catch(_e2){ /* */ }
      } else if (key) {
        await fetch('https://api.resend.com/emails', { method:'POST', headers:{ 'Authorization':'Bearer '+key, 'Content-Type':'application/json' }, body: JSON.stringify({
          from, to, reply_to: email || undefined,
          subject: 'New contact message'+(name?(' from '+name):''),
          html: `<p><b>New contact-form message</b></p><p><b>Name:</b> ${esc(name)||'—'}<br><b>Email:</b> ${esc(email)||'—'}<br><b>Phone:</b> ${esc(phone)||'—'}</p><p style="white-space:pre-wrap">${esc(message)}</p><p style="color:#888;font-size:12px">Ref #${row?.id||''}</p>`
        }) });
      }
    } catch(_e){ /* email is best-effort; the row is stored regardless */ }
    return J({ ok: true });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
