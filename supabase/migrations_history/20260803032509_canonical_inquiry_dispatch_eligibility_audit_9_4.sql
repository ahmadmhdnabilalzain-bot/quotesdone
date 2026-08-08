-- Audit 9.4 "Canonical dispatch_eligible gate" — FAIL, "built but not on the live path".
-- v_workstream_dispatch.dispatch_eligible exists and is correct:
--   active AND no missing mandatory answers AND no unresolved conflicts AND all required
--   workstream gates satisfied.
-- Nothing read it. dispatch_inquiry decided on inquiries.rfq_ready alone.
--
-- The view is keyed by workstream. An inquiry reaches it through
-- inquiries -> inquiry_workstream_group -> inquiry_workstream, so this function resolves an
-- inquiry to its ACTIVE workstreams and requires every one of them to be eligible.
--
-- Deliberate semantics for an inquiry with NO workstream rows: eligible, reason
-- 'no_workstreams'. Workstreams are created for multi-trade and turnkey work; requiring them
-- unconditionally would block every simple single-trade RFQ, which is not what the check is for.
-- The gate binds exactly where the interpretation engine has something to say.

create or replace function public.fn_inquiry_dispatch_eligible(p_inquiry_id uuid)
returns jsonb
language sql stable security definer set search_path to 'public','pg_temp' as $$
  with ws as (
    select d.workstream_id, d.trade_key, d.dispatch_eligible, d.mandatory_complete,
           d.no_unresolved_conflict, d.gates_passed, d.missing_mandatory, d.blocked_by
    from public.inquiry_workstream_group g
    join public.inquiry_workstream w on w.group_id = g.id
    join public.v_workstream_dispatch d on d.workstream_id = w.id
    where g.inquiry_id = p_inquiry_id and w.active
  )
  select case
    when (select count(*) from ws) = 0
      then jsonb_build_object('eligible', true, 'reason', 'no_workstreams', 'workstreams', 0)
    when (select bool_and(dispatch_eligible) from ws)
      then jsonb_build_object('eligible', true, 'reason', 'all_workstreams_eligible',
                              'workstreams', (select count(*) from ws))
    else jsonb_build_object(
      'eligible', false,
      'reason', 'workstream_not_dispatch_eligible',
      'workstreams', (select count(*) from ws),
      'blocking', (select jsonb_agg(jsonb_build_object(
          'workstream_id', workstream_id, 'trade', trade_key,
          'mandatory_complete', mandatory_complete,
          'no_unresolved_conflict', no_unresolved_conflict,
          'gates_passed', gates_passed,
          'missing_mandatory', to_jsonb(missing_mandatory),
          'blocked_by', to_jsonb(blocked_by)))
        from ws where not dispatch_eligible))
  end;
$$;

revoke execute on function public.fn_inquiry_dispatch_eligible(uuid) from public, anon, authenticated;;
