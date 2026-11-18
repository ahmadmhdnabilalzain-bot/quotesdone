// THE FOUNDER IS E-MAILED EACH SUPPLIER WHO REGISTERS AND IS APPROVED (sales_engineer, 18 Nov 2026; founder ruling 1731). The registration
// notice he had was routed to a task (kind supplier_registered may not e-mail him) and was sent at first Save only, while an approval
// often lands later. FAILS if: the kind may not e-mail him; the trigger stops firing on every approval, or fires on every update of an
// approved row; a demo / test identity, an e2e run's supplier or his own account is told; one supplier can be told twice; the e-mail
// loses a field the ruling names (company, trades / services, emirate, how he came, a link to the record); the founder's address is
// written in the file instead of read from config; it goes by WhatsApp (level above info); a routine loses its revoke or search_path.
// Rehearsed on a local Postgres 16 with production's own bodies of the routines it calls (the file's header).
//   node --test scripts/checks/the_founder_is_e_mailed_each_supplier_who_registers_and_is_approved.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyState, manifestWithPending } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FILE = 'scripts/sql/the_founder_is_e_mailed_each_supplier_who_registers_and_is_approved.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const src = code(R(FILE));
const body = (fn) => { const i = src.indexOf(`create or replace function public.${fn}(`); assert.ok(i >= 0, `${fn} is not defined`); return src.slice(i, src.indexOf('$fn$;', src.indexOf('$fn$', i) + 4) + 5); };

test('the kind may e-mail him, and every approval on every path is the one moment it fires', () => {
  assert.match(src, /insert into public\.founder_mail_policy \(kind, allowed_to_email, reason, owner_role\)\s+values \('supplier_approved_founder', true,/);
  assert.match(src, /create trigger trg_z30_founder_hears_of_each_approved_supplier\s+after insert or update of approval_status on public\.leads\s+for each row when \(new\.approval_status = 'approved'\)/);
  assert.match(body('fn_founder_hears_of_each_approved_supplier'), /if tg_op = 'UPDATE' and coalesce\(old\.approval_status, ''\) = 'approved' then return null; end if;/, 'not the transition only');
});

test('never a demo or test identity, never his own account, never twice', () => {
  const skip = body('fn_founder_supplier_approved_skip');
  assert.match(skip, /public\.fn_seat_clock_lead_is_fixture\(p\)/);
  assert.match(skip, /t like 'qd\\_run:%' or t = 'qd_demo'/);
  assert.match(skip, /public\.fn_is_founder_own_inbox\(p\.claimed_by\) or public\.fn_is_founder_own_inbox\(p\.email\)/);
  assert.match(skip, /f\.dedupe_key = 'supplier_approved_founder:' \|\| p\.id and f\.channel = 'email'/, 'the once-per-supplier test is gone');
  const trg = body('fn_founder_hears_of_each_approved_supplier');
  const at = trg.indexOf('fn_founder_supplier_approved_skip(new)'), send = trg.indexOf('fn_notify_founder(');
  assert.ok(at > 0 && send > at && /if v_why is null then/.test(trg.slice(at, send)), 'the send is not behind the skip');
  assert.match(trg, /p_kind => 'supplier_approved_founder', p_dedupe_key => 'supplier_approved_founder:' \|\| new\.id/);
  assert.match(trg, /p_level => 'info'/, 'a level above info also sends WhatsApp');
  assert.match(trg, /exception when others then[\s\S]+'failed'/, 'a failure could undo the approval');
});

test('the e-mail names company, trades and services, emirate, how he came and his record; the address comes from config', () => {
  const c = body('fn_founder_supplier_approved_compose');
  for (const f of ["'Company: '", "'Trades: '", "'Services: '", "'Emirate: '", "'How he came: '", "'Record: '"]) assert.ok(c.includes(f), `the e-mail lost ${f}`);
  for (const k of ["'referral: referred by '", "'invitation: we invited him'", "'direct: he registered on the site himself'"]) assert.ok(c.includes(k), `how he came lost ${k}`);
  assert.match(c, /from public\.supplier_referral r/);
  assert.match(c, /from public\.marketing_first_touch f/);
  assert.match(c, /key = 'project_ref'/, 'the record link is not built from config');
  // no address is written into any routine of this file: fn_notify_founder reads admin_emails
  for (const fn of ['fn_founder_supplier_approved_skip', 'fn_founder_supplier_approved_compose', 'fn_founder_hears_of_each_approved_supplier'])
    assert.doesNotMatch(body(fn), /[a-z0-9._%+-]+@[a-z0-9-]+\.[a-z]{2,}/i, `${fn} writes an e-mail address`);
  assert.doesNotMatch(src, /insert into public\.notifications/i, 'the file queues mail itself instead of through fn_notify_founder');
});

test('routines are closed and pinned; the file is applied or pending and ends in a verdict row', () => {
  for (const [fn, sig] of [['fn_founder_supplier_approved_skip', 'public.leads'], ['fn_founder_supplier_approved_compose', 'public.leads'], ['fn_founder_hears_of_each_approved_supplier', '']]) {
    assert.match(body(fn).slice(0, 300), /set search_path to 'public', 'pg_temp'/, `${fn}: search_path not pinned`);
    assert.ok(src.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), `${fn}: no revoke`);
  }
  const st = applyState(FILE);
  assert.ok(st.applied !== (st.note !== null), 'exactly one of a MANIFEST line and a pending note');
  assert.ok(manifestWithPending().includes(FILE));
  assert.match(R(FILE), /'PROBE OK: the founder is e-mailed once per approved supplier/);
  assert.doesNotMatch(src, /raise notice/i);
});
