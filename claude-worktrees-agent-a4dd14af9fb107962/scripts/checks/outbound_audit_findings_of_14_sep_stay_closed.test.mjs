// THE FIVE OUTBOUND FINDINGS OF THE 14 SEP AUDIT STAY CLOSED — owner: customer_support
//
//   node --test scripts/checks/outbound_audit_findings_of_14_sep_stay_closed.test.mjs
//
// Reads the repository only (no network). The audit is docs/audit/BACKEND_AUDIT_AND_ONE_YEAR_PLAN_2026-09-14.md.
// Each test fails if the fix for its finding drifts back.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const manifest = R('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
const dropped = R('scripts/sql/DROPPED.txt');
const SENDABLE = 'scripts/sql/the_invite_composer_calls_a_sendability_check_that_was_retired_under_it.sql';
const GUARD = 'scripts/sql/the_demo_guard_holds_a_row_moved_back_to_the_queue_and_its_release_exists.sql';

test('1. supplier_api search returns named fields only, never claimed_by', () => {
  const api = R('supabase/functions/supplier_api/index.ts');
  const line = api.split('\n').find((l) => l.includes("action === 'search'"));
  assert.ok(line, 'search action not found');
  assert.ok(!/\.\.\.r\b/.test(line), 'search spreads the raw row again');
  assert.match(line, /searchResult\(/);
  const shape = R('supabase/functions/supplier_api/search_result.ts');
  const body = shape.slice(shape.indexOf('export function searchResult'));
  assert.ok(!/^\s*claimed_by\s*:/m.test(body), 'searchResult returns claimed_by');
});

test('2. fn_email_sendable is defined again, revoked, pinned, and applied after the file that dropped it', () => {
  const sql = R(SENDABLE);
  assert.match(sql, /create or replace function public\.fn_email_sendable\(p_email text\)/);
  assert.match(sql, /security definer\s*\nset search_path to 'public', 'pg_temp'/);
  assert.match(sql, /revoke execute on function public\.fn_email_sendable\(text\) from public, anon, authenticated;/);
  assert.ok(!/^fn_email_sendable ::/m.test(dropped), 'DROPPED.txt still records fn_email_sendable as dropped');
  assert.ok(manifest.indexOf(SENDABLE) > manifest.indexOf('scripts/sql/retire_the_routines_no_seat_can_reach.sql'), 'must follow the file that dropped it');
});

test('3. the demo guard watches re-queues, and the release it names exists and refuses mid-rehearsal', () => {
  const sql = R(GUARD);
  assert.match(sql, /before insert or update of status, to_email, to_phone on public\.notifications/);
  assert.match(sql, /TG_OP = 'UPDATE' and coalesce\(NEW\.status, ''\) not in \('queued', 'pending', 'digest'\)/);
  assert.match(sql, /create or replace function public\.fn_notifications_release_held\(p_limit integer default 1000\)/);
  assert.match(sql, /refuses while decision_policy\.demo_rehearsal_active is true/);
  assert.match(sql, /starts_with\(coalesce\(n\.last_error, ''\), 'HELD by zzz_notifications_demo_guard'\)/);
  // a row held because the guard itself failed must not share the prefix the release selects on
  const fallback = sql.match(/NEW\.last_error := '([^']*)\(guard itself errored/);
  assert.ok(fallback && !fallback[1].startsWith('HELD by zzz_notifications_demo_guard'), 'the error fallback stamp collides with the release filter');
  assert.match(sql, /revoke execute on function public\.fn_notifications_release_held\(integer\) from public, anon, authenticated;/);
  assert.ok(!/^fn_notifications_release_held ::/m.test(dropped), 'DROPPED.txt still records fn_notifications_release_held');
  assert.ok(manifest.indexOf(GUARD) > manifest.indexOf('scripts/sql/the_demo_guard_keeps_rehearsals_out_of_notifications.sql'), 'must be the canonical guard');
  // the guard must not raise out of the trigger: its probe ends in a notice, never an exception
  assert.ok(!/raise exception 'CHK/.test(sql));
});

test('4. contact_submit is rate limited per IP and per address before anything is stored', () => {
  const src = R('supabase/functions/contact_submit/index.ts');
  const ip = src.indexOf("rl('contact_submit_ip:'"), em = src.indexOf("rl('contact_submit_email:'"), ins = src.indexOf("from('contact_messages').insert");
  assert.ok(ip > 0 && em > 0, 'rl_check keys missing');
  assert.ok(ins > ip && ins > em, 'the limit must run before the insert');
  assert.match(src, /admin\.rpc\('rl_check'/);
  assert.match(src, /, 429\)/);
});

// "never registered from code" was the 14 Sep position and is SUPERSEDED: the founder authorised the
// Meta submission on 18 Sep, and the EN + AR templates are in wa_template_setup's catalogue and
// submitted. What this test protects is unchanged and is the part that mattered — a row that cannot
// go yet says WHY instead of sitting silently, and the email twin is queued first and is the record.
test('5. a supplier_account_notice row with no approved template says why, and the email carries it', () => {
  const src = R('supabase/functions/send_whatsapp/index.ts');
  assert.match(src, /return 'supplier_account_notice'/);
  assert.match(src, /key === 'supplier_account_notice'\) await admin\.from\('notifications'\)\.update\(\{ last_error: AWAITING_TEMPLATE_NOTE \}\)/);
  assert.match(src, /AWAITING_TEMPLATE_NOTE = 'awaiting template: /);
  // and the template it is waiting for exists in the one place templates are authored
  assert.match(R('supabase/functions/wa_template_setup/index.ts'), /^ {2}supplier_account_notice: \{$/m);
  // the email twin is what carries the notice meanwhile
  const notice = R('scripts/sql/a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql');
  const fn = notice.slice(notice.indexOf('function public.fn_supplier_notice'));
  assert.ok(fn.indexOf("'email', v_subject") > 0 && fn.indexOf("'email', v_subject") < fn.indexOf("'whatsapp', v_subject"), 'fn_supplier_notice must queue the email first');
});
