-- THE INVITE CAP MOVED AND THE ALLOCATION LEDGER NEVER HEARD ABOUT IT
--
-- Row #3 §23 wants resources reallocated across three named classes and reads 1 of 3: only
-- `ai_budget_aed` has ever appeared in allocation_change. "Supplier onboarding capacity" is scored
-- MISSING — and the company reallocates it regularly.
--
-- `invite_daily_cap` IS supplier onboarding capacity. fn_invite_ramp moves it on a measured signal
-- and a stated policy: 10 -> 20 on 6 Aug ("healthy: cap 10->20"), 20 -> 10 on 7 Aug ("throttle: 7d
-- bounce 13.3% >= 5%"). Those are reallocations by any reading. They were written to app_secrets and
-- to an agent_runs note, and never to allocation_change, which is where this company keeps its
-- allocation history — so the ledger showed one resource class moving when two were.
--
-- A TRIGGER RATHER THAN AN ELEVEN-THOUSAND-CHARACTER PATCH. fn_invite_ramp is 11,026 characters and
-- adding one insert would mean reproducing all of it; reconstructing a large routine to add a clause
-- is how a 13,455-character sweep nearly lost its STALLED accounting on 14 Aug. A trigger on the
-- value itself is smaller, cannot drift from the function, and catches the change whoever makes it —
-- including a manual edit or a future ramp rewrite.
--
-- IT DOES NOT BACKFILL. The 6 and 7 August moves are not written retrospectively. §23 therefore
-- stays at 1 of 3 today and becomes 2 of 3 the next time the cap actually moves — which the ramp
-- will do once the 7-day bounce window clears the pre-12-August role-address sends around 19 Aug and
-- it warms up again. Writing yesterday's reallocations into the ledger tonight to make a check go
-- green is exactly the fabrication this session has refused everywhere else.
--
-- The remaining class, "marketing budget to channels", is NOT built and is not buildable honestly:
-- department_budget carries the AI budget per department (fn_what_if reads it as such), marketing
-- holds AED 400, and there is one paid channel sitting at AED 0 spend and 0 results. An allocator
-- across channels would have no performance signal to move on and could only emit arbitrary moves
-- dressed as decisions.

create or replace function public.trg_invite_cap_allocation()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_old numeric; v_new numeric;
begin
  if new.key <> 'invite_daily_cap' then return new; end if;

  -- A non-numeric or absent value is not a reallocation; nothing is recorded rather than guessed.
  begin
    v_old := nullif(btrim(coalesce(old.value, '')), '')::numeric;
    v_new := nullif(btrim(coalesce(new.value, '')), '')::numeric;
  exception when others then
    return new;
  end;
  if v_old is null or v_new is null then return new; end if;

  -- A move to the same number moved nothing. s23-reallocation-policy-cited counts a no-op as a
  -- finding, correctly, so one is never written.
  if v_old is not distinct from v_new then return new; end if;

  insert into public.allocation_change (resource, subject, from_value, to_value, reason, policy)
  values ('supplier_onboarding_capacity', 'invite_daily_cap', v_old, v_new,
          case when v_new > v_old
               then 'Daily supplier-invite capacity raised from ' || v_old || ' to ' || v_new
                    || '. Deliverability is inside tolerance, so more onboarding capacity is released.'
               else 'Daily supplier-invite capacity reduced from ' || v_old || ' to ' || v_new
                    || '. Bounce rate is above tolerance, so onboarding capacity is withdrawn to '
                    || 'protect the sending domain.' end,
          'invite ramp: capacity follows the measured 7-day bounce rate against invite_max_bounce_rate, '
          || 'warming at most 2x per day, floored at the base cap and ceilinged by the volume stage');
  return new;
end
$function$;

drop trigger if exists a50_invite_cap_allocation on public.app_secrets;
create trigger a50_invite_cap_allocation
  after update on public.app_secrets
  for each row
  when (old.value is distinct from new.value)
  execute function public.trg_invite_cap_allocation();

revoke all on function public.trg_invite_cap_allocation() from public, anon, authenticated;
