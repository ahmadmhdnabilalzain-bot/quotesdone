// A WAL FAILURE THE ARCHIVER HAS ALREADY RETRIED PAST RAISES NO ALARM (it_engineer, 27 Oct 2026).
//
// scripts/sql/a_wal_failure_the_archiver_has_already_retried_past_raises_no_alarm.sql. Fails when:
//   1. (static) the FAILING branch of fn_it_detect's WAL detector stops requiring that the failure is still the newest
//      archiver event, or the STALLED branch that catches a real stop is gone;
//   2. (production, rolled back) fn_it_detect raises backup_chain:wal_archiving_failing while pg_stat_archiver shows a
//      segment archived after the last failure - or does NOT raise it while the failure is the newest event in the window.
//
//   node --test scripts/checks/a_wal_failure_the_archiver_has_already_retried_past_raises_no_alarm.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/a_wal_failure_the_archiver_has_already_retried_past_raises_no_alarm.sql';
const src = readFileSync(join(REPO, FILE), 'utf8').replace(/--[^\n]*/g, '');

test('the failure must be the newest archiver event, and a real stop is still caught as STALLED', () => {
  assert.match(src, /v_arch_fail_at > v_now - c_win\s+and \(v_arch_at is null or v_arch_fail_at >= v_arch_at\) then\s+v_key\s+:= 'backup_chain:wal_archiving_failing'/);
  assert.match(src, /elsif v_arch_age > 60 then\s+v_key\s+:= 'backup_chain:wal_archiving_stalled'/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back: the alarm follows the archiver\'s newest event', { skip: hasToken ? false : 'no Supabase management token', timeout: 300000 }, async () => {
  const pre = pendingNotes().has(FILE) ? readFileSync(join(REPO, FILE), 'utf8') + '\n;\n' : '';
  const rows = await replaySql(pre + `
;select (select jsonb_build_object('failed', last_failed_time, 'archived', last_archived_time,
                                   'failure_is_newest_in_window', last_failed_time is not null and last_failed_time > now() - interval '60 minutes'
                                                                  and (last_archived_time is null or last_failed_time >= last_archived_time))
           from pg_stat_archiver) as archiver,
        public.fn_it_detect(null, false)::text like '%backup_chain:wal_archiving_failing%' as fired`,
  { label: 'wal alarm', rows: true, retry: false });
  const { archiver, fired } = rows[0];
  assert.equal(fired, archiver.failure_is_newest_in_window,
    `wal_archiving_failing fired=${fired} but the archiver says ${JSON.stringify(archiver)}`);
});
