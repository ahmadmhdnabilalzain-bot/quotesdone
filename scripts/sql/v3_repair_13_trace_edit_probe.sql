-- V3 REMEDIATION — a probe the regression suite can trust.
--
-- The first regression run reported "a sealed trace refuses an evidence edit: NOT refused" while a
-- hand-run aborted-transaction probe on the same database showed it plainly BLOCKED. The guard was
-- working; the CHECK was wrong. It decided the verdict by string-matching the exception text that
-- came back through the management API, and that is a brittle way to learn anything - it fails the
-- moment the wrapper changes its error shape, and it fails in the direction that reports a healthy
-- guard as dead.
--
-- This function answers the question in STATE instead: it attempts the forbidden edit inside its
-- own subtransaction, catches the refusal, and returns a boolean. Nothing is left behind either
-- way, and there is no error string to parse.

begin;

create or replace function public.fn_trace_edit_is_blocked(p_id uuid)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare v_before numeric; v_after numeric;
begin
  select confidence into v_before from decision_trace where id = p_id;
  begin
    -- The edit that must be refused on a sealed trace.
    update decision_trace set confidence = coalesce(v_before, 0) + 0.01 where id = p_id;
  exception when others then
    return true;                       -- refused, which is the correct behaviour
  end;
  select confidence into v_after from decision_trace where id = p_id;
  -- Not refused. Put it back so the probe leaves nothing behind, then report the defect honestly.
  update decision_trace set confidence = v_before where id = p_id;
  return v_after is not distinct from v_before;
end $$;
revoke all on function public.fn_trace_edit_is_blocked(uuid) from public;
grant execute on function public.fn_trace_edit_is_blocked(uuid) to service_role;

commit;
