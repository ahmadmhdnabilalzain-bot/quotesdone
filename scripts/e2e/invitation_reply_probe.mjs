// scripts/e2e/invitation_reply_probe.mjs — an invited supplier says "yes", and gets an answer that says how to register
// (28 Oct 2026, owner: sales_engineer, ledger 1375). Production, reaching nobody.
//
//   node scripts/e2e/invitation_reply_probe.mjs            # the Microsoft 365 lane (default): what real replies take
//   node scripts/e2e/invitation_reply_probe.mjs --lane=row  # an inbound_messages row handed straight to email_triage
//
// WHY. Measured 27-28 Oct: every reply to supplier@ was "Not answered automatically: internal" (fixed in #1699), and the
// answer's facts called an unregistered lead "A REGISTERED SUPPLIER" (also #1699). This replays the reply and asserts:
//   m365  resend_inbound (the same Svix-signed hand-off _shared/m365_reply_inbox.ts makes, id 'm365:...') stores it with
//         sender_authenticated=true from Microsoft's verdict, wakes email_triage itself, and the answer is queued;
//   both  the answer carries the lead's own https://quotesdone.com/portal?t=<claim_token>, and never "registered".
//
// WHO IT CAN REACH. The lead is `ZZ DEMO …`; its address, and so the answer's only recipient, is
// delivered+qd-<tag>-sup0@resend.dev, Resend's own sink (accepted, recorded delivered, dropped). Secrets are read from
// app_secrets and never printed.
//
// CLEAN-UP, counted. The probe made rows in leads, inbound_messages, notifications, agent_actions, and, through the
// support wiring, support_customer_profile and support_case (the first run of this probe missed those two: found by a
// scan of every e-mail column, 28 Oct). All are deleted and every e-mail-like column is scanned for the address after.
import crypto from 'node:crypto';
import { read, write } from './fixtures.mjs';

process.env.QD_FIXTURES = '1';
const LANE = (process.argv.find((a) => a.startsWith('--lane=')) || '--lane=m365').split('=')[1];
const FN = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1';
const tag = 'rp' + Date.now().toString(36).slice(-6);
const addr = `delivered+qd-${tag}-sup0@resend.dev`;
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const results = [];
const step = (name, ok, detail = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`); };
let lead = null;
try {
  lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
    values ('ZZ DEMO Reply Probe ${tag}', ${q(addr)}, 'Dubai', 'directory', 'sent', now(), 'en', array['qd_demo','qd_run:${tag}'])
    returning id, claim_token::text t`, 'probe lead'))[0];
  const sec = Object.fromEntries((await read(`select key, value from public.app_secrets
    where key in ('resend_inbound_token','resend_inbound_signing_secret','cred_fn_resend_inbound')`)).map((r) => [r.key, r.value]));
  const t0 = Date.now();
  let msgId = null;
  const text = 'Yes please, we would like to receive requests. We supply aluminium windows and glass partitions.';
  if (LANE === 'm365') {
    const gid = 'AAMkQDPROBE' + tag;
    const body = JSON.stringify({ type: 'email.received', data: {
      email_id: 'm365:' + gid, message_id: `<qd-${tag}@resend.dev>`, from: addr, to: 'supplier@quotesdone.com',
      subject: 'Re: Quote requests in the UAE', text: text + '\r\n\r\nOn Tue, QuotesDone wrote:\r\n> Would your company like to receive requests?',
      headers: { 'message-id': `<qd-${tag}@resend.dev>`,
        'authentication-results': 'spf=pass (sender IP is 54.240.0.1) smtp.mailfrom=resend.dev; dkim=pass (signature was verified) header.d=resend.dev;dmarc=pass action=none header.from=resend.dev;compauth=pass reason=100' },
      attachments: [], created_at: new Date().toISOString() } });
    const id = 'msg_m365_' + gid.slice(-30), ts = String(Math.floor(Date.now() / 1000));
    const sig = crypto.createHmac('sha256', Buffer.from(String(sec.resend_inbound_signing_secret).replace(/^whsec_/, ''), 'base64')).update(`${id}.${ts}.${body}`).digest('base64');
    const r = await fetch(`${FN}/resend_inbound?s=${encodeURIComponent(sec.resend_inbound_token)}`, { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': 'v1,' + sig }, body });
    const j = await r.json().catch(() => ({}));
    step('resend_inbound takes the M365 hand-off and matches the lead', r.status === 200 && Number(j.matched_lead) === Number(lead.id), `HTTP ${r.status} ${JSON.stringify(j).slice(0, 120)}`);
    const row = (await read(`select id, raw->>'sender_authenticated' auth from public.inbound_messages where provider_email_id = ${q('m365:' + gid)}`))[0];
    msgId = row?.id ?? null;
    step('stored with sender_authenticated from Microsoft\'s verdict', row?.auth === 'true', JSON.stringify(row || null));
  } else {
    msgId = (await write(`insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, needs_review, matched_existing, raw)
      values (${lead.id}, ${q(addr)}, 'supplier@quotesdone.com', 'Re: Quote requests in the UAE', ${q(text)}, true, true,
      jsonb_build_object('sender_authenticated', true, 'message_id', ${q('<qd-' + tag + '@resend.dev>')})) returning id`, 'probe inbound'))[0].id;
    const r = await fetch(`${FN}/email_triage`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: sec.cred_fn_resend_inbound, message_id: msgId }) });
    step('email_triage answers the row', r.status === 200, `HTTP ${r.status}`);
  }
  let out = []; const until = Date.now() + 300000;
  while (Date.now() < until) { out = await read(`select id, status, body from public.notifications where lower(to_email) = lower(${q(addr)}) and type = 'inbound_reply'`); if (out.length) break; await new Promise((s) => setTimeout(s, 10000)); }
  const reply = String(out[0]?.body || '');
  step('an answer is queued for the supplier', out.length === 1, `${Date.now() - t0} ms after the reply arrived`);
  step('the answer carries the company\'s own registration link', reply.includes(`https://quotesdone.com/portal?t=${lead.t}`));
  step('the answer never calls the company registered', !/you are (already )?registered|registered supplier/i.test(reply));
  if (reply) console.log('\n' + reply + '\n');
} finally {
  if (lead) {
    await write(`delete from public.support_case where customer_profile_id in (select id from public.support_customer_profile where lower(email) = lower(${q(addr)}));
      delete from public.support_customer_profile where lower(email) = lower(${q(addr)});
      delete from public.agent_actions where target_table = 'inbound_messages' and target_id in (select id::text from public.inbound_messages where lower(from_email) = lower(${q(addr)}));
      delete from public.agent_actions where detail->>'lead_id' = '${lead.id}' or (target_table = 'leads' and target_id = '${lead.id}');
      delete from public.notifications where lower(to_email) = lower(${q(addr)});
      delete from public.inbound_messages where lower(from_email) = lower(${q(addr)});
      delete from public.leads where id = ${lead.id}`, 'probe clean-up');
    const cols = await read(`select c.table_name t, c.column_name c from information_schema.columns c join information_schema.tables x
      on x.table_schema = c.table_schema and x.table_name = c.table_name and x.table_type = 'BASE TABLE'
      where c.table_schema = 'public' and c.data_type in ('text','character varying') and (c.column_name ilike '%email%' or c.column_name = 'claimed_by')`);
    const left = [];
    for (const { t, c } of cols) { const n = (await read(`select count(*)::int n from public."${t}" where lower("${c}") = lower(${q(addr)})`).catch(() => [{ n: 0 }]))[0].n; if (n) left.push(`${t}.${c}=${n}`); }
    step('nothing the probe made is left (every e-mail column scanned)', left.length === 0, left.join(' '));
  }
}
process.exitCode = results.every((r) => r.ok) ? 0 : 1;
