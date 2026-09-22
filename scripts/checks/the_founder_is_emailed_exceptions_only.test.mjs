// THE FOUNDER IS EMAILED EXCEPTIONS ONLY.
//
// Founder's standing rule: he receives exceptions, not routine; nothing routes to his approval except a
// Stripe refund. On 6 Sep 2026 he asked for an audit of the mail from info@quotesdone.com — "so many errors
// were sent to me from the engine" — and 30 days of public.notifications showed ~210 of 244 emails were a
// department's work. public.founder_mail_policy (kind -> allowed_to_email, owner_role) now decides, and
// a10_notifications_founder_mail_policy on notifications + fn_notify_founder enforce it
// (scripts/sql/the_founder_is_emailed_exceptions_only.sql). This check is what keeps that true.
//
//   1. every notifications row addressed to him (to_role founder/admin/owner, or the first admin_emails
//      address) created in the last 24h, on the email or whatsapp channel, carries a kind the policy allowed
//      WHEN IT WAS QUEUED (public.founder_mail_policy_history, written only when allowed_to_email changes);
//   2. every routine that calls fn_notify_founder names its kind (p_kind =>), and every kind named as a
//      literal is registered; a non-literal kind (p_kind => r.kind) is data-driven and is covered at run
//      time by (1) and by the gate, which never emails an unregistered kind;
//   3. every literal kind passed to fn_founder_mail_route is registered;
//   4. the gate is attached: a10_notifications_founder_mail_policy exists on public.notifications and
//      fires before the digest trigger (BEFORE INSERT triggers fire in name order);
//   5. no founder_alerts row records a route failure in the last 24h (the gate logs
//      'founder_mail:route_failed' instead of emailing him when the door itself errors).
//
// READ-ONLY against production: every statement is a SELECT under an 8s statement timeout.
//
//   node --test scripts/checks/the_founder_is_emailed_exceptions_only.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}

test('notifications: every founder-bound email/whatsapp row of the last 24h has a kind the policy allows', { skip: SKIP }, async () => {
  const r = await rows(`
    with admin as (select lower(split_part(coalesce(value,''),',',1)) as email from public.app_secrets where key = 'admin_emails')
    select n.id, n.type, n.kind, n.status, left(n.subject, 100) as subject, n.created_at
      from public.notifications n, admin
     where n.created_at > now() - interval '24 hours'
       and coalesce(n.channel, 'email') in ('email', 'whatsapp')
       and (n.to_role in ('founder', 'admin', 'owner') or lower(n.to_email) = admin.email)
       and coalesce(n.to_email, '') !~* '@example[.]invalid$'
       -- A row is judged by the allowed_to_email IN FORCE WHEN IT WAS QUEUED, read from
       -- founder_mail_policy_history (the_founder_mail_policy_keeps_its_history.sql). MEASURED 22 Sep 2026:
       -- twelve it_new_bug emails of 21 Sep were sent while it_new_bug was allowed; instruction 642 set it false
       -- at 23:22 UTC, and judging them by today's value kept this red for a day on history. #825 exempted rows
       -- older than the kind's updated_at instead - but updated_at also moves on a reason / owner_role edit, so
       -- a cosmetic edit made after a real violation hid it (review of #825). History is written only when
       -- allowed_to_email changes. NULL = before the kind's first history row: not known, not judged.
       -- A never-registered kind is false.
       and public.fn_founder_mail_policy_at(coalesce(n.kind, n.type), n.created_at) is false
     order by n.created_at desc
     limit 50`);
  assert.equal(r.length, 0, 'these founder-bound rows carry a kind founder_mail_policy does not allow (the gate a10_notifications_founder_mail_policy should have routed them):\n' + JSON.stringify(r, null, 1));
});

// The history above is only as good as its writer: the trigger must be attached and enabled, and every kind's
// latest history value must equal its current allowed_to_email (a disabled trigger or a writer that bypassed it
// shows here as drift, before the first check judges an email by a stale value).
test('founder_mail_policy_history: the trigger is attached and every kind\'s history agrees with the policy', { skip: SKIP }, async () => {
  const t = await rows(`select tgenabled from pg_trigger where tgrelid = 'public.founder_mail_policy'::regclass and tgname = 'trg_founder_mail_policy_history'`);
  assert.equal(t.length, 1, 'trg_founder_mail_policy_history is not on public.founder_mail_policy (the_founder_mail_policy_keeps_its_history.sql)');
  assert.notEqual(t[0].tgenabled, 'D', 'trg_founder_mail_policy_history is disabled: allowed_to_email changes are not being recorded');
  const drift = await rows(`
    select p.kind, p.allowed_to_email, public.fn_founder_mail_policy_at(p.kind, 'infinity') as history_says
      from public.founder_mail_policy p
     where public.fn_founder_mail_policy_at(p.kind, 'infinity') is distinct from p.allowed_to_email`);
  assert.equal(drift.length, 0, 'these kinds\' latest founder_mail_policy_history value differs from founder_mail_policy.allowed_to_email:\n' + JSON.stringify(drift, null, 1));
});

test('routines: every fn_notify_founder call names p_kind, and every literal kind is registered', { skip: SKIP }, async () => {
  const r = await rows(`
    select p.proname,
           (select count(*) from regexp_matches(p.prosrc, 'fn_notify_founder\\s*\\(', 'g')) as calls,
           (select count(*) from regexp_matches(p.prosrc, 'p_kind\\s*=>', 'g')) as kinds_named,
           (select coalesce(array_agg(distinct m[1]), '{}') from regexp_matches(p.prosrc, 'p_kind\\s*=>\\s*''([a-z0-9_]+)''', 'g') m) as literal_kinds
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname <> 'fn_notify_founder'
       and p.prosrc ~ 'fn_notify_founder\\s*\\('`);
  assert.ok(r.length >= 5, 'expected the known callers of fn_notify_founder; found ' + r.length);
  const unnamed = r.filter(x => Number(x.calls) !== Number(x.kinds_named));
  assert.equal(unnamed.length, 0, 'these routines call fn_notify_founder without naming p_kind => (an unnamed kind is routed, never emailed, but the caller must say what it is):\n' + JSON.stringify(unnamed, null, 1));
  const literals = [...new Set(r.flatMap(x => x.literal_kinds || []))];
  if (literals.length) {
    const reg = await rows(`select kind from public.founder_mail_policy where kind = any(array[${literals.map(k => `'${k}'`).join(',')}]::text[])`);
    const have = new Set(reg.map(x => x.kind));
    const missing = literals.filter(k => !have.has(k));
    assert.equal(missing.length, 0, 'these kinds are passed to fn_notify_founder but have no founder_mail_policy row: ' + missing.join(', '));
  }
});

// 21 Sep 2026 (ceo). fn_notify_founder has returned JSONB since 6 Sep. fn_ceo_weekly_report_deliver kept
// `v_notif bigint := fn_notify_founder(...)`, every call raised "invalid input syntax for type bigint",
// its exception block rolled the email back, and the CEO weekly report failed on 14 and 21 Sep without
// reaching him. A variable that receives the answer must be declared jsonb.
test('routines: every variable assigned from fn_notify_founder is declared jsonb', { skip: SKIP }, async () => {
  const r = await rows(`
    select p.proname, m[1] as var,
           p.prosrc ~* ('\\m' || m[1] || '\\s+jsonb\\M') as declared_jsonb
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
           regexp_matches(p.prosrc, '(\\w+)\\s*:=\\s*(?:public\\.)?fn_notify_founder\\s*\\(', 'g') m
     where n.nspname = 'public' and p.proname <> 'fn_notify_founder'`);
  const bad = r.filter(x => x.declared_jsonb !== true);
  assert.equal(bad.length, 0, 'these routines store fn_notify_founder\'s jsonb answer in a variable not declared jsonb (the assignment raises and the email is rolled back):\n' + JSON.stringify(bad, null, 1));
});

test('routines: every literal kind passed to fn_founder_mail_route is registered', { skip: SKIP }, async () => {
  const r = await rows(`
    select distinct m[1] as kind
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
           regexp_matches(p.prosrc, 'fn_founder_mail_route\\s*\\(\\s*''([a-z0-9_]+)''', 'g') m
     where n.nspname = 'public' and p.proname <> 'fn_founder_mail_route'`);
  const kinds = r.map(x => x.kind);
  if (!kinds.length) return;
  const reg = await rows(`select kind from public.founder_mail_policy where kind = any(array[${kinds.map(k => `'${k}'`).join(',')}]::text[])`);
  const have = new Set(reg.map(x => x.kind));
  const missing = kinds.filter(k => !have.has(k));
  assert.equal(missing.length, 0, 'these kinds are routed by name but have no founder_mail_policy row: ' + missing.join(', '));
});

test('the gate is attached to notifications and fires before the digest trigger', { skip: SKIP }, async () => {
  const r = await rows(`
    select tgname, tgenabled
      from pg_trigger
     where tgrelid = 'public.notifications'::regclass and not tgisinternal
       and tgtype & 2 = 2 and tgtype & 4 = 4   -- BEFORE ... INSERT
     order by tgname`);
  const names = r.map(x => x.tgname);
  assert.ok(names.includes('a10_notifications_founder_mail_policy'), 'a10_notifications_founder_mail_policy is not a BEFORE INSERT trigger on public.notifications; found: ' + names.join(', '));
  const gate = r.find(x => x.tgname === 'a10_notifications_founder_mail_policy');
  assert.notEqual(gate.tgenabled, 'D', 'the gate is disabled');
  const digest = names.indexOf('trg_notifications_digest');
  if (digest >= 0) assert.ok(names.indexOf('a10_notifications_founder_mail_policy') < digest, 'the gate must sort before trg_notifications_digest');
});

test('founder_alerts: no route failure recorded in the last 24h', { skip: SKIP }, async () => {
  const r = await rows(`
    select id, left(detail, 300) as detail, created_at
      from public.founder_alerts
     where event = 'founder_mail:route_failed' and created_at > now() - interval '24 hours'
     order by created_at desc limit 20`);
  assert.equal(r.length, 0, 'fn_founder_mail_route failed inside the gate (the row was dropped, not emailed, but the door is broken):\n' + JSON.stringify(r, null, 1));
});
