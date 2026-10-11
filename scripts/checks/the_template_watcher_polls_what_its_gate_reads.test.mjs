// The WhatsApp template watcher's gate reads public.messaging_template ("is anything undecided?").
// On 28 Sep 2026 its poll read only the wa_template_sids map, so 9 undecided register rows were never
// asked about, the gate never shut, and every run re-announced "all approved" (8 error rows in 24 h),
// called a pg_cron unschedule routine that does not exist, and polled 17 sids one after another past
// resilience_ping's 20 s timeout (heartbeat step `orphans` red from 16:46 UTC). Ledger 760.
//
// 29 Sep 2026 (review of #1049): an APPROVED verdict was read from the register and Twilio was never
// asked again, so a template Meta later paused or rejected still counted as approved. Approved rows
// are now re-checked once a day, by both halves: the scheduler gate (fn_resilience_orphan_steps_due,
// scripts/sql/an_approved_whatsapp_template_is_rechecked_with_twilio_once_a_day.sql) and the watcher.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const src = readFileSync(new URL('../../supabase/functions/wa_templates_watch/index.ts', import.meta.url), 'utf8');
const gateSql = readFileSync(new URL('../sql/a_whatsapp_template_twilio_no_longer_has_is_missing_not_404.sql', import.meta.url), 'utf8');

test('the poll covers the undecided register rows the gate reads', () => {
  assert.match(src, /\[\.\.\.sids, \.\.\.extra\]/);
});

test('Twilio is asked in parallel, not one sid after another', () => {
  assert.match(src, /Promise\.all\(\[\.\.\.sids, \.\.\.extra\]\.map/);
});

test('no call to the pg_cron unschedule routine, which does not exist', () => {
  assert.doesNotMatch(src, /rpc\(\s*'cron_unschedule/);
});

test('an already-live channel is not re-announced', () => {
  assert.match(src, /allApproved && \(\(await sec\('wa_templates_ready'\)\)/);
});

test('an approved row is trusted only while confirmed within the re-check window', () => {
  // final verdicts (6 Oct 2026: 'missing' = Twilio 404 joins 'rejected') are never asked again
  assert.match(src, /const FINAL = new Set\(\['rejected', 'missing'\]\);/);
  // due: not final, and either undecided or approved-but-unconfirmed
  assert.match(src, /!FINAL\.has\(r\.status\) && \(r\.status !== 'approved' \|\| unconfirmed\(r\)\)/);
  // read from the register (not asked): final, or approved AND confirmed
  assert.match(src, /FINAL\.has\(r\.status\) \|\| \(r\.status === 'approved' && !unconfirmed\(r\)\)/);
});

test('the watcher and the scheduler gate use the same 20 hours', () => {
  const ms = src.match(/const RECHECK_MS = (\d+) \* 3600 \* 1000;/);
  assert.ok(ms, 'RECHECK_MS not found');
  const sqlArm = gateSql.match(/status not in \('rejected', 'missing'\)\s+and \(last_checked_at is null or last_checked_at < now\(\) - interval '(\d+) hours'\)/);
  assert.ok(sqlArm, 'the wa_templates arm no longer re-checks approved rows');
  assert.equal(Number(ms[1]), Number(sqlArm[1]));
});

test('a paused or rejected approval is written to the register and raises a finding', () => {
  assert.match(src, /approved_at: null, rejection_reason: x\.reason/);
  assert.match(src, /wasApproved\.has\(x\.sid\) \|\| \(x\.status === 'missing' && tracked\.has\(x\.sid\)\)\) && x\.status !== 'approved'/);
  // an HTTP code is never written as a status (6 Oct 2026: six register rows read "404")
  assert.match(src, /r\.status === 404 \? 'missing'/);
  assert.doesNotMatch(src, /j\?\.whatsapp\?\.status \|\| j\?\.status/);
  assert.match(src, /rpc\('fn_it_engineer_finding_upsert'/);
});

// The gate as written in the FILE, run in a transaction that always rolls back: with every other
// template confirmed just now, ONE approved row unconfirmed for 21 h must open the wa_templates gate,
// and confirming it must shut the gate again. On the previous body (undecided only) the first case
// reads false.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('a stale approved template opens the scheduler gate, a confirmed one does not', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const def = gateSql.match(/create or replace function public\.fn_resilience_orphan_steps_due\(\)[\s\S]*?\n\$fn\$;/)[0];
  let got;
  try {
    await sql(`${def}
      do $p$ declare a boolean; b boolean; c boolean; d boolean; v_sid text; begin
        if coalesce((select value from public.app_secrets where key = 'wa_templates_ready'), '') <> 'true' then
          raise exception 'CHK<<{"skip":"wa_templates_ready is not true, the flag arm holds the gate open"}>>';
        end if;
        update public.messaging_template set last_checked_at = now() where channel = 'whatsapp';
        a := (public.fn_resilience_orphan_steps_due()->>'wa_templates')::boolean;
        select sid into v_sid from public.messaging_template where channel = 'whatsapp' and status = 'approved' limit 1;
        if v_sid is null then raise exception 'CHK<<{"skip":"no approved template in the register"}>>'; end if;
        update public.messaging_template set last_checked_at = now() - interval '21 hours' where sid = v_sid;
        b := (public.fn_resilience_orphan_steps_due()->>'wa_templates')::boolean;
        update public.messaging_template set status = 'rejected' where sid = v_sid;
        c := (public.fn_resilience_orphan_steps_due()->>'wa_templates')::boolean;
        update public.messaging_template set status = 'missing' where sid = v_sid;
        d := (public.fn_resilience_orphan_steps_due()->>'wa_templates')::boolean;
        raise exception 'CHK<<%>>', jsonb_build_object('all_fresh', a, 'approved_stale', b, 'rejected_stale', c, 'missing_stale', d);
      end $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    got = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(got, 'probe committed instead of rolling back');
  if (got.skip) return;
  assert.deepEqual(got, { all_fresh: false, approved_stale: true, rejected_stale: false, missing_stale: false });
});
