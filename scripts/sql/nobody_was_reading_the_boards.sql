-- ============================================================================================
-- NOBODY WAS READING THE BOARDS
--
-- The final acceptance audit found two kernel boards RED on production while `npm test` was green
-- across 288 tests and PHASE_C_BUILDER_CLOSURE.md reported "headlines FAILED 0":
--
--   fn_kernel_trigger_state    active_autonomous_source_not_yet_routing_through_the_inbox  26 of 37
--   fn_kernel_retired_path_state  kernel_primitives_called_from_outside_the_kernel          1 of 9
--
-- Neither was a new failure. Both had been red since the increment that created them. The reason
-- nothing caught them is the whole finding: SIX OF THE SEVEN KERNEL BOARDS WERE READ BY NO TEST AND
-- NO CI JOB. They were written, deployed, and never opened. A board nobody reads is a comment.
--
--   fn_kernel_trigger_state           tests 0   ci 0
--   fn_kernel_retired_path_state      tests 0   ci 0
--   fn_kernel_source_cutover_state    tests 0   ci 0
--   fn_kernel_signal_state            tests 0   ci 0
--   fn_kernel_trace_integrity         tests 0   ci 0
--   fn_kernel_historical_repair_state tests 0   ci 0
--   fn_kernel_system_trace_state      tests 1   ci 0
--
-- DISCOVERY BY SIGNATURE, NOT BY LIST. A hard-coded list of boards would have exactly the defect it
-- is fixing the moment somebody adds board number twenty-two and forgets the list. Every board in
-- this estate is a zero-argument function returning (check_name, expected, actual, ok), so that
-- shape is what is searched for. A new board is watched from the moment it is deployed, without
-- anyone remembering to register it. Twenty-one exist today, including the two added this session.
--
-- WHY THIS RETURNS RESULTS RATHER THAN RAISING. Some boards are gates and must be all-ok. Others
-- are deliberately open-gap reports: kernel_k6_trace_ledger.sql states in its own header that
-- fn_kernel_trace_integrity carries every numerator and denominator over the FULL table with no
-- population filter, precisely so preserved orphan traces and the TRACE-SYSTEM-EXECUTION gap stay
-- visible — "the gap stays visible" is the design, and demanding zero there would be demanding the
-- disclosure be deleted. Sorting gate from report is a judgement about intent, so it lives in a
-- committed file next to the test that reads it, not in this function. This function's job is to
-- open every board and report, without deciding.
-- ============================================================================================

create or replace function public.fn_kernel_all_boards()
returns table(board text, check_name text, expected text, actual text, ok boolean)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $kab$
declare
  b record;
begin
  for b in
    select p.proname as fn
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.pronargs = 0
       and p.proargnames @> array['check_name','expected','actual','ok']
       -- IT DISCOVERED ITSELF. Written and applied without this line, and the first call recursed
       -- until the statement timeout killed it: this function returns exactly the shape it searches
       -- for, so it found itself, called itself, found itself again. Left as the reason the
       -- exclusion is by name rather than by a comment saying "don't add recursive boards".
       and p.proname <> 'fn_kernel_all_boards'
     order by p.proname
  loop
    board := b.fn;
    begin
      return query execute format(
        'select %L::text, x.check_name, x.expected, x.actual, x.ok from public.%I() x', b.fn, b.fn);
    exception when others then
      -- A BOARD THAT RAISES IS A FAILURE, NOT AN ABSENCE. fn_phase_c_invariants once raised 22007
      -- on every call after a column retype, which also took out fn_phase_c_baseline_drift. If that
      -- happens again it must read as red here rather than as a board that quietly returned nothing.
      check_name := 'BOARD_RAISED';
      expected   := 'the board returns rows';
      actual     := sqlstate || ' ' || sqlerrm;
      ok         := false;
      return next;
    end;
  end loop;
end
$kab$;

revoke execute on function public.fn_kernel_all_boards() from public;
grant  execute on function public.fn_kernel_all_boards() to service_role;
