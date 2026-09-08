import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- G13 — a count named "notifications written" that could not say whether anything was sendable
--
-- G11 gave the notification object the fixture stage it never had. The row it writes carries the
-- suppression the outbound door declares, at a status no sender selects, inside a transaction that
-- is aborted. The scenario factory then reported:
--
--     notifications_written_by_this_scenario   1
--
-- and the deliverable builder, which sums that across thirty drives and asserts zero, refused to
-- write its result: "notifications written 30 (must be 0)".
--
-- THE ASSERTION IS RIGHT AND IS NOT WEAKENED. What it is FOR is the property the Phase D hold rests
-- on: a fixture may not queue an outbound message. What it COUNTS is rows in a table, which is a
-- different thing, and the difference only became visible when one stage legitimately wrote there.
-- A count that cannot tell a queued message from a suppressed record is the same shape as a check
-- that reports on a subject other than the one it names.
--
-- So the factory now reports BOTH, and they are different questions:
--
--   notifications_written_by_this_scenario                rows written, all of them
--   deliverable_notifications_written_by_this_scenario    rows a sender would select
--
-- The second is the one that must be zero, and the builder asserts on it. The first stays in the
-- return object and in the deliverable, so a reader can still see that a row was written at all.
--
-- WHAT COUNTS AS DELIVERABLE IS DERIVED, NOT LISTED. A row is deliverable unless its status equals
-- the working_state declared by the fixture stage whose object's write map targets
-- public.notifications -- which is the same value fn_phase_d_object_write's outbound-door loop
-- forces and does not let a caller override. Change the suppression in one place and both the
-- writer and this count follow it; there is no second copy of the word to drift.
--
-- The check is strictly sharper than before: previously a scenario that wrote no row but enqueued a
-- deliverable one through some other path would have passed this counter, and a scenario that wrote
-- a suppressed record would have failed it. Now it fails exactly when something sendable exists.
--
-- Three anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let def = r[0].def;
const splice = (anchor, repl, what) => {
  const n = def.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  def = def.replace(anchor, repl);
};

splice(`  v_notif_id_before bigint;              -- G11: the high-water mark, so new rows are identifiable`,
`  v_notif_id_before bigint;              -- G11: the high-water mark, so new rows are identifiable
  v_notif_id_start  bigint;              -- G13: the same, for the whole scenario rather than one stage`,
  'G13 declaration');

splice(`  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label, 'fixture_run_id', v_fixture_run,`,
`  select coalesce(max(id),0) into v_notif_id_before from public.notifications;  -- reused as a bound

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label, 'fixture_run_id', v_fixture_run,`,
  'G13 return prologue');

splice(`    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,`,
`    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,
    -- G13. THE ONE THAT MUST BE ZERO. A row a sender would select is a queued outbound message; a
    -- row at the suppression the outbound door forces is a record. The suppression is read from the
    -- stage that declares it rather than written here, so there is no second copy of the word.
    'deliverable_notifications_written_by_this_scenario',
      (select count(*) from public.notifications n
        where n.id > coalesce(v_notif_id_start, 0)
          and n.status is distinct from (
            select st2.working_state from public.phase_d_fixture_stage st2
             where st2.object_id in (select wm3.object_id from public.phase_d_object_write_map wm3
                                      where wm3.target_relation = 'public.notifications')
             limit 1)),`,
  'G13 deliverable count');

// v_notif_id_start must be taken where v_notif_start is.
splice(`  select count(*) into v_notif_start from public.notifications;`,
`  select count(*) into v_notif_start from public.notifications;
  select coalesce(max(id),0) into v_notif_id_start from public.notifications;  -- G13`,
  'G13 start mark');

writeFileSync('scripts/sql/phase_d_g13_a_count_that_could_not_say_whether_anything_was_sendable.sql',
  HEAD + '\n' + def + '\n');
console.log('G13 written');
