// Will the supplier invitation land in the inbox? (customer_support, 22 Sep 2026; founder instructions
// 633 and 635.)
//
//   node --no-warnings scripts/invitation_inbox_check.mjs
//       RENDER ONLY, sends nothing. Reads the LIVE invitation copy, From, Reply-To and supplier frame from
//       production, builds the exact Resend payload with send_outbox's own functions (render.ts,
//       arabic_frame.ts, supplier_mail.ts, payload.ts) and prints the headers plus every inbox rule.
//       Exit 1 if a rule fails.
//
//   node --no-warnings scripts/invitation_inbox_check.mjs --send-seed --to=test-abc123@srv1.mail-tester.com
//       Sends ONE invitation through the real path: a notifications row (type supplier_invite_seed,
//       to_role supplier, company "ZZ DEMO Supplier", a zero portal token) that the running send_outbox
//       picks up and hands to Resend with the campaign's From, Reply-To, headers and frame. It is not a
//       supplier_invite, so it never spends the day's cap and the campaign gates (invite_enabled,
//       supplier_outreach_golive) are untouched. REFUSES any address outside SEED_DOMAINS: nothing can
//       reach a real person through this flag.
//       --subject-file=<path> / --body-file=<path> send a CANDIDATE subject/body (same {{company}}/{{link}}
//       placeholders) instead of the live copy; --role=customer routes it through the info@ identity and
//       customer frame instead (a diagnostic to split sender identity from content), so a copy fix is placement-tested before app_secrets changes.
//
// ENGLISH ONLY (24 Sep 2026, marketing, ledger 993 item 4 "invitations always in English"). The render and the
// seed are English; --lang=ar is refused. The copy rules (one closing question after the link, never the word
// AI, English only) come from supabase/functions/send_outbox/invitation_copy.ts, and the render applies
// withReplyQuestion exactly as send_outbox does. A separate line says whether the STORED body already ends with
// the question, i.e. whether the_supplier_invitation_ends_with_one_question_and_is_always_english.sql is applied.
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
// The founder's OWN inboxes, exact match only (marketing, ledger 993, 24 Sep 2026: placement is read in
// his Gmail and his Outlook). Never a domain: a colleague at quotesdone.com is still a real person.
export const FOUNDER_INBOXES = ['ahmadmhdnabilalzain@gmail.com', 'management@quotesdone.com', 'management@doratajewelries.com'];
export function seedAddressAllowed(addr) {
  const m = /^[a-z0-9._+-]+@([a-z0-9.-]+)$/i.exec(String(addr || '').trim());
  if (!m) return false;
  if (FOUNDER_INBOXES.includes(String(addr).trim().toLowerCase())) return true;
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
  const keys = ['email_from_supplier', 'email_reply_supplier', 'invite_subject', 'invite_body',
    'public_site_url', 'email_signature_name', 'email_signature_title', 'email_logo_url',
    'unsubscribe_public_base', 'email_asset_public_base', 'invite_preheader'];
  const rows = await sql(`select key, value from app_secrets where key in (${keys.map((k) => `'${k}'`).join(',')})
                          union all select 'tpl:email_supplier', content from templates where name = 'email_supplier'`);
  return Object.fromEntries(rows.map((r) => [r.key, r.value]));
}

/** The invitation body exactly as fn_supplier_invite_candidates fills it (English only), for a fixture company. */
function inviteBody(c, override) {
  const site = c.public_site_url || 'https://quotesdone.com';
  const body = override ?? c.invite_body;
  return body.split('{{company}}').join('ZZ DEMO Supplier')
    .split('{{link}}').join(`${site}/en/portal?t=00000000-0000-0000-0000-000000000000`);
}
// Any Arabic-script letter. A candidate subject or body carrying one is refused: the invitation is English only.
export const ARABIC_SCRIPT = /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/;

async function render(c) {
  globalThis.Deno ??= { env: { get: (k) => (k === 'SUPABASE_URL' ? PROJECT_URL : '') } };
  const base = new URL('../supabase/functions/send_outbox/', import.meta.url);
  const { tmpl } = await import(new URL('render.ts', base).href);
  const { plainTextPart } = await import(new URL('supplier_mail.ts', base).href);
  const { resendPayload, inboxLint, ownDomain } = await import(new URL('payload.ts', base).href);
  const { UNSUBSCRIBE_MAILBOX } = await import(new URL('../_shared/unsubscribe_mailbox.ts', base).href);
  const { withReplyQuestion, invitationCopyLint, endsWithOneQuestion } = await import(new URL('invitation_copy.ts', base).href);
  const reply = c.email_reply_supplier || 'supplier@quotesdone.com';
  const unsub = `${c.unsubscribe_public_base || PROJECT_URL + '/functions/v1/unsubscribe'}?e=zz-demo%40example.invalid&t=render-only`;
  const stored = inviteBody(c);
  const body = withReplyQuestion(stored);   // what send_outbox renders for an English invitation
  const subject = c.invite_subject;
  const preheader = c.invite_preheader || '';
  const html = tmpl({ body, logo: c.email_logo_url || '', name: c.email_signature_name || 'Ahmad Alzain', title: c.email_signature_title || 'Founder',
    channelEmail: reply, unsub, wrapper: c['tpl:email_supplier'] || '', internal: false, subject, preheader });
  const mail = resendPayload({ from: c.email_from_supplier || 'QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply, subject,
    html: ownDomain(html, PROJECT_URL, c.email_asset_public_base || ''), text: plainTextPart({ body, unsub, ar: false, internal: false }), unsub, unsubMailto: UNSUBSCRIBE_MAILBOX });
  const site = c.public_site_url || 'https://quotesdone.com';
  const copy = invitationCopyLint({ lang: 'en', subject, body, preheader, link: `${site}/en/portal?t=00000000-0000-0000-0000-000000000000` });
  copy.push({ rule: 'the STORED invite_body already ends with the question (the SQL is applied)', ok: endsWithOneQuestion(stored),
    detail: 'send_outbox appends it at send time; apply scripts/sql/the_supplier_invitation_ends_with_one_question_and_is_always_english.sql' });
  // A reply to the question must reach resend_inbound: every address on mail.quotesdone.com does; quotesdone.com
  // itself is a Microsoft 365 tenant no code reads (a_supplier_reply_reaches_a_mailbox_that_is_read.sql).
  copy.push({ rule: 'Reply-To is a mailbox resend_inbound reads (@mail.quotesdone.com)', ok: /@mail\.quotesdone\.com$/i.test(reply), detail: `Reply-To ${reply}` });
  return { mail, lint: [...inboxLint(mail, ['quotesdone.com', `${REF}.supabase.co`]), ...copy] };
}

async function main() {
  const c = await liveConfig();
  if (flag('send-seed')) {
    const to = arg('to');
    if (arg('lang') && arg('lang') !== 'en') { console.error('REFUSED: the supplier invitation is English only (ledger 993).'); process.exit(2); }
    if (!seedAddressAllowed(to)) { console.error(`REFUSED: ${to || '(no --to)'} is not on an inbox-test service (${SEED_DOMAINS.join(', ')}).`); process.exit(2); }
    const readOpt = (k) => (arg(k) ? readFileSync(arg(k), 'utf8').trim() : undefined);
    for (const k of ['subject-file', 'body-file']) {
      if (ARABIC_SCRIPT.test(readOpt(k) ?? '')) { console.error(`REFUSED: --${k} carries Arabic script; the supplier invitation is English only (ledger 993).`); process.exit(2); }
    }
    const subject = readOpt('subject-file') ?? c.invite_subject;
    const [row] = await sql(`insert into notifications (type, to_email, to_role, subject, body, lang, status, requested_by)
      values ('supplier_invite_seed', ${dq(to.toLowerCase())}, '${arg('role') === 'customer' ? 'customer' : 'supplier'}', ${dq(subject)}, ${dq(inviteBody(c, readOpt('body-file')))}, 'en', 'queued', 'customer_support')
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
  {
    const { mail, lint } = await render(c);
    console.log('\n=== the invitation, English (rendered, not sent)');
    console.log(`From:     ${mail.from}\nReply-To: ${mail.reply_to}\nSubject:  ${mail.subject}`);
    for (const [k, v] of Object.entries(mail.headers || {})) console.log(`${k}: ${v}`);
    console.log(`html ${mail.html.length} bytes, text ${mail.text.length} chars`);
    for (const l of lint) { console.log(`${l.ok ? 'PASS' : 'FAIL'}  ${l.rule}${l.detail && !l.ok ? '  -- ' + l.detail : ''}`); if (!l.ok) bad++; }
  }
  process.exit(bad ? 1 : 0);
}
if (import.meta.url === pathToFileURL(process.argv[1]).href) main().catch((e) => { console.error(e.message); process.exit(2); });
