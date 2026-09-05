-- change_deployment STEPS 1, 8 AND 9 ARE PERFORMED, NOT DOCUMENTED (MASTER_PLAN A1 / §4.2), 5 Sep 2026.
--
-- MEASURED on production before this file (28 change_deployment runs, all 'done' on 4 Sep):
--   step 1 "Change proposed, with the metric it should move and the baseline captured"   — closed by the
--          dispatcher applying the step-1 playbook: 28 runs, 28 distinct deploy payloads, 1 distinct
--          deliverable. No baseline was ever captured; the playbook's own prose was stored as the work.
--   step 8 "Promote to production" — closed by executor:resilience_ping, a self-heal probe that knows
--          nothing about the deploy it was supposedly promoting.
--   step 9 "Monitor and grade the outcome against the baseline; reverse if worse" — closed by the
--          dispatcher with the step-9 playbook: 1 distinct deliverable across 28 runs, no window read,
--          no grade, nothing compared to anything. Its registered executor (recommend -> analytics_recommend)
--          runs on the held paid model.
--
-- WHAT PERFORMING EACH STEP MEANS FOR THIS COMPANY, decided here and enforced in code below:
--   step 1  The change IS the deploy the event describes (context.functions, context.ref, context.at).
--           The metric it should move is each deployed function's failure count: errored agent_runs
--           (agent = slug) plus failed kernel traces (phase_c_system_execution.result='failed' for a cron
--           whose command calls /functions/v1/<slug>). The baseline is that metric over the 7 days ENDING
--           at context.at, read now and stored on the step so step 9 has a number to grade against.
--   step 8  Promotion is already true when deploy.completed fires: scripts/deploy_functions.mjs emits it
--           only after reading every function's version back from the management API. The determination
--           records the promoted slugs and the verification the emitter carried (context.verified, added
--           to the payload on 5 Sep; an older event says so instead of inventing one).
--   step 9  The outcome is graded over the window [context.at, now], at least 60 minutes long (the
--           executor DEFERS through fn_action_invoke_rpc until the window has elapsed; it never grades a
--           4-minute window and never closes early), capped at 24h, against step 1's baseline (recomputed
--           from the same predicate if step 1 was closed by the dispatcher before this file). Rates are
--           per hour. worse = post failures >= 3 and post rate > 1.5x baseline rate; improved = baseline
--           failures >= 3 and post rate < 0.5x baseline rate; otherwise no_change. On 'worse' the
--           reversal is RECOMMENDED as an org_task for Platform & Reliability (product_eng) naming the
--           route (redeploy the previously committed bundle for each slug). It is never performed here:
--           reversing a production deploy is a gated action for the Platform lead.
--
-- A step that cannot be determined FAILS with a readable reason (a mis-targeted ref, an event with no
-- function slugs): the sweep settles it 'failed' and the run says which step and why. Never a fake close.
-- Steps 2-7 keep their executors (qa_suite, resilience_ping, knowledge_exam): each runs a real check on
-- production, needs no model, and was settling before this file.
--
-- WIRING: three org_action_executor rows (kind rpc, one target), and workflow_step rows 1, 8, 9 of
-- change_deployment re-pointed at them. fn_workflow_step_sweep queues them (low/advisory_safe/reversible,
-- no model), fn_action_invoke_rpc calls the target with the step's request, the sweep settles the step
-- with the target's result as the output. The target takes the request as one jsonb, which the invoker
-- passes since rpc_invoker_passes_the_request_and_honours_defer.sql.
--
-- No model call exists in this routine: it is plpgsql over agent_runs, phase_c_system_execution,
-- workflow_run and workflow_step_run. used_llm:false in its output is a fact about the code, stated with
-- its basis, not a literal copied from the applier.
--
-- Down: scripts/sql/down/change_deployment_deterministic_executors_down.sql
--
--   node scripts/apply_sql.mjs scripts/sql/change_deployment_deterministic_executors.sql --apply --ddl

begin;

create or replace function public.fn_change_deployment_execute(p jsonb)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id     uuid := nullif(p->>'workflow_run_id','')::uuid;
  v_step_no    int  := nullif(p->>'step_no','')::int;
  v_ctx        jsonb;
  v_ref        text;
  v_at         timestamptz;
  v_fns        text[];
  v_window_min int  := coalesce(nullif(p->>'grade_window_minutes','')::int, 60);
  v_from       timestamptz;
  v_to         timestamptz;
  v_per        jsonb;
  v_err        int;
  v_runs       int;
  v_traces     int;
  v_base       jsonb;
  v_base_src   text;
  v_hours      numeric;
  v_base_rate  numeric;
  v_post_rate  numeric;
  v_grade      text;
  v_task       bigint;
  v_money      text[];
  v_deliv      text;
  v_verified   jsonb;
  v_parity     text;
  v_project    text;
begin
  if v_run_id is null or v_step_no is null then
    raise exception 'fn_change_deployment_execute: request carries no workflow_run_id/step_no (got %)', left(p::text, 300);
  end if;

  select r.context into v_ctx from public.workflow_run r where r.id = v_run_id;
  if v_ctx is null then
    raise exception 'fn_change_deployment_execute: workflow_run % not found', v_run_id;
  end if;

  v_ref := v_ctx->>'ref';
  v_at  := nullif(v_ctx->>'at','')::timestamptz;
  select coalesce(array_agg(x order by x), '{}'::text[]) into v_fns
    from jsonb_array_elements_text(coalesce(v_ctx->'functions', '[]'::jsonb)) x;

  -- The one project is read, not embedded: fn_action_invoke_dispatch reads the same key, and the schema
  -- export must stay portable (export_from_either_source_is_identical flags an embedded ref).
  select value into v_project from public.app_secrets where key = 'project_ref';
  if v_project is null then
    raise exception 'app_secrets.project_ref is not set: a mis-targeted deploy cannot be told from the one project';
  end if;

  -- ESCALATE INSTEAD OF PROPOSING (step-1 playbook, enforced): these are not proposable changes.
  if v_ref is distinct from v_project then
    raise exception 'mis-targeted deploy: deploy.completed names ref % and the one project is %; nothing here is proposed or graded', coalesce(v_ref, '(none)'), v_project;
  end if;
  if coalesce(array_length(v_fns, 1), 0) = 0 then
    raise exception 'deploy.completed carries no function slugs: there is nothing to measure, so the change is not proposed';
  end if;
  if v_at is null then
    raise exception 'deploy.completed carries no "at" timestamp: the baseline window cannot be placed';
  end if;

  -- ------------------------------------------------------------------ the metric, read over a window
  -- Failures per deployed function: errored agent_runs (the function logs under its own slug) plus failed
  -- kernel traces of any cron whose command invokes /functions/v1/<slug>.
  if v_step_no = 1 then v_from := v_at - interval '7 days'; v_to := v_at;
  elsif v_step_no = 9 then v_from := v_at; v_to := least(now(), v_at + interval '24 hours');
  end if;

  if v_step_no in (1, 9) then
    if v_step_no = 9 and now() < v_at + make_interval(mins => v_window_min) then
      return jsonb_build_object(
        'defer_until', v_at + make_interval(mins => v_window_min),
        'reason', format('grading needs at least %s minutes after the deploy at %s; %s minutes have elapsed',
                         v_window_min, v_at, floor(extract(epoch from now() - v_at) / 60)::int),
        'step_no', 9, 'worked_by', 'fn_change_deployment_execute');
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
             'slug', f.slug,
             'errored_runs', (select count(*) from public.agent_runs a
                               where a.agent = f.slug and a.status = 'error'
                                 and a.started_at >= v_from and a.started_at < v_to),
             'total_runs',   (select count(*) from public.agent_runs a
                               where a.agent = f.slug
                                 and a.started_at >= v_from and a.started_at < v_to),
             'failed_traces', (select count(*) from public.phase_c_system_execution t
                                where t.result = 'failed'
                                  and t.started_at >= v_from and t.started_at < v_to
                                  and t.component_id in (select w.component_id
                                                           from public.phase_c_system_execution_wrapper w
                                                          where w.original_command like '%/functions/v1/' || f.slug || '%')))
           order by f.slug), '[]'::jsonb)
      into v_per
      from unnest(v_fns) as f(slug);

    select coalesce(sum((e->>'errored_runs')::int), 0), coalesce(sum((e->>'total_runs')::int), 0),
           coalesce(sum((e->>'failed_traces')::int), 0)
      into v_err, v_runs, v_traces
      from jsonb_array_elements(v_per) e;
  end if;

  -- ------------------------------------------------------------------ step 1: propose + baseline
  if v_step_no = 1 then
    v_deliv := format(
      'CHANGE PROPOSED: the deploy of %s function(s) to %s completed at %s (deploy.completed, emitted by scripts/deploy_functions.mjs after reading each version back): %s. '
      || 'METRIC IT SHOULD MOVE: each deployed function''s failure count — errored agent_runs under its own slug plus failed kernel traces of the crons that call it. '
      || 'BASELINE CAPTURED over the 7 days ending at %s (168h): %s errored run(s) of %s run(s) and %s failed kernel trace(s) across the set; per function: %s. '
      || 'REVERSIBILITY: redeploy the previously committed bundle for each slug (node scripts/deploy_functions.mjs --ref=%s --production <slug>); a SQL change reverses by its down script under scripts/sql/down/. '
      || 'Step 9 grades the window after the deploy against these numbers.',
      array_length(v_fns, 1), v_ref, v_at, array_to_string(v_fns, ', '), v_at, v_err, v_runs, v_traces,
      (select string_agg(format('%s errored %s/%s runs, %s failed trace(s)', e->>'slug', e->>'errored_runs', e->>'total_runs', e->>'failed_traces'), '; ')
         from jsonb_array_elements(v_per) e),
      v_project);
    return jsonb_build_object(
      'step_no', 1, 'kind', 'baseline', 'mode', 'performed', 'worked_by', 'fn_change_deployment_execute',
      'used_llm', false, 'used_llm_basis', 'plpgsql over agent_runs and phase_c_system_execution; no provider call exists in this routine',
      'ref', v_ref, 'at', v_at, 'functions', to_jsonb(v_fns), 'count', array_length(v_fns, 1),
      'metric', 'errored agent_runs per deployed function + failed kernel traces of the crons calling it',
      'window', jsonb_build_object('from', v_from, 'to', v_to, 'hours', 168),
      'baseline', jsonb_build_object('errored_runs', v_err, 'total_runs', v_runs, 'failed_traces', v_traces,
                                     'failures', v_err + v_traces, 'per_function', v_per),
      'reversibility', 'redeploy the previously committed bundle per slug; SQL by its down script',
      'deliverable', v_deliv,
      'outcome', format('proposed %s function(s); baseline %s failure(s) over 168h before %s', array_length(v_fns, 1), v_err + v_traces, v_at));
  end if;

  -- ------------------------------------------------------------------ step 8: promote to production
  if v_step_no = 8 then
    v_verified := v_ctx->'verified';
    v_parity := case
      when v_verified is null then 'not_in_payload'
      when coalesce((v_verified->>'pass')::int, -1) = array_length(v_fns, 1)
           and coalesce(jsonb_array_length(v_verified->'not_verified'), 0) = 0 then 'verified_all'
      else 'verified_partial' end;
    -- Money and identity surfaces are founder-gated territory whatever the diff size (step-2 playbook).
    select coalesce(array_agg(s), '{}'::text[]) into v_money
      from unnest(v_fns) s
     where s ~ '^(customer_api|os_api|refunds?_api|stripe_webhook|payment|checkout|reveal|invoice)';
    v_deliv := format(
      'PROMOTED TO PRODUCTION: the deploy IS the promotion — deploy.completed is emitted only after scripts/deploy_functions.mjs read each function''s version back from the management API. Functions (%s): %s. Target %s at %s. '
      || 'PARITY: %s%s. '
      || 'BLAST RADIUS: %s. '
      || 'No further action moves the change; step 9 monitors it against the step-1 baseline.',
      array_length(v_fns, 1), array_to_string(v_fns, ', '), v_ref, v_at,
      case v_parity
        when 'verified_all' then format('the emitter verified %s/%s version bump(s)', v_verified->>'pass', v_verified->>'of')
        when 'verified_partial' then format('the emitter verified %s/%s; not verified: %s', v_verified->>'pass', v_verified->>'of', coalesce(v_verified->>'not_verified', '[]'))
        else 'the event predates the 5 Sep emitter and carries no verification detail; the emitter''s own rule 4 (version read-back before the event is emitted) is the only evidence, and it is not repeated here' end,
      case when v_verified ? 'versions' then '; versions: ' || left((v_verified->'versions')::text, 1500) else '' end,
      case when coalesce(array_length(v_money, 1), 0) > 0
           then 'includes a money/identity surface (' || array_to_string(v_money, ', ') || ') — high radius regardless of diff size'
           else 'no money/identity surface among the slugs; radius is the ' || array_length(v_fns, 1) || ' function(s) and what they write' end);
    return jsonb_build_object(
      'step_no', 8, 'kind', 'promote', 'mode', 'performed', 'worked_by', 'fn_change_deployment_execute',
      'used_llm', false, 'used_llm_basis', 'plpgsql over the run context; no provider call exists in this routine',
      'promoted', true, 'promotion_is', 'the verified deploy the event describes',
      'ref', v_ref, 'at', v_at, 'functions', to_jsonb(v_fns), 'count', array_length(v_fns, 1),
      'parity', jsonb_build_object('verdict', v_parity, 'instrument', 'scripts/deploy_functions.mjs rule 4 (version read-back), carried as context.verified',
                                   'verified', coalesce(v_verified, 'null'::jsonb)),
      'money_surfaces', to_jsonb(v_money),
      'deliverable', v_deliv,
      'outcome', format('promoted %s function(s) at %s; parity %s', array_length(v_fns, 1), v_at, v_parity));
  end if;

  -- ------------------------------------------------------------------ step 9: monitor, grade, recommend
  if v_step_no = 9 then
    v_hours := greatest(extract(epoch from v_to - v_from) / 3600.0, 0.01);
    select s.output->'result'->0->'baseline' into v_base
      from public.workflow_step_run s
     where s.workflow_run_id = v_run_id and s.step_no = 1 and s.status = 'done';
    if v_base ? 'failures' then
      v_base_src := 'step 1 of this run';
    else
      -- step 1 was closed advisory (before this file) or the shape is foreign: recompute from the same predicate
      select jsonb_build_object(
               'errored_runs', coalesce(sum(e.err), 0), 'total_runs', coalesce(sum(e.tot), 0),
               'failed_traces', coalesce(sum(e.tr), 0), 'failures', coalesce(sum(e.err + e.tr), 0))
        into v_base
        from (select (select count(*) from public.agent_runs a where a.agent = f.slug and a.status = 'error'
                        and a.started_at >= v_at - interval '7 days' and a.started_at < v_at) err,
                     (select count(*) from public.agent_runs a where a.agent = f.slug
                        and a.started_at >= v_at - interval '7 days' and a.started_at < v_at) tot,
                     (select count(*) from public.phase_c_system_execution t where t.result = 'failed'
                        and t.started_at >= v_at - interval '7 days' and t.started_at < v_at
                        and t.component_id in (select w.component_id from public.phase_c_system_execution_wrapper w
                                                where w.original_command like '%/functions/v1/' || f.slug || '%')) tr
                from unnest(v_fns) f(slug)) e;
      v_base_src := 'recomputed over the 7 days before the deploy (step 1 recorded no baseline)';
    end if;

    v_base_rate := (v_base->>'failures')::numeric / 168.0;
    v_post_rate := (v_err + v_traces)::numeric / v_hours;
    v_grade := case
      when (v_err + v_traces) >= 3 and v_post_rate > 1.5 * v_base_rate then 'worse'
      when (v_base->>'failures')::int >= 3 and v_post_rate < 0.5 * v_base_rate then 'improved'
      else 'no_change' end;

    if v_grade = 'worse' then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, priority)
      select 'product_eng',
             left(format('Reverse the deploy of %s: post-deploy failures worse than baseline (run %s)', array_to_string(v_fns, ', '), v_run_id), 240),
             format('change_deployment step 9 graded the deploy at %s WORSE: %s failure(s) in %sh after it (%s/h) against a baseline of %s over 168h (%s/h; %s). Per function after the deploy: %s. '
                    || 'RECOMMENDED REVERSAL: redeploy the previously committed bundle for each slug — node scripts/deploy_functions.mjs --ref=%s --production %s. '
                    || 'This task RECORDS the recommendation; reversing a production deploy is a gated action for the Platform lead and was not performed by the executor.',
                    v_at, v_err + v_traces, round(v_hours, 1), round(v_post_rate, 3), v_base->>'failures', round(v_base_rate, 3), v_base_src,
                    (select string_agg(format('%s errored %s/%s, %s failed trace(s)', e->>'slug', e->>'errored_runs', e->>'total_runs', e->>'failed_traces'), '; ') from jsonb_array_elements(v_per) e),
                    v_project, array_to_string(v_fns, ' ')),
             'proposed', 'gated', false, 'incident_fix', 1
       where not exists (select 1 from public.org_tasks t
                          where t.title like '%(run ' || v_run_id || ')' and t.status <> 'done')
      returning id into v_task;
    end if;

    v_deliv := format(
      'MONITORED the %s deployed function(s) (%s) over %sh after the deploy at %s (window %s to %s, minimum %s min, cap 24h): %s errored run(s) of %s run(s) and %s failed kernel trace(s); per function: %s. '
      || 'BASELINE (%s): %s failure(s) over 168h = %s/h. POST: %s/h. '
      || 'GRADE: %s (worse = post >= 3 failures and rate > 1.5x baseline; improved = baseline >= 3 and rate < 0.5x; else no_change). %s',
      array_length(v_fns, 1), array_to_string(v_fns, ', '), round(v_hours, 1), v_at, v_from, v_to, v_window_min,
      v_err, v_runs, v_traces,
      (select string_agg(format('%s errored %s/%s runs, %s failed trace(s)', e->>'slug', e->>'errored_runs', e->>'total_runs', e->>'failed_traces'), '; ') from jsonb_array_elements(v_per) e),
      v_base_src, v_base->>'failures', round(v_base_rate, 3), round(v_post_rate, 3), v_grade,
      case when v_grade = 'worse' and v_task is not null then format('REVERSAL RECOMMENDED as org_task %s for Platform & Reliability (product_eng): redeploy the previously committed bundle per slug. Not performed here — a production reversal is the Platform lead''s gated action.', v_task)
           when v_grade = 'worse' then 'REVERSAL RECOMMENDED; an open org_task for this run already carries it.'
           else 'No reversal: the deploy is not worse than its baseline on this metric.' end);
    return jsonb_build_object(
      'step_no', 9, 'kind', 'grade', 'mode', 'performed', 'worked_by', 'fn_change_deployment_execute',
      'used_llm', false, 'used_llm_basis', 'plpgsql over agent_runs, phase_c_system_execution and this run''s step 1; no provider call exists in this routine',
      'ref', v_ref, 'at', v_at, 'functions', to_jsonb(v_fns), 'count', array_length(v_fns, 1),
      'window', jsonb_build_object('from', v_from, 'to', v_to, 'hours', round(v_hours, 2), 'minimum_minutes', v_window_min),
      'baseline', v_base || jsonb_build_object('source', v_base_src, 'per_hour', round(v_base_rate, 4)),
      'post', jsonb_build_object('errored_runs', v_err, 'total_runs', v_runs, 'failed_traces', v_traces,
                                 'failures', v_err + v_traces, 'per_hour', round(v_post_rate, 4), 'per_function', v_per),
      'grade', v_grade,
      'rollback_recommended', v_grade = 'worse',
      'rollback_task_id', v_task,
      'reversal_performed', false,
      'deliverable', v_deliv,
      'outcome', format('graded %s: %s failure(s) in %sh vs baseline %s/168h%s', v_grade, v_err + v_traces, round(v_hours, 1), v_base->>'failures',
                        case when v_task is not null then '; reversal recommended as org_task ' || v_task else '' end));
  end if;

  raise exception 'fn_change_deployment_execute: step % of change_deployment has no deterministic determination here (steps 1, 8, 9 only)', v_step_no;
end
$function$;

comment on function public.fn_change_deployment_execute(jsonb) is
  'Deterministic executor for change_deployment steps 1 (baseline), 8 (promote) and 9 (grade; defers until the window has elapsed; recommends reversal as an org_task, never performs it). Takes the invoker request as one jsonb. No model call.';

-- The allow-list the executor-table guard checks (an rpc target is database authority; it is granted deliberately).
insert into public.org_action_executor_rpc_allowed (target, note)
values ('fn_change_deployment_execute',
        '5 Sep 2026: change_deployment steps 1/8/9. Reads agent_runs, phase_c_system_execution, workflow_run; writes only an org_tasks reversal recommendation on grade=worse. Takes the invoker request as one jsonb.')
on conflict (target) do nothing;

-- The three executor rows: one target, three classes, so a reader of workflow_step sees what happens.
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os, risk_tier,
   reversible, idempotency_strategy, timeout_seconds, max_attempts, required_authority,
   compensation_action_class, notifies_human, unattended_ok)
values
  ('change_deploy_baseline', 'rpc', 'fn_change_deployment_execute', '{}'::jsonb, true,
   'change_deployment step 1: reads the deploy.completed payload and captures the 7-day failure baseline of the deployed functions. Read-only.',
   true, 'product_eng', 'technology', 'low', true, 'none_read_only', 60, 1, null, 'none_required_read_only', false, true),
  ('change_deploy_promote', 'rpc', 'fn_change_deployment_execute', '{}'::jsonb, true,
   'change_deployment step 8: records the promoted functions and the emitter''s verification (the deploy is the promotion). Read-only.',
   true, 'product_eng', 'technology', 'low', true, 'none_read_only', 60, 1, null, 'none_required_read_only', false, true),
  ('change_deploy_grade', 'rpc', 'fn_change_deployment_execute', '{"grade_window_minutes": 60}'::jsonb, true,
   'change_deployment step 9: defers until 60 min after the deploy, grades post-deploy failures against the step-1 baseline, and on worse records a reversal recommendation as an org_task for product_eng. Never reverses a deploy.',
   true, 'product_eng', 'technology', 'low', true, 'natural_key', 60, 1, null, 'manual_reversal', false, true)
on conflict (action_class) do update set
  kind = excluded.kind, target = excluded.target, params = excluded.params, active = true, note = excluded.note,
  advisory_safe = excluded.advisory_safe, department = excluded.department, owner_os = excluded.owner_os,
  risk_tier = excluded.risk_tier, reversible = excluded.reversible, idempotency_strategy = excluded.idempotency_strategy,
  timeout_seconds = excluded.timeout_seconds, max_attempts = excluded.max_attempts,
  compensation_action_class = excluded.compensation_action_class, notifies_human = excluded.notifies_human,
  unattended_ok = excluded.unattended_ok;

update public.workflow_step set action_class = 'change_deploy_baseline' where workflow_key = 'change_deployment' and step_no = 1;
update public.workflow_step set action_class = 'change_deploy_promote'  where workflow_key = 'change_deployment' and step_no = 8;
update public.workflow_step set action_class = 'change_deploy_grade'    where workflow_key = 'change_deployment' and step_no = 9;

do $$
begin
  if (select count(*) from public.workflow_step where workflow_key = 'change_deployment'
       and action_class in ('change_deploy_baseline','change_deploy_promote','change_deploy_grade')) <> 3 then
    raise exception 'change_deployment steps 1, 8, 9 are not wired to the deterministic executors';
  end if;
  if public.fn_executor_needs_model('fn_change_deployment_execute') then
    raise exception 'fn_change_deployment_execute must not be registered as a model-backed fn_task_class';
  end if;
end $$;

commit;
