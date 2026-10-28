// scripts/e2e/resend_sink.mjs — the REAL sign-up e-mail code, received and read, without a real person's inbox
// (28 Oct 2026, owner: sales_engineer). Founder, before invitations resumed: "you have to verify 100% the registration
// is smooth through a browser" — so the e-mail OTP is no longer seeded for this leg; the form sends it, login_otp
// mints it, Resend delivers it, and the harness reads the delivered message and types the code.
//
// WHERE THE CODE IS DELIVERED. `delivered+<label>@resend.dev` is Resend's own test sink: Resend accepts the message,
// records it as delivered and drops it, so no person and no third-party inbox ever receives it, and no bounce lands
// on our sending reputation. The address carries the run tag, so it is ours and only ours.
//
// HOW IT IS READ. The cloud container may not reach api.resend.com (proxy 403, measured 28 Oct 2026), so the read
// goes from the database through pg_net with the key already stored in app_secrets: GET /emails (the list), then
// GET /emails/<id> (the html). The key never leaves the database and is never printed. Only the ONE message addressed
// to this run's sink is ever parsed; nothing else in the list is returned to the caller.
//
// CLEAN-UP. fixtures.teardown keys on `qd-<tag>-...@example.*`, which this address is not, so cleanSink removes
// what an account created through the real form leaves: the auth user, its e-mail verifications and every
// notification addressed to it. leftoversSink counts them afterwards; a clean run reads 0.
import { read, write, BASE } from './fixtures.mjs';
import { keys } from '../lib/demo_factory.mjs';

const sq = (s) => `'${String(s).replace(/'/g, "''")}'`;
export const sinkAddress = (tag, n) => `delivered+qd-${tag}-sup${n}@resend.dev`;
export const isSink = (a) => /^delivered\+qd-[a-z0-9]{4,16}-[a-z0-9]+@resend\.dev$/i.test(String(a || ''));

async function resendGet(path) {
  const [{ id }] = await write(`select net.http_get(url := ${sq('https://api.resend.com' + path)},
     headers := jsonb_build_object('Authorization', 'Bearer ' || (select value from public.app_secrets where key = 'resend_api_key'))) id`, 'resend read');
  for (let i = 0; i < 40; i++) {
    await new Promise((r) => setTimeout(r, 750));
    const r = await read(`select status_code, content from net._http_response where id = ${Number(id)}`);
    if (r.length && r[0].status_code) {
      if (r[0].status_code !== 200) throw new Error(`Resend ${path} answered HTTP ${r[0].status_code}`);
      return JSON.parse(r[0].content);
    }
  }
  throw new Error(`Resend ${path}: no answer through pg_net in 30 s`);
}

/** The six-digit code in the newest message to `address` sent at or after `sinceMs`, with its delivery facts. */
export async function readCode(address, sinceMs, { timeoutMs = 90_000 } = {}) {
  if (!isSink(address)) throw new Error('readCode reads only a run sink address, never anyone else\'s mail');
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const list = await resendGet('/emails?limit=50');
    const mine = (list.data || []).filter((e) => (e.to || []).map((x) => String(x).toLowerCase()).includes(address.toLowerCase())
      && Date.parse(e.created_at) >= sinceMs - 5000).sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
    if (mine.length) {
      const full = await resendGet('/emails/' + encodeURIComponent(mine[0].id));
      const text = String(full.html || full.text || '').replace(/<[^>]+>/g, ' ');
      const code = (text.match(/\b(\d{6})\b/) || [])[1] || null;
      return { code, subject: full.subject, from: full.from, last_event: full.last_event || mine[0].last_event,
        queued_ms: Date.parse(mine[0].created_at) - sinceMs, read_ms: Date.now() - sinceMs };
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  return { code: null, read_ms: Date.now() - sinceMs };
}

/** Remove what an account made through the real form leaves behind. Only ever a sink address. */
export async function cleanSink(address) {
  if (!isSink(address)) throw new Error('cleanSink removes only a run sink account');
  const { SERVICE } = await keys();
  const users = await read(`select id from auth.users where lower(email) = lower(${sq(address)})`);
  for (const u of users) await fetch(`${BASE}/auth/v1/admin/users/${u.id}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
  await write(`delete from public.email_verifications where lower(email) = lower(${sq(address)});
               delete from public.notifications where lower(to_email) = lower(${sq(address)})`, 'sink cleanup');
  return leftoversSink(address);
}

export async function leftoversSink(address) {
  return (await read(`select
    (select count(*) from auth.users where lower(email) = lower(${sq(address)}))::int auth_users,
    (select count(*) from public.email_verifications where lower(email) = lower(${sq(address)}))::int email_verifications,
    (select count(*) from public.notifications where lower(to_email) = lower(${sq(address)}))::int notifications,
    (select count(*) from public.leads where lower(claimed_by) = lower(${sq(address)}))::int leads`))[0];
}
