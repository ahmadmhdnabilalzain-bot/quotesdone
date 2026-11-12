// node --test scripts/checks/an_approved_supplier_whose_new_licence_is_never_read_is_handed_on.test.mjs
// Review of #1982, L3-1 (12 Nov 2026, sales_engineer; founder rulings 1663, 1664): an APPROVED supplier keeps the accepted licence
// reading while his new file is read, and the re-read sweep stops after 8 tries (about 42 h). The three-day hand-over to the ceo seat
// read approval_status = 'pending' only, so such a supplier stayed approved on the old reading for good, the new file unread and
// nobody told. This fails if the hand-over stops selecting approved suppliers whose licence our reader failed on for three days,
// stops keeping "once" per licence file, opens itself to callers, or is no longer called by the daily decider.
// The behaviour is proved by the file's probe on production (scripts/ci/rehearse_sql.mjs, rolled back).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const F = 'scripts/sql/an_approved_supplier_whose_new_licence_is_never_read_goes_to_the_ceo_seat.sql';

test('an approved supplier whose new licence is unread for three days is put to the ceo seat once per file, by the daily decider', () => {
  const sql = R(F);
  const body = sql.slice(sql.indexOf('function public.fn_sales_engineer_hands_unread_approved_licences_to_ceo'), sql.indexOf('revoke all on function'));
  assert.match(body, /l\.approval_status = 'approved'/);
  assert.match(body, /l\.licence_read_state = 'ours_failed'/);
  assert.match(body, /l\.licence_read_failed_since <= p_at - interval '3 days'/);
  assert.match(body, /v_key := 'approved_licence_unread:' \|\| r\.license_doc_path;/, 'once is not kept per licence file');
  assert.match(body, /a\.kind = 'held_registration_for_ceo' and a\.target_id = r\.id::text and a\.detail ->> 'clock' = v_key/);
  assert.match(body, /set search_path to 'public', 'pg_temp'/);
  assert.match(sql, /revoke all on function public\.fn_sales_engineer_hands_unread_approved_licences_to_ceo\(timestamptz, bigint\) from public, anon, authenticated;/);
  assert.doesNotMatch(body, /fn_sales_engineer_writes|insert into public\.notifications/, 'the hand-over must not message the supplier');
  assert.match(sql, /v_approved_to_ceo := public\.fn_sales_engineer_hands_unread_approved_licences_to_ceo\(p_at\);/, 'the daily decider does not call it');
});
