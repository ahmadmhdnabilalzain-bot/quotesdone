-- PROBE for the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.sql. Seat: ceo. Never applied:
-- it always raises CHK<<...>> and rolls back. It runs the launch-plan duty as of 2 Dec 2026 on the real 2027-01 plan
-- document (rolled back with everything else) and asserts the CEO decided it, nobody was mailed, and the brief carries it.
do $probe$
declare r jsonb; d public.marketing_plan_doc; v_bad text := ''; v_notes int; v_lines text;
begin
  select count(*) into v_notes from public.notifications;
  update public.marketing_plan_doc set status = 'draft' where kind = 'launch_plan' and period = date '2027-01-01';
  r := public.fn_marketing_launch_plan_run(date '2026-12-02');
  select * into d from public.marketing_plan_doc where kind = 'launch_plan' and period = date '2027-01-01';
  if d.status <> 'approved' then v_bad := v_bad || ' status=' || d.status || ' ' || coalesce(d.body->'ceo_review'->>'reasons', ''); end if;
  if d.body->'ceo_review'->>'decided_by' is distinct from 'ceo' then v_bad := v_bad || ' not-decided-by-ceo'; end if;
  if jsonb_array_length(coalesce(d.body->'launch_trades', '[]')) = 0 then v_bad := v_bad || ' no-launch-trades'; end if;
  if d.body->>'rule' ilike '%every category%' then v_bad := v_bad || ' all-categories-rule'; end if;
  if (select count(*) from public.notifications) <> v_notes then v_bad := v_bad || ' mailed'; end if;
  v_lines := public.fn_founder_brief_ceo_lines(now() - interval '1 hour', now() + interval '1 hour');
  if v_lines !~ 'January launch plan approved' then v_bad := v_bad || ' brief-line-missing'; end if;
  -- a rerun the same day does not decide or tell twice
  r := public.fn_marketing_launch_plan_run(date '2026-12-02');
  if (select count(*) from public.ceo_brief_line where source = 'fn_ceo_decide_launch_plan') <> 1 then v_bad := v_bad || ' told-twice'; end if;
  -- a paid channel while paid is not allowed is sent back with its reason, never approved
  update public.marketing_plan_doc set status = 'change_requested', body = body || jsonb_build_object('channels', jsonb_build_array('organic social', 'paid Meta within the ad cap'))
   where id = d.id;
  r := public.fn_ceo_decide_launch_plan(d.id);
  if not public.fn_marketing_paid_allowed() and r->>'status' <> 'change_requested' then v_bad := v_bad || ' paid-approved'; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK the CEO approved the January plan (%), no mail, one brief line; paid sent back: %>>', d.body->'ceo_review'->'reasons', r->'reasons';
end $probe$;
