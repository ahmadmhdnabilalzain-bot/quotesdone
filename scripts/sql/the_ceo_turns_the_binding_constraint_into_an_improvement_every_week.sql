-- THE CEO TURNS THE BINDING CONSTRAINT INTO AN IMPROVEMENT EVERY WEEK — AN IDEA WITH AN OWNER AND A DATE.
--
-- Assigned: ceo. 24 Sep 2026. Seat audit GAPS.md, CEO gap 2 (ledger 983; founder instructions 10, 27, 638: "what
-- Elon Musk does for Tesla", "not a yes/no bot"). Approved job description, weekly: "Write at least one reasoned idea
-- to improve the company ... Delegate it with an owner and a date."
--
-- ══ MEASURED, 24 Sep 2026 ═════════════════════════════════════════════════════════════════════════════
--   * ceo.improvement (the_ceo_runs_the_company_on_the_founders_year_one_targets.sql, #923) proposes from three
--     sources: a metric behind its path on 7 of 14 days, a lesson in seat_case_memory, a finding seen 3+ times.
--     All three wait for something to go wrong first.
--   * public.ceo_plan names the binding constraint every day (latest row 10, 24 Sep: stage 'invitations' since
--     22 Sep, lever 'founder_reserved', held because the campaign gate is the founder's). When the lever is
--     reserved, fn_ceo_plan_act gives no seat any order, correctly — and nothing proposes what the company can do
--     about the constraint WITHOUT the reserved decision. The constraint was read and nobody acted on it.
--
-- ══ WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════
--   ceo.constraint_lever, weekly (fn_ceo_constraint_lever): reads the latest ceo_plan and, for the binding stage,
--   opens ONE improvement through the existing fn_ceo_improvement_open (so it gets the CEO task, the
--   ceo.improvement handoff to the owner seat and the existing tracking) from a coded lever table
--   (ceo_constraint_lever): per stage, the step the company can move that is NOT the reserved decision, the seat
--   that owns it (the founder's 24 Sep ownership map) and the measure that proves it. The evidence carries the
--   plan row, the reading and a due date 14 days out. One proposal per run of a constraint; a constraint still
--   binding at 14 days gets a second, escalated one. It closes itself when the plan's binding stage moves on.
--   On plan, nothing binds and nothing is proposed from here (the other three sources still run).
--
-- NOT CHANGED: fn_ceo_improvement_sweep and its sources, fn_ceo_plan_tick and its directives. Code only: the lever
-- is chosen by the stage key the plan wrote; nothing reads text, nothing calls a model. The ideas themselves are
-- a senior operator's standing levers, written once here where an auditor can read and change them.
--
-- Pending: scripts/sql/pending/the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.txt.
-- Needs the_ceo_runs_the_company_on_the_founders_year_one_targets.sql (ceo_improvement).

alter table public.ceo_improvement drop constraint if exists ceo_improvement_source_kind_check;
alter table public.ceo_improvement add constraint ceo_improvement_source_kind_check
  check (source_kind in ('recurring_miss', 'month_miss', 'lesson', 'recurring_finding', 'binding_constraint',
                         -- the CEO's other two sources, opened by their own duties and closed by them:
                         -- the_ceo_holds_the_marketing_seat_to_its_month_plan_date.sql, the_ceo_audits_every_seat_each_quarter.sql
                         'marketing_plan_late', 'seat_audit'));

create table if not exists public.ceo_constraint_lever (
  stage      text primary key,
  owner_seat text not null references public.org_role (role_id),
  proposal   text not null check (btrim(proposal) <> ''),
  measure    text not null check (btrim(measure) <> '')
);
alter table public.ceo_constraint_lever enable row level security;
drop policy if exists ceo_constraint_lever_service_role_only on public.ceo_constraint_lever;
create policy ceo_constraint_lever_service_role_only on public.ceo_constraint_lever as permissive for all to public using (false) with check (false);
revoke all on public.ceo_constraint_lever from anon, authenticated;

insert into public.ceo_constraint_lever (stage, owner_seat, proposal, measure) values
  ('deliverability', 'customer_support',
   'Bounces bind the funnel. Take every address that bounced in the last 7 days out of the queue, re-verify the list the next batch draws from before it is sent, and report the bounce rate per source list so the worst source is dropped.',
   'bounce_pct_7d below 5 %'),
  ('invitations', 'sales_engineer',
   'Invitations bind the funnel. While the campaign switch is the founder''s, grow what needs no switch: every supplier who started a registration and did not submit is taken through it one by one, and each registered supplier is asked for the names of two suppliers in another trade.',
   'registrations_submitted this month against the path'),
  ('registrations', 'sales_engineer',
   'Registrations bind the funnel. Find the registration step where most suppliers stop (started against submitted, per step) and remove the friction in that one step; send the day-2 and day-6 reminders with the exact field that is missing.',
   'registrations_submitted this month against the path'),
  ('verification', 'sales_engineer',
   'Verification binds the funnel. Every submitted registration older than 24 hours is decided today; for each one missing a document, the supplier is told exactly which document and why, the same day.',
   'stranded_submissions at 0 and registrations_verified against the path'),
  ('demand', 'marketing',
   'Customer requests bind the funnel. Put the organic effort on the trades where supply already quotes (supply_gap closed), and measure requests per post by trade so the next month''s calendar follows what converts.',
   'inquiries_posted against the path'),
  ('quotes', 'sales_engineer',
   'Quotes bind the funnel. For each request under three quotes after 48 hours, widen the invitation inside the exact trade to every matchable supplier and chase the ones who opened it and did not quote.',
   'quote_coverage_pct against the path'),
  ('reveals', 'sales_engineer',
   'Reveals bind the funnel. Follow up every comparison report within 24 hours with the customer: what is stopping the decision, and whether a clarified specification would change the ranking.',
   'reveals_paid against the path')
on conflict (stage) do update set owner_seat = excluded.owner_seat, proposal = excluded.proposal, measure = excluded.measure;

create or replace function public.fn_ceo_constraint_lever()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ceo_plan; l public.ceo_constraint_lever; v_id bigint; v_ref text; v_level int; r record; n_closed int := 0;
begin
  select * into p from public.ceo_plan order by plan_date desc, id desc limit 1;

  -- tracked to done: the binding stage moved on, so the constraint the idea was for is no longer the one that binds
  for r in select i.* from public.ceo_improvement i where i.source_kind = 'binding_constraint' and i.status in ('open', 'assigned') loop
    if p.id is not null and p.stage is distinct from r.evidence->>'stage' then
      perform public.fn_ceo_improvement_close(r.id, format('The binding constraint moved from %s to %s (ceo_plan %s, %s).',
        r.evidence->>'stage', p.stage, p.id, p.plan_date));
      n_closed := n_closed + 1;
    end if;
  end loop;

  if p.id is null or p.stage is null or p.stage = 'on_plan' then
    return jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'proposed', null, 'closed', n_closed);
  end if;
  select * into l from public.ceo_constraint_lever where stage = p.stage;
  if l.stage is null then
    -- a stage with no lever is a gap in this table, recorded for the CEO rather than silently skipped
    perform public.fn_it_engineer_finding_upsert('ceo:no_constraint_lever:' || p.stage,
      'The binding stage ' || p.stage || ' has no lever in ceo_constraint_lever', 'public.ceo_constraint_lever', 'agent_facing', 1,
      jsonb_build_object('stage', p.stage, 'owner_seat', 'ceo'), '{}'::text[], array['which step the company can move for this stage'], 'ceo');
    return jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'proposed', null, 'closed', n_closed, 'error', 'no lever');
  end if;
  v_level := case when p.plan_date - p.constraint_since >= 14 then 2 else 1 end;
  v_ref := p.stage || ':' || p.constraint_since || ':L' || v_level;
  v_id := public.fn_ceo_improvement_open('binding_constraint', v_ref, l.owner_seat,
    case when v_level = 2 then format('ESCALATED: %s has bound the funnel for %s days. ', p.decision->>'label', p.plan_date - p.constraint_since) else '' end
      || l.proposal || ' Owner: ' || l.owner_seat || '. Due: ' || to_char(p.plan_date + 14, 'DD Mon YYYY') || '. Proven by: ' || l.measure || '.',
    jsonb_build_object('stage', p.stage, 'plan_id', p.id, 'constraint_since', p.constraint_since, 'level', v_level,
      'lever', p.decision->>'lever', 'held_because', p.decision->>'held_because',
      'month_to_date', p.funnel->'month_to_date', 'last_7_days', p.funnel->'last_7_days',
      'measure', l.measure, 'due_on', p.plan_date + 14));
  return jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'level', v_level, 'proposed', v_id, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_constraint_lever() from public, anon, authenticated;
grant execute on function public.fn_ceo_constraint_lever() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.constraint_lever', 'ceo', interval '7 days', 'fn_ceo_constraint_lever',
   'Every week the binding constraint of the plan becomes one improvement the company can make without the reserved decision, with an owner seat, a due date and the measure that proves it.',
   'scripts/sql/the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
