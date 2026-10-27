-- A SPAM SEED HOLDS THE INVITATION BATCH (19 Oct 2026; it_engineer, on the coordinator's go). Ledger 1113 (5 Oct,
-- "make sure no emails go to junk or spam") supersedes ledger 1001 (a measured junk placement let the batch go).
-- Only fn_invite_placement_gate changes: spam -> 'fail:spam'; inbox and elsewhere (Gmail Promotions) pass; the
-- it_engineer finding and marketing handoff are still filed by fn_invite_placement_settle. Same text as the owning
-- file the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql, applied alone so the rest of
-- that file is not replayed. CREATE OR REPLACE keeps grants; the revoke is repeated anyway.
create or replace function public.fn_invite_placement_gate(p_day date default null, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := coalesce(p_day, (p_now at time zone 'Asia/Dubai')::date);
  r public.invite_placement_check; v text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;
  if r.dubai_day is null then
    if p_now < public.fn_invite_placement_cutoff(v_day) then return 'wait'; end if;
    if public.fn_invite_placement_day_closed(p_now) is null then
      perform public.fn_invite_placement_finding(v_day, 'no_check',
        'no inbox placement check ran on ' || v_day || ', an open sending day',
        jsonb_build_object('checked_at', p_now, 'sender', public.fn_invite_placement_sender()));
    end if;
    return 'fail:no_check';
  end if;
  v := r.verdict;
  if v = 'pending' then
    if p_now < public.fn_invite_placement_cutoff(v_day) then return 'wait'; end if;
    v := public.fn_invite_placement_settle(v_day, p_now);
  end if;
  -- Ledger 1113 (5 Oct 2026, 'make sure no emails go to junk or spam') supersedes 1001: a spam seed holds the batch
  -- (settle has already filed the it_engineer finding and the marketing handoff); Gmail Promotions ('elsewhere') passes.
  if v = 'spam' then return 'fail:spam'; end if;
  if v not in ('inbox', 'elsewhere') then return 'fail:' || v; end if;
  if public.fn_invite_placement_sender() is distinct from r.from_address then return 'fail:from_changed'; end if;
  return 'pass';
end
$fn$;
revoke execute on function public.fn_invite_placement_gate(date, timestamptz) from public, anon, authenticated;
