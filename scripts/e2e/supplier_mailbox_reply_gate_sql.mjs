// scripts/e2e/supplier_mailbox_reply_gate_sql.mjs: the supplier-mailbox reply gate's SQL, run for real, on a throwaway local
// Postgres that this script creates and deletes. customer_support, 11 Nov 2026, founder ruling 1633.
//
//   node scripts/e2e/supplier_mailbox_reply_gate_sql.mjs        (needs PostgreSQL server binaries: initdb, pg_ctl, psql)
//
// WHAT IT PROVES. On 9-10 Nov 2026 inbound_messages 1874 (azure-noreply@microsoft.com) and 1994/2069
// (supportmail@techsupport.microsoft.com) were declined by email_triage and answered anyway with the registration template
// (notifications 129468, 134514, 138326) by fn_sales_engineer_acts_on_supplier_reply, which never read the decline, through
// fn_inbox_send, which refused nothing but an empty body.
//   KNOWN-BAD CONTROL: the previous canonical bodies (read from the files scripts/sql/MANIFEST.txt makes canonical) answer
//   the Azure mail exactly as production did: one supplier_mailbox_reply to azure-noreply@microsoft.com and a follow-up.
//   THE FIX: scripts/sql/a_reply_from_the_supplier_mailbox_leaves_only_when_the_reading_said_answer.sql applied whole, its
//   verdict PROBE OK, and then every rule of the brief, each on its own row.
//
// IT CANNOT REACH PRODUCTION OR A PERSON. It reads no credential and no environment database URL; the server listens on a Unix
// socket inside its own temporary directory (listen_addresses = ''), and every psql call names that socket. PG* variables are
// removed from the child environment. There is no network code in this file: a "sent" mail here is a row in a table that is
// deleted with the cluster. The addresses are the shapes measured on production (a supplier address is a zz-demo domain).
import { spawnSync } from 'node:child_process';
import { chownSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const FIX = 'scripts/sql/a_reply_from_the_supplier_mailbox_leaves_only_when_the_reading_said_answer.sql';

function pgBin() {
  const tryDir = (d) => d && existsSync(join(d, 'initdb')) && existsSync(join(d, 'pg_ctl')) ? d : null;
  const cfg = spawnSync('pg_config', ['--bindir'], { encoding: 'utf8' });
  const fromCfg = cfg.status === 0 ? tryDir(cfg.stdout.trim()) : null;
  if (fromCfg) return fromCfg;
  const base = '/usr/lib/postgresql';
  if (existsSync(base)) for (const v of readdirSync(base).sort().reverse()) { const d = tryDir(join(base, v, 'bin')); if (d) return d; }
  const which = spawnSync('sh', ['-c', 'command -v initdb'], { encoding: 'utf8' });
  if (which.status === 0) return tryDir(which.stdout.trim().replace(/\/initdb$/, ''));
  return null;
}
const BIN = pgBin();
if (!BIN) { console.error('REFUSED: no PostgreSQL server binaries (initdb, pg_ctl) found; this proof needs a local Postgres.'); process.exit(2); }
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG') && k !== 'DATABASE_URL'));
const DIR = mkdtempSync(join(tmpdir(), 'qd-mailbox-gate-'));
const DATA = join(DIR, 'data');
// initdb refuses to run as root (cloud sessions are root): the server then runs as an unprivileged local account.
const idOf = (u) => { const r = spawnSync('id', ['-u', u], { encoding: 'utf8' }); const g = spawnSync('id', ['-g', u], { encoding: 'utf8' }); return r.status === 0 ? [Number(r.stdout), Number(g.stdout)] : null; };
const AS = process.getuid?.() === 0 ? (['postgres', 'nobody'].map((u) => [u, idOf(u)]).find(([, i]) => i) ?? null) : null;
if (process.getuid?.() === 0 && !AS) { console.error('REFUSED: running as root and no unprivileged account (postgres, nobody) to run the server as.'); process.exit(2); }
if (AS) chownSync(DIR, AS[1][0], AS[1][1]);
const spawnAs = (bin, args, opts) => AS ? spawnSync('runuser', ['-u', AS[0], '--', bin, ...args], opts) : spawnSync(bin, args, opts);
const run = (cmd, args) => {
  const r = spawnAs(join(BIN, cmd), args, { encoding: 'utf8', env, maxBuffer: 16 << 20 });
  if (r.status !== 0) throw new Error(cmd + ' failed: ' + (r.stderr || r.stdout).slice(0, 2000));
  return r.stdout;
};
const sql = (q) => {
  const r = spawnAs(existsSync(join(BIN, 'psql')) ? join(BIN, 'psql') : 'psql', ['-h', DIR, '-U', 'postgres', '-d', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1'],
    { encoding: 'utf8', env, input: q, maxBuffer: 16 << 20 });
  if (r.status !== 0) throw new Error('psql: ' + (r.stderr || r.stdout).slice(0, 2000));
  return r.stdout.trim();
};
const j = (q) => JSON.parse(sql(q) || 'null');
const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// The one canonical body of a routine in a file: from its CREATE OR REPLACE to the closing dollar tag.
function bodyOf(file, routine) {
  const src = readFileSync(file, 'utf8');
  const at = src.search(new RegExp('create\\s+or\\s+replace\\s+function\\s+(?:public\\.)?' + routine + '\\s*\\(', 'i'));
  if (at < 0) throw new Error(routine + ' is not defined in ' + file);
  const tail = src.slice(at);
  const tag = tail.match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  const open = tail.indexOf(tag);
  return tail.slice(0, tail.indexOf(tag, open + tag.length) + tag.length) + ';\n';
}
// The canonical file for a routine is the LAST one in scripts/sql/MANIFEST.txt that defines it (the apply order).
function canonicalFile(routine) {
  const files = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const def = new RegExp('create\\s+or\\s+replace\\s+function\\s+(?:public\\.)?' + routine + '\\s*\\(', 'i');
  let last = null;
  for (const f of files) { try { if (def.test(readFileSync(f, 'utf8'))) last = f; } catch { /* listed, not on disk: the manifest check owns that */ } }
  if (!last) throw new Error('no canonical file defines ' + routine);
  return last;
}
const canonical = (routine) => bodyOf(canonicalFile(routine), routine);

const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log((ok ? 'PASS ' : 'FAIL ') + name + (ok ? '' : '  ' + detail)); };

// One inbound mail, as resend_inbound stores it; returns its id.
let mid = 5000;
function inbound({ id = ++mid, from, subject = 'Hello', body = 'Hello', raw = {}, created = 'now()' }) {
  const r = { message_id: `<m${id}@sender.zz-demo>`, ...raw };
  sql(`insert into public.inbound_messages (id, from_email, to_email, subject, body, raw, created_at, needs_review, ai_category, ai_summary, triaged_at)
       values (${id}, ${lit(from)}, 'supplier@quotesdone.com', ${lit(subject)}, ${lit(body)}, ${lit(JSON.stringify(r))}::jsonb, ${created}, true, null, null, null)`);
  return id;
}
// The decline email_triage wrote on 9-10 Nov, and the z53 handoff it fired.
let hid = 700;
function declinedWithHandoff(id) {
  sql(`update public.inbound_messages set ai_category = 'no_auto_reply', ai_summary = 'Not answered automatically: internal (customer_mail.ts noAutoReply).',
         triaged_at = now(), owner_role = 'sales_engineer' where id = ${id}`);
  sql(`insert into public.agent_actions (id, agent, kind, status, detail) values (${++hid}, 'sales_engineer', 'handoff', 'pending',
         jsonb_build_object('type', 'mailbox.supplier_reply', 'inbound_message_id', ${id}))`);
  return hid;
}
const repliesTo = (addr) => Number(sql(`select count(*) from public.notifications where type = 'inbound_reply' and lower(to_email) = lower(${lit(addr)})`));

try {
  run('initdb', ['-D', DATA, '-U', 'postgres', '--auth=trust', '-E', 'UTF8', '--no-locale']);
  run('pg_ctl', ['-D', DATA, '-o', `-c listen_addresses='' -k ${DIR} -c fsync=off -c timezone=UTC`, '-l', join(DIR, 'log'), '-w', 'start']);

  // The tables the routines read and write, in the columns they use. Nothing else from production is needed or copied.
  sql(`create role anon; create role authenticated; create role service_role;
    create table public.app_secrets (key text primary key, value text);
    create table public.org_role (role_id text primary key, status text);
    create table public.customers (id bigserial primary key, email text);
    create table public.leads (id bigint primary key, email text, claimed_by text, company_name text, claimed boolean, registration_submitted_at timestamptz);
    create table public.email_suppressions (email text primary key, reason text, source text);
    create table public.inbound_messages (id bigint primary key, lead_id bigint, from_email text, to_email text, subject text, body text, raw jsonb,
      created_at timestamptz default now(), needs_review boolean, ai_category text, ai_summary text, triaged_at timestamptz, replied_at timestamptz,
      replied_by text, owner_role text);
    create table public.notifications (id bigserial primary key, type text, to_email text, to_role text, lead_id bigint, kind text, channel text,
      subject text, body text, in_reply_to text, dedupe_key text, status text default 'queued', requested_by text, lang text, created_at timestamptz default now());
    create unique index notifications_dedupe_key_uidx on public.notifications (dedupe_key) where dedupe_key is not null;
    create table public.agent_actions (id bigserial primary key, agent text, kind text, status text, risk text, title text, detail jsonb, target_table text,
      target_id text, decided_by text, decided_at timestamptz);
    create table public.support_case (case_id bigserial primary key, case_ref text, channel text, party_id text, state text, subject text, csat_requested_at timestamptz);
    create table public.table_export_registry (table_name text primary key, exported boolean, category text, reason text, added_by text);
    create table public.supplier_reply_followup (id bigserial primary key, inbound_message_id bigint not null unique references public.inbound_messages (id),
      lead_id bigint, to_email text not null, intent text not null check (intent in ('subsidiary', 'later', 'interested')), due_at timestamptz not null,
      state text not null default 'due' check (state in ('due', 'sent', 'dropped')), outcome text, created_at timestamptz not null default now(), done_at timestamptz);
    -- the seat doors these routines call, as no-ops or a plain insert
    create function public.fn_support_case_close(text, text, text) returns void language sql as $$ select $$;
    create function public.fn_seat_handoff_act(bigint) returns jsonb language sql as $$ select '{}'::jsonb $$;
    create function public.fn_customer_support_takes_delivery(p jsonb) returns jsonb language sql as $$
      insert into public.notifications (type, to_email, to_role, channel, subject, body, dedupe_key)
      select x->>'type', x->>'to_email', x->>'to_role', x->>'channel', x->>'subject', x->>'body', x->>'dedupe_key' from jsonb_array_elements(p) x
      returning '{}'::jsonb $$;`);
  sql(`insert into public.app_secrets (key, value) values ('invite_m365_mailbox', 'supplier@quotesdone.com'), ('email_reply_supplier', 'suppliers@mail.quotesdone.com'),
         ('admin_emails', 'founder@zz-demo-founder.ae'), ('public_site_url', 'https://quotesdone.com');
       insert into public.org_role values ('ceo','active'),('customer_support','active'),('sales_engineer','active'),('accountant','active'),('it_engineer','active'),('marketing','active');`);
  // The routines the gate leans on, from their canonical files.
  for (const r of ['fn_mailbox_fold', 'fn_is_demo_email', 'fn_is_founder_own_inbox', 'fn_mail_sender_known', 'fn_is_machine_sender', 'fn_inbound_is_bounce',
    'fn_supplier_reply_intent', 'fn_supplier_reply_answer']) sql(canonical(r));

  // ---- KNOWN-BAD CONTROL: the bodies production ran on 9-10 Nov ------------------------------------------------------------
  sql(canonical('fn_inbox_send'));
  sql(canonical('fn_sales_engineer_acts_on_supplier_reply'));
  sql(`select setval('public.notifications_id_seq', 129467)`);   // so the control's reply is 129468, as on production
  const azure = inbound({ id: 1874, from: 'azure-noreply@microsoft.com', subject: 'Your new Azure account is ready', body: 'Welcome to Azure. Sign in to deploy your first Azure solution.' });
  const ho = declinedWithHandoff(azure);
  const ctl = j(`select public.fn_sales_engineer_acts_on_supplier_reply(${ho})::text`);
  check('known-bad control: the previous bodies answer the declined Azure mail with the registration template',
    repliesTo('azure-noreply@microsoft.com') === 1 && sql(`select body from public.notifications where id = 129468`).startsWith('Thank you for your reply.'), JSON.stringify(ctl));
  check('known-bad control: as supplier_mailbox_reply, replied_by sales_engineer, with a follow-up promised to Microsoft',
    sql(`select kind from public.notifications where id = 129468`) === 'supplier_mailbox_reply'
    && sql(`select replied_by from public.inbound_messages where id = ${azure}`) === 'sales_engineer'
    && sql(`select count(*) from public.supplier_reply_followup where inbound_message_id = ${azure} and state = 'due'`) === '1');

  // ---- THE FIX, applied whole --------------------------------------------------------------------------------------------
  const verdict = sql(readFileSync(FIX, 'utf8')).split('\n').pop();
  check('the file applies on the control\'s state and its verdict reads PROBE OK', verdict === 'PROBE OK', verdict);
  check('the Azure reply already queued (129468) would be refused at send: no reading allowed it',
    j(`select public.fn_mailbox_reply_may_leave(129468)::text`)?.allow === false);
  check('the follow-up the template promised Microsoft is dropped by the rule, not by hand',
    sql(`select state from public.supplier_reply_followup where inbound_message_id = ${azure}`) === 'dropped');
  check('the table is RLS on, one deny policy, nothing for anon or authenticated',
    sql(`select relrowsecurity from pg_class where oid = 'public.mailbox_reply_decision'::regclass`) === 't'
    && sql(`select count(*) from pg_policies where tablename = 'mailbox_reply_decision'`) === '1'
    && sql(`select has_table_privilege('anon', 'public.mailbox_reply_decision', 'select')`) === 'f');
  const created = ['fn_mail_thread_key(jsonb)', 'fn_is_supplier_mailbox_mail(text)', 'fn_mail_reply_target_is_ours(text,text)', 'fn_mailbox_auto_reply_key(bigint)',
    'fn_mailbox_reply_hard_rule(bigint)', 'fn_mailbox_reading_of_rule(text)', 'fn_mailbox_reply_rules(bigint)',
    'fn_mailbox_reply_decide(bigint,text,text,text,text,text,text)', 'fn_mailbox_followup_allowed(bigint)', 'fn_mailbox_reply_may_leave(bigint)'];
  const open = created.filter((s) => sql(`select has_function_privilege('anon', 'public.${s}', 'execute') or has_function_privilege('authenticated', 'public.${s}', 'execute')`) === 't');
  check('every routine the file creates is closed to anon and authenticated', open.length === 0, open.join(', '));
  const unpinned = sql(`select string_agg(p.proname, ',') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
    and p.proname in ('fn_mail_thread_key','fn_is_supplier_mailbox_mail','fn_mail_reply_target_is_ours','fn_mailbox_auto_reply_key','fn_mailbox_reply_hard_rule',
      'fn_mailbox_reading_of_rule','fn_mailbox_reply_rules','fn_mailbox_reply_decide','fn_mailbox_followup_allowed','fn_mailbox_reply_may_leave','fn_inbox_send',
      'fn_sales_engineer_acts_on_supplier_reply','fn_sales_engineer_follows_up_supplier_replies')
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')`);
  check('every routine the file defines pins its search_path', unpinned === '', unpinned);

  // ---- HARD RULES IN CODE ------------------------------------------------------------------------------------------------
  const rule = (id) => sql(`select coalesce(public.fn_mailbox_reply_hard_rule(${id}), 'none')`);
  check('azure-noreply@microsoft.com is a machine sender', rule(azure) === 'machine_sender');
  for (const [from, want] of [['mailer-daemon@googlemail.com', 'bounce'], ['postmaster@zz-demo-host.ae', 'bounce'], ['notifications@zz-demo-saas.ae', 'machine_sender'],
    ['no-reply@zz-demo-saas.ae', 'machine_sender'], ['alerts@zz-demo-saas.ae', 'machine_sender'], ['management@quotesdone.com', 'founder_inbox'],
    ['founder@zz-demo-founder.ae', 'founder_inbox'], ['ops@quotesdone.ae', 'own_domain']]) {
    check(`${from} is refused by code (${want})`, rule(inbound({ from, subject: 'x', body: 'x' })) === want, rule(mid));
  }
  for (const [label, raw, want] of [['Auto-Submitted: auto-generated', { auto_submitted: 'auto-generated' }, 'auto_submitted'],
    ['X-Autoreply', { x_autoreply: 'yes' }, 'auto_submitted'], ['Precedence: bulk', { precedence: 'bulk' }, 'list_mail'],
    ['List-Id (stored as list_unsubscribe)', { list_unsubscribe: '<news.zz-demo-saas.ae>' }, 'list_mail'], ['list_id', { list_id: '<x.zz-demo>' }, 'list_mail']]) {
    check(`a person's address with ${label} is refused by code (${want})`, rule(inbound({ from: 'person@zz-demo-co.ae', raw })) === want, rule(mid));
  }
  const hand = inbound({ from: 'ahmad@zz-demo-realestate.ae', subject: 'Re: Registration',
    body: 'Definitely but later\n________________________________\nFrom: Ahmad Alzain - QuotesDone <supplier@quotesdone.com>\nSent: Wednesday',
    raw: { in_reply_to: '<DX3P273MB216182EBCF07FA498AA9DE0AA86F2@DX3P273MB2161.AREP273.PROD.OUTLOOK.COM>' } });
  check('a reply to mail the founder sent by hand from Outlook (inbound 1483) is refused by code', rule(hand) === 'replies_to_mail_sent_by_hand', rule(hand));
  const ours = inbound({ from: 'sales@zz-demo-coating.ae', subject: 'Re: A question about your work', body: 'Yes, interested\nFrom: Ahmad Alzain - QuotesDone <supplier@quotesdone.com>',
    raw: { in_reply_to: '<qd-notif-124771.1793858496131@quotesdone.com>' } });
  check('a reply to one of OUR automatic mails (inbound 1871) is not refused by that rule', rule(ours) === 'none', rule(ours));

  // ---- THE DECISION IS THE ONLY KEY ------------------------------------------------------------------------------------
  const dec = (id, reading) => j(`select public.fn_mailbox_reply_decide(${id}, ${reading ? lit(reading) : 'null'}, 'why', 'quote', 'model', 'stub/model', 'high')::text`);
  const send = (id, by) => j(`select public.fn_inbox_send(${id}, 'Hello,\n\nAn answer to what you wrote.\n\nKind regards,\nThe QuotesDone Team', ${by ? lit(by) : 'null'})::text`);
  const azure2 = inbound({ from: 'azure-noreply@microsoft.com', subject: 'Your Azure invoice', body: 'Your invoice is ready.' });
  const hoA = declinedWithHandoff(azure2);
  check('the handoff waits for the reading and writes nothing', 'waiting' in (j(`select public.fn_sales_engineer_acts_on_supplier_reply(${hoA})::text`) ?? {}) && repliesTo('azure-noreply@microsoft.com') === 1);
  const dA = dec(azure2, 'supplier_registration');
  check('a model that misreads Azure as a supplier is overruled by code: automated_notice, may_reply false', dA.reading === 'automated_notice' && dA.may_reply === false && dA.hard_rule === 'machine_sender', JSON.stringify(dA));
  const aA = j(`select public.fn_sales_engineer_acts_on_supplier_reply(${hoA})::text`);
  check('the handoff, once read: "not answered", no reply, no follow-up', String(aA?.action).startsWith('not answered: the mail was read as automated_notice')
    && repliesTo('azure-noreply@microsoft.com') === 1 && sql(`select count(*) from public.supplier_reply_followup where inbound_message_id = ${azure2}`) === '0', JSON.stringify(aA));
  const sA = send(azure2, 'sales_engineer');
  check('fn_inbox_send refuses a seat\'s answer to it', String(sA?.error).startsWith('refused: this mail was read as automated_notice'), JSON.stringify(sA));

  const ms = inbound({ from: 'supportmail@techsupport.microsoft.com', subject: 'Quota request for Standard NVADSA10v5 Family vCPUs at UAE North',
    body: 'Hello Ahmad, Your ask for quota has been reviewed and backlogged at this time. We will continue working on it.' });
  check('the Microsoft support case has no code rule: the model must read it', rule(ms) === 'none', rule(ms));
  const hoM = declinedWithHandoff(ms);
  const dM = dec(ms, 'vendor_our_account');
  check('read as vendor_our_account: may_reply false', dM.may_reply === false && dM.reading === 'vendor_our_account');
  const aM = j(`select public.fn_sales_engineer_acts_on_supplier_reply(${hoM})::text`);
  check('its handoff sends nothing (on 10 Nov the regex read "continue working on it" as later and answered)', repliesTo('supportmail@techsupport.microsoft.com') === 0
    && String(aM?.action).includes('vendor_our_account'), JSON.stringify(aM));
  check('fn_inbox_send refuses customer_support too', String(send(ms, 'customer_support')?.error).startsWith('refused'));
  const unread = inbound({ from: 'someone@zz-demo-co.ae', subject: 'x', body: 'y' });
  check('a seat may not answer a supplier-mailbox mail that was never read', String(send(unread, 'customer_support')?.error).includes('never read'));

  // a supplier asking to register: the one case that is answered, once per sender per thread per Dubai day
  const sup = inbound({ from: 'owner@zz-demo-fitout.ae', subject: 'Registration', body: 'How do we register our company as a supplier?' });
  const hoS = declinedWithHandoff(sup);
  sql(`update public.inbound_messages set ai_category = 'supplier_question', ai_summary = 'stub', owner_role = null where id = ${sup}`);
  check('read as supplier_registration: may_reply true', dec(sup, 'supplier_registration').may_reply === true);
  const s1 = send(sup, 'customer_support');
  check('customer_support\'s answer is queued, keyed one per sender/thread/day, and linked to its decision', s1?.ok === true
    && sql(`select dedupe_key from public.notifications where id = ${s1.notification_id}`).startsWith('mailbox_auto_reply:owner@zz-demo-fitout.ae:')
    && sql(`select reply_notification_id from public.mailbox_reply_decision where inbound_message_id = ${sup}`) === String(s1.notification_id), JSON.stringify(s1));
  check('and the send gate lets it leave', j(`select public.fn_mailbox_reply_may_leave(${s1.notification_id})::text`)?.allow === true);
  const s2 = send(sup, 'customer_support');
  check('a second automatic answer in the same thread the same day is refused', String(s2?.error).startsWith('refused') && repliesTo('owner@zz-demo-fitout.ae') === 1, JSON.stringify(s2));
  const again = inbound({ from: 'owner@zz-demo-fitout.ae', subject: 'Re: Registration', body: 'Thanks, and the trade licence?', raw: { references: `<m${sup}@sender.zz-demo>`, in_reply_to: `<m${sup}@sender.zz-demo>` } });
  check('their next mail in that thread the same day: daily_cap by code', rule(again) === 'daily_cap', rule(again));
  const aS = j(`select public.fn_sales_engineer_acts_on_supplier_reply(${hoS})::text`);
  check('the handoff records the answer and files the follow-up the reading allowed', String(aS?.action).startsWith('answered by customer_support')
    && sql(`select state from public.supplier_reply_followup where inbound_message_id = ${sup}`) === 'due', JSON.stringify(aS));

  // the last answer in a thread was a person's: never answered automatically after it
  const p1 = inbound({ from: 'buyer@zz-demo-buyer.ae', subject: 'Prices', body: 'Do you supply marble?' });
  check('a person answers from the Inbox (p_by null): no reading needed, marked as a person\'s', send(p1, null)?.ok === true
    && j(`select public.fn_mailbox_reply_may_leave(max(id))::text from public.notifications`)?.allow === true);
  const p2 = inbound({ from: 'buyer@zz-demo-buyer.ae', subject: 'Re: Prices', body: 'Thanks, and granite?', raw: { references: `<m${p1}@sender.zz-demo>`, in_reply_to: `<m${p1}@sender.zz-demo>` } });
  check('their next mail: person_in_thread by code, so no seat answers into the founder\'s conversation', rule(p2) === 'person_in_thread', rule(p2));
  dec(p2, 'customer');
  check('even read as a customer, a seat\'s answer is refused', String(send(p2, 'customer_support')?.error).startsWith('refused'));

  // ---- THE SEND GATE CATCHES A ROW ANY PATH WROTE -------------------------------------------------------------------------
  const bypass = sql(`insert into public.notifications (type, to_email, kind, channel, subject, body) values ('inbound_reply', 'supportmail@techsupport.microsoft.com',
    'supplier_mailbox_reply', 'email', 'Re: Quota', 'To register, open the portal') returning id`);
  check('a supplier_mailbox_reply written straight into the outbox (no fn_inbox_send) is refused at send', j(`select public.fn_mailbox_reply_may_leave(${bypass})::text`)?.allow === false);
  const tmplFollow = sql(`insert into public.supplier_reply_followup (inbound_message_id, to_email, intent, due_at) values (${ms}, 'supportmail@techsupport.microsoft.com', 'later', now()) returning id`);
  const fq = sql(`insert into public.notifications (type, to_email, channel, subject, body, dedupe_key) values ('supplier_registration_reminder',
    'supportmail@techsupport.microsoft.com', 'email', 'Your QuotesDone supplier registration', 'Hello', 'supplier_reply_followup:${tmplFollow}') returning id`);
  check('a follow-up queued for mail whose reading allowed no answer is refused at send', j(`select public.fn_mailbox_reply_may_leave(${fq})::text`)?.allow === false);
  const okFollow = sql(`select id from public.supplier_reply_followup where inbound_message_id = ${sup}`);
  const fq2 = sql(`insert into public.notifications (type, to_email, channel, subject, body, dedupe_key) values ('supplier_registration_reminder',
    'owner@zz-demo-fitout.ae', 'email', 'Your QuotesDone supplier registration', 'Hello', 'supplier_reply_followup:${okFollow}') returning id`);
  check('the supplier\'s own follow-up is allowed', j(`select public.fn_mailbox_reply_may_leave(${fq2})::text`)?.allow === true);
  const other = sql(`insert into public.notifications (type, to_email, channel, subject, body) values ('quote_received', 'x@zz-demo-co.ae', 'email', 's', 'b') returning id`);
  check('a row that is not a supplier-mailbox reply is not this gate\'s', j(`select public.fn_mailbox_reply_may_leave(${other})::text`)?.allow === true);
  // a row from before the readings: answered by customer_support's model counts; the template's never does
  const legacy = inbound({ from: 'sales@zz-demo-coating2.ae', subject: 'Re: work', body: 'Yes' });
  sql(`update public.inbound_messages set replied_at = now(), replied_by = 'customer_support' where id = ${legacy}`);
  check('a pre-reading row answered by customer_support keeps its follow-up; the template\'s does not',
    sql(`select public.fn_mailbox_followup_allowed(${legacy})`) === 't' && sql(`select public.fn_mailbox_followup_allowed(${azure})`) === 'f');
} catch (e) {
  check('the run completed', false, String(e?.message || e).slice(0, 1500));
} finally {
  try { run('pg_ctl', ['-D', DATA, '-m', 'immediate', '-w', 'stop']); } catch { /* already down */ }
  rmSync(DIR, { recursive: true, force: true });
}
const failed = results.filter((x) => !x.ok).length;
console.log(`VERDICT ${failed ? 'FAILED' : 'OK'}: ${results.length - failed}/${results.length} checks passed (throwaway database deleted)`);
process.exit(failed ? 1 : 0);
