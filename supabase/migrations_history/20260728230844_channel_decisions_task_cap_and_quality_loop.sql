-- ===========================================================================
-- 1. THE MESSAGING CHANNEL DECISION, made on evidence rather than deferred.
--
-- Measured 28 Jul 2026, 30-day window:
--     SMS sent .................. 0
--     WhatsApp outbound ......... 0
--     WhatsApp inbound runs ..... 6
--     Mobile/login OTP runs ..... 0
--     Twilio ............. CONFIGURED (so an autonomous agent COULD start sending)
--
-- sms_enabled -> OFF. Zero traffic in 30 days and no SMS step in the supplier
-- journey, but a live Twilio credential and agents gaining authority on Thursday.
-- That is pure downside: cost and reputation risk with no offsetting benefit. It
-- takes one row to switch back the moment a real use case appears.
--
-- wa_autoreply_enabled -> STAYS ON. There IS inbound WhatsApp. During a
-- supplier-acquisition phase, an unanswered supplier is worse than an imperfect
-- answer. It was only unsafe before because it had no rate limit; it now has one
-- (20/hour/sender), a no-model FAQ layer, and human escalation.
--
-- email_enabled / supplier_emails_enabled -> STAY ON. The invite campaign is the
-- entire launch. Non-negotiable.
-- ===========================================================================
update app_secrets set value='false', updated_at=now() where key='sms_enabled';

insert into founder_alerts (level, event, detail, channel)
values ('info','channel_policy_set',
 'SMS disabled ahead of the 30 Jul autonomy switch: 0 messages sent in 30 days, no SMS step in the supplier journey, but Twilio is configured and agents gain send authority on Thursday. WhatsApp auto-reply stays ON - there is real inbound and it is now rate-limited (20/hr/sender) with a no-model FAQ layer and human escalation. Email and supplier email stay ON; the invite campaign depends on them.',
 'system');

-- ===========================================================================
-- 2. OPEN_TASK_CAP: stop it silencing the departments that matter most.
--
-- dept_plan skips any department holding 5+ open tasks. Measured today that was
-- 8 of 13 departments, including procurement on 42 - the department that owns the
-- supplier gap the whole launch window exists to close.
--
-- Raising the flat cap is the wrong fix: the guard exists to stop unstarted work
-- piling up, and that is a real concern. The right fix is to count only what the
-- guard was actually protecting against - work that has been ASSIGNED and never
-- started - and to guarantee every department a voice at least weekly regardless.
-- ===========================================================================
create or replace function fn_dept_can_plan(p_dept_key text)
returns jsonb
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_stalled int; v_cap int := 5; v_last timestamptz;
begin
  -- Only ASSIGNED-but-never-run work counts as pile-up. Work in progress, work
  -- awaiting the founder, and work already attempted are not what the cap is for.
  select count(*) into v_stalled from org_tasks
   where dept_key = p_dept_key and status = 'assigned' and attempts = 0
     and created_at < now() - interval '48 hours';

  select max(created_at) into v_last from org_memory
   where scope = p_dept_key and kind = 'plan' and source = 'dept_plan';

  -- No department goes silent for more than a week, whatever its backlog. A
  -- department that cannot plan cannot improve, and that is the failure mode the
  -- autonomous-company design exists to prevent.
  if v_last is null or v_last < now() - interval '7 days' then
    return jsonb_build_object('can_plan', true, 'reason',
      'weekly floor: last self-plan ' || coalesce(v_last::text,'never') || ' - planning regardless of backlog',
      'stalled', v_stalled);
  end if;

  if v_stalled >= v_cap then
    return jsonb_build_object('can_plan', false, 'reason',
      v_stalled || ' tasks assigned over 48h ago and never attempted. Execution is behind planning; drain before adding.',
      'stalled', v_stalled);
  end if;

  return jsonb_build_object('can_plan', true, 'reason',
    v_stalled || ' stalled task(s), under the cap of ' || v_cap, 'stalled', v_stalled);
end $$;

revoke execute on function fn_dept_can_plan(text) from public, anon, authenticated;

-- ===========================================================================
-- 3. QUALITY SCORING -> ROUTING. Close the loop so cheap models earn promotion
--    on evidence instead of staying cheap on faith.
-- ===========================================================================
create table if not exists model_outcome (
  id           bigint generated always as identity primary key,
  occurred_at  timestamptz not null default now(),
  fn           text,
  task_class   text not null,
  model_used   text not null,
  tier         text,
  ok           boolean not null,          -- did the caller get a usable answer
  parse_ok     boolean,                   -- did structured output parse
  latency_ms   integer,
  cost_usd     numeric,
  note         text
);
create index if not exists model_outcome_class_idx on model_outcome (task_class, model_used, occurred_at desc);
alter table model_outcome enable row level security;
revoke all on model_outcome from public, anon, authenticated;

-- Score each model per task class from what actually happened.
create or replace function fn_model_benchmark()
returns table (task_class text, model_used text, runs bigint, success_rate numeric,
               avg_cost_usd numeric, verdict text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with s as (
    select o.task_class, o.model_used,
           count(*) as runs,
           round(avg(case when o.ok and coalesce(o.parse_ok, true) then 1.0 else 0.0 end), 4) as success_rate,
           round(avg(o.cost_usd)::numeric, 6) as avg_cost_usd
    from model_outcome o
    where o.occurred_at > now() - interval '30 days'
    group by 1, 2
    having count(*) >= 20   -- never judge a model on a handful of runs
  )
  select s.task_class, s.model_used, s.runs, s.success_rate, s.avg_cost_usd,
         case
           when s.success_rate >= 0.95 then 'GOOD - safe to keep or promote for this class'
           when s.success_rate >= 0.85 then 'ACCEPTABLE - watch'
           else 'POOR - this class needs a stronger tier'
         end
  from s order by s.task_class, s.success_rate desc;

  -- Feed the score back onto the registry so routing can see it.
  update model_registry r set quality_score = q.sr, updated_at = now()
  from (
    select o.model_used, round(avg(case when o.ok and coalesce(o.parse_ok,true) then 1.0 else 0.0 end),4) sr
    from model_outcome o where o.occurred_at > now() - interval '30 days'
    group by 1 having count(*) >= 20
  ) q
  where r.model_id = q.model_used;
end $$;

revoke execute on function fn_model_benchmark() from public, anon, authenticated;

-- Act on the evidence: demote a model that is failing a class, and raise the
-- finding rather than silently degrading quality.
create or replace function fn_model_autoswitch()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r record; v_new text; v_n int := 0;
begin
  for r in
    select o.task_class, o.model_used,
           avg(case when o.ok and coalesce(o.parse_ok,true) then 1.0 else 0.0 end) sr, count(*) n
    from model_outcome o
    where o.occurred_at > now() - interval '14 days'
    group by 1,2 having count(*) >= 20
       and avg(case when o.ok and coalesce(o.parse_ok,true) then 1.0 else 0.0 end) < 0.85
  loop
    -- only act if this model is still the primary for that class
    if not exists (select 1 from model_policy p where p.task_class = r.task_class
                    and p.model_primary = r.model_used and p.active) then continue; end if;

    select mr.model_id into v_new from model_registry mr
     join model_registry cur on cur.model_id = r.model_used
     where mr.active and mr.approved and mr.in_per_mtok_usd > cur.in_per_mtok_usd
     order by mr.in_per_mtok_usd asc limit 1;
    if v_new is null then continue; end if;

    update model_policy set model_primary = v_new where task_class = r.task_class and active;
    v_n := v_n + 1;

    insert into founder_alerts (level, event, detail, channel)
    values ('warn','model_autoswitched',
      'Task class "' || r.task_class || '" was failing on ' || r.model_used || ' (' ||
      round(r.sr*100,1) || '% success over ' || r.n || ' runs, floor 85%). Promoted to ' || v_new ||
      '. Cheaper is only correct while it works; this is the loop that checks.', 'system');

    insert into org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder)
    values ('it', left('Model auto-switched for ' || r.task_class, 200),
      'Automatic promotion after measured failure. Class: ' || r.task_class ||
      E'\nWas: ' || r.model_used || ' at ' || round(r.sr*100,1) || '% success over ' || r.n || ' runs' ||
      E'\nNow: ' || v_new ||
      E'\n\nReview whether the prompt is at fault rather than the model - a badly specified task fails on every tier, and promoting it just costs more.',
      'proposed','supervised','analysis', false);
  end loop;
  return v_n;
end $$;

revoke execute on function fn_model_autoswitch() from public, anon, authenticated;

select cron.schedule('model_benchmark_daily','25 4 * * *', $$ select fn_model_benchmark() $$);
select cron.schedule('model_autoswitch_daily','35 4 * * *', $$ select fn_model_autoswitch() $$);