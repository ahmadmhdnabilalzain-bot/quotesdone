// Will the supplier invitation land in the inbox? (customer_support, 22 Sep 2026; founder instructions
// 633 and 635.)
//
//   node --no-warnings scripts/invitation_inbox_check.mjs
//       RENDER ONLY, sends nothing. Reads the LIVE invitation copy, From, Reply-To and supplier frame from
//       production, builds the exact Resend payload with send_outbox's own functions (render.ts,
//       arabic_frame.ts, supplier_mail.ts, payload.ts) and prints the headers plus every inbox rule.
//       Exit 1 if a rule fails.
//
//   node --no-warnings scripts/invitation_inbox_check.mjs --send-seed --to=test-abc123@srv1.mail-tester.com [--lang=ar]
//       Sends ONE invitation through the real path: a notifications row (type supplier_invite_seed,
//       to_role supplier, company "ZZ DEMO Supplier", a zero portal token) that the running send_outbox
//       picks up and hands to Resend with the campaign's From, Reply-To, headers and frame. It is not a
//       supplier_invite, so it never spends the day's cap and the campaign gates (invite_enabled,
//       supplier_outreach_golive) are untouched. REFUSES any address outside SEED_DOMAINS: nothing can
//       reach a real person through this flag.
//
// Token: %USERPROFILE%\.supabase\access-token or SUPABASE_ACCESS_TOKEN. No secret is printed.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';

const REF = 'htdblwldjkcgjvmqkbeh';
const PROJECT_URL = `https://${REF}.supabase.co`;
// Inbox-placement test services only. A subdomain of one of these is accepted (srv1.mail-tester.com).
export const SEED_DOMAINS = ['mail-tester.com', 'glockapps.com', 'mailgenius.com', 'dkimvalidator.com', 'appmaildev.com', 'learndmarc.com'];
export function seedAddressAllowed(addr) {
  const m = /^[a-z0-9._+-]+@([a-z0-9.-]+)$/i.exec(String(addr || '').trim());
  if (!m) return false;
  const host = m[1].toLowerCase();
  return SEED_DOMAINS.some((d) => host === d || host.endsWith('.' + d));
}

const arg = (k) => { const a = process.argv.find((x) => x.startsWith(`--${k}=`)); return a ? a.slice(k.length + 3) : undefined; };
const flag = (k) => process.argv.includes(`--${k}`);

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('No Supabase access token.');
}
async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}
const dq = (s) => { const tag = 'q' + Math.random().toString(36).slice(2, 8); return `$${tag}$${s}$${tag}$`; };

async function liveConfig() {
  const keys = ['email_from_supplier', 'email_reply_supplier', 'invite_subject', 'invite_subject_ar', 'invite_body', 'invite_body_ar',
    'public_site_url', 'email_signature_name', 'email_signature_name_ar', 'email_signature_title', 'email_logo_url',
    'unsubscribe_public_base', 'email_asset_public_base', 'invite_preheader'];
  const rows = await sql(`select key, value from app_secrets where key in (${keys.map((k) => `'${k}'`).join(',')})
                          union all select 'tpl:email_supplier', content from templates where name = 'email_supplier'`);
  return Object.fromEntries(rows.map((r) => [r.key, r.value]));
}

/** The invitation body exactly as fn_supplier_invite_candidates fills it, for a fixture company. */
function inviteBody(c, lang) {
  const site = c.public_site_url || 'https://quotesdone.com';
  const body = lang === 'ar' ? c.invite_body_ar : c.invite_body;
  return body.split('{{company}}').join('ZZ DEMO Supplier')
    .split('{{link}}').join(`${site}/${lang}/portal?t=00000000-0000-0000-0000-000000000000`);
}

async function render(c, lang) {
  globalThis.Deno ??= { env: { get: (k) => (k === 'SUPABASE_URL' ? PROJECT_URL : '') } };
  const base = new URL('../supabase/functions/send_outbox/', import.meta.url);
  const { tmpl } = await import(new URL('render.ts', base).href);
  const { arabicFrame } = await import(new URL('arabic_frame.ts', base).href);
  const { plainTextPart } = await import(new URL('supplier_mail.ts', base).href);
  const { resendPayload, inboxLint, ownDomain } = await import(new URL('payload.ts', base).href);
  const { UNSUBSCRIBE_MAILBOX } = await import(new URL('../_shared/unsubscribe_mailbox.ts', base).href);
  const ar = lang === 'ar';
  const reply = c.email_reply_supplier || 'supplier@quotesdone.com';
  const unsub = `${c.unsubscribe_public_base || PROJECT_URL + '/functions/v1/unsubscribe'}?e=zz-demo%40example.invalid&t=render-only`;
  const body = inviteBody(c, lang);
  const subject = ar ? c.invite_subject_ar : c.invite_subject;
  const html0 = tmpl({ body, logo: c.email_logo_url || '', name: ar ? (c.email_signature_name_ar || 'أحمد الزين') : (c.email_signature_name || 'Ahmad Alzain'),
    title: ar ? 'المؤسس' : (c.email_signature_title || 'Founder'), channelEmail: reply, unsub, wrapper: c['tpl:email_supplier'] || '', internal: false, subject, preheader: ar ? '' : (c.invite_preheader || '') });
  const mail = resendPayload({ from: c.email_from_supplier || 'QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply, subject,
    html: ownDomain(ar ? arabicFrame(html0) : html0, PROJECT_URL, c.email_asset_public_base || ''), text: plainTextPart({ body, unsub, ar, internal: false }), unsub, unsubMailto: UNSUBSCRIBE_MAILBOX });
  return { mail, lint: inboxLint(mail, ['quotesdone.com', `${REF}.supabase.co`]) };
}

async function main() {
  const c = await liveConfig();
  if (flag('send-seed')) {
    const to = arg('to'); const lang = arg('lang') === 'ar' ? 'ar' : 'en';
    if (!seedAddressAllowed(to)) { console.error(`REFUSED: ${to || '(no --to)'} is not on an inbox-test service (${SEED_DOMAINS.join(', ')}).`); process.exit(2); }
    const subject = lang === 'ar' ? c.invite_subject_ar : c.invite_subject;
    const [row] = await sql(`insert into notifications (type, to_email, to_role, subject, body, lang, status, requested_by)
      values ('supplier_invite_seed', ${dq(to.toLowerCase())}, 'supplier', ${dq(subject)}, ${dq(inviteBody(c, lang))}, '${lang}', 'queued', 'customer_support')
      returning id, status`);
    console.log(`queued notifications#${row.id} (${row.status}) to ${to}; waiting for send_outbox ...`);
    for (let i = 0; i < 40; i++) {
      await new Promise((r) => setTimeout(r, 30000));
      const [s] = await sql(`select status, provider_message_id is not null as accepted, left(coalesce(last_error,''),200) as err from notifications where id = ${Number(row.id)}`);
      if (s.status !== 'queued') { console.log(JSON.stringify(s)); process.exit(s.status === 'sent' ? 0 : 1); }
    }
    console.error('still queued after 20 minutes'); process.exit(1);
  }
  let bad = 0;
  for (const lang of ['en', 'ar']) {
    const { mail, lint } = await render(c, lang);
    console.log(`\n=== ${lang.toUpperCase()} invitation (rendered, not sent)`);
    console.log(`From:     ${mail.from}\nReply-To: ${mail.reply_to}\nSubject:  ${mail.subject}`);
    for (const [k, v] of Object.entries(mail.headers || {})) console.log(`${k}: ${v}`);
    console.log(`html ${mail.html.length} bytes, text ${mail.text.length} chars`);
    for (const l of lint) { console.log(`${l.ok ? 'PASS' : 'FAIL'}  ${l.rule}${l.detail && !l.ok ? '  -- ' + l.detail : ''}`); if (!l.ok) bad++; }
  }
  process.exit(bad ? 1 : 0);
}
if (import.meta.url === pathToFileURL(process.argv[1]).href) main().catch((e) => { console.error(e.message); process.exit(2); });
