-- ROLLBACK for phase_d_m02_open_and_close_the_committed_scenario.sql
--
-- Refuses while a scenario is still OPEN: dropping the only routine that can reverse a committed
-- fixture, while one is committed, is how the residue this operation exists to prevent gets left.
do $down$
declare v_n int;
begin
  select count(*) into v_n from public.phase_d_committed_scenario where state = 'OPEN';
  if v_n > 0 then
    raise exception 'phase_d_m02 down: % scenario(s) are still OPEN; close them first', v_n;
  end if;
end $down$;
drop function if exists public.fn_phase_d_committed_scenario_close(bigint);
drop function if exists public.fn_phase_d_committed_scenario_open(jsonb);
