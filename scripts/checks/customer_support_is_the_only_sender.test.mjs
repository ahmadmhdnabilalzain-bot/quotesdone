// CUSTOMER SUPPORT IS THE ONLY SENDER ON EMAIL AND WHATSAPP.
//
// Founder, 14 Sep 2026, verbatim: "the only agent who uses the whatsapp and email is the customer
// support agent. so he should be always up to date with that is going on."
//
// Statically (runs in CI without a token):
//   * only the documented functions reach a provider's SEND endpoint (Resend /emails, Twilio
//     Messages.json POST): the two outbox dispatchers, customer_support's own WhatsApp runtime, and
//     the platform OTP service. Every other seat queues a delivery request in public.notifications.
//   * no edge function writes an outbox row whose sender is anything but customer_support.
//   * the three places support composes or answers read fn_contact_timeline first.
// Against production (skipped without a management token):
//   * the CHECK constraint refuses a sender other than customer_support (aborted transaction)
//   * every row names the seat that asked, and customer_support sends it
//   * every channel slug is owned by customer_support
//   * fn_contact_timeline assembles a delivery request into the contact's timeline with its seat
// Scope of the static scan: supabase/functions only. Routines are covered by the constraint, which
// no writer can get past, and by the production assertions below.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FNS = join(REPO, 'supabase', 'functions');

export const PROVIDER_SENDERS = {
  send_outbox: 'the email dispatcher (customer_support)',
  send_whatsapp: 'the WhatsApp dispatcher (customer_support)',
  wa_inbound: "customer_support's own runtime, replying inside the 24-hour window",
  login_otp: 'platform OTP service (sign-in code)',
  kyc: 'platform OTP service (email confirmation code)',
  send_sms: 'platform OTP service (SMS code)',
};
export const CHANNEL_SLUGS = ['send_outbox', 'send_whatsapp', 'email_cron', 'wa_inbound', 'resend_inbound', 'inbound_email',
  'email_triage', 'site_assistant', 'wa_template_setup', 'wa_templates_watch', 'resend_webhook', 'unsubscribe'];

const walk = (d) => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(f) && !/\.test\./.test(f) ? [p] : [];
});
const slugs = readdirSync(FNS).filter((s) => !s.startsWith('_') && statSync(join(FNS, s)).isDirectory());
const src = (s) => walk(join(FNS, s)).map((f) => readFileSync(f, 'utf8')).join('\n');

// The send endpoints, spelled so that a read (/emails/inbound, /domains, Messages.json?To=) never matches.
const RESEND_SEND = /api\.resend\.com\/emails['"`]/;
const TWILIO_SEND = /Messages\.json['"`]/;

test('only the documented functions reach a provider send endpoint', () => {
  const found = slugs.filter((s) => { const t = src(s); return RESEND_SEND.test(t) || TWILIO_SEND.test(t); });
  assert.ok(found.includes('send_outbox') && found.includes('send_whatsapp'), 'the scan found neither dispatcher: it is not looking at anything');
  assert.deepEqual(found.filter((s) => !PROVIDER_SENDERS[s]), [], 'these functions send without the outbox');
});

test('no edge function writes an outbox row with a sender other than customer_support', () => {
  const bad = [];
  for (const s of slugs) for (const m of src(s).matchAll(/\bsender:\s*'([a-z_]+)'/g)) {
    // messages.sender (portal chat: 'customer' / 'supplier') is a different table; only outbox inserts count.
    const before = src(s).slice(Math.max(0, m.index - 600), m.index);
    if (/from\('notifications'\)\.insert\([^)]*$/.test(before) && m[1] !== 'customer_support') bad.push(`${s}: sender='${m[1]}'`);
  }
  assert.deepEqual(bad, []);
});

test('every place support composes or answers reads the contact timeline first', () => {
  for (const s of ['wa_inbound', 'site_assistant', 'email_triage']) assert.ok(/rpc\('fn_contact_timeline'/.test(src(s)), `${s} does not load fn_contact_timeline`);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: the guard refuses another seat, every row names its requester, the timeline assembles', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  let msg = '';
  try {
    await sql(`do $p$
      declare v_blocked boolean := false; v jsonb; r text; s text;
      begin
        begin
          insert into public.notifications (type, to_email, to_role, channel, status, subject, body, sender)
          values ('new_quote', 'zz-demo-check@example.invalid', 'customer', 'email', 'held', 'ZZ DEMO', 'ZZ DEMO', 'sales_engineer');
        exception when check_violation then v_blocked := true; end;
        insert into public.notifications (type, to_email, to_role, channel, status, subject, body)
        values ('refund_issued', 'zz-demo-check@example.invalid', 'customer', 'email', 'held', 'ZZ DEMO', 'ZZ DEMO')
        returning requested_by, sender into r, s;
        v := public.fn_contact_timeline('zz-demo-check@example.invalid', 5);
        raise exception 'CHK<<%>>', jsonb_build_object('blocked', v_blocked, 'requested_by', r, 'sender', s, 'timeline', v)::text;
      end $p$;`);
  } catch (e) { msg = String(e?.message || e); }
  const m = msg.match(/CHK<<(.*)>>/s);
  assert.ok(m, 'probe did not report: ' + msg.slice(0, 300));
  const got = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(got.blocked, true, 'an outbox row with sender=sales_engineer was accepted');
  assert.equal(got.requested_by, 'accountant');
  assert.equal(got.sender, 'customer_support');
  assert.equal(got.timeline.event_count, 1);
  assert.deepEqual(Object.keys(got.timeline.events[0]).sort(), ['at', 'channel', 'direction', 'kind', 'ref', 'seat', 'summary']);
  assert.equal(got.timeline.events[0].seat, 'accountant');

  const [row] = await sql(`select count(*) filter (where requested_by is null)::int unfilled,
                                  count(*) filter (where sender <> 'customer_support')::int other_sender
                             from public.notifications`);
  assert.deepEqual(row, { unfilled: 0, other_sender: 0 });

  const owners = await sql(`select function_slug, owner from public.function_owner where function_slug = any (array[${CHANNEL_SLUGS.map((s) => `'${s}'`).join(',')}])`);
  assert.deepEqual(owners.filter((o) => o.owner !== 'customer_support').map((o) => `${o.function_slug}=${o.owner}`), []);
  assert.equal(owners.length, CHANNEL_SLUGS.length, 'a channel slug has no function_owner row');
});
