-- A DETERMINISTIC CLOSE PERFORMS THE STEP, IT DOES NOT DOCUMENT IT (MASTER_PLAN A1 / §4.2), 5 Sep 2026.
--
-- MEASURED on production 4 Sep 2026, every number by hand:
--   * fn_workflow_step_deterministic_done wrote jsonb_build_object('used_llm', false, 'disposition',
--     'deterministic_low_confidence', ...) UNCONDITIONALLY. The flag was a literal, not a measurement,
--     and all 215 deterministic_step review_queue rows carried that one disposition — it could not tell a
--     step that was determined from one that merely needed narrative.
--   * A step closed this way carried mode='advisory' and stranded_reason='executor runs on the held paid
--     model; not queued'. Its executor never ran. metric_lifecycle step 7 (bi_snapshot -> fn_bi_snapshot,
--     kind rpc, zero-arg, no model) was closed by the dispatcher 12 times without fn_bi_snapshot ever
--     being called for it.
--   * 27 change_deployment step-1 rows carried EXACTLY ONE distinct deliverable across 27 distinct
--     inputs; metric_lifecycle step 1: 13 closes, 1 deliverable, 13 contexts. The applier emitted the
--     playbook's own text. Done meant documented, not performed.
--
-- WHAT CHANGES, all deterministic, no model call anywhere:
--   1. fn_workflow_step_facts(step_run_id) reads the step's OWN facts: the triggering company_event and
--      its payload, the run context, the metric it is about (v_bi_scorecard row, snapshot history, the
--      consecutive-miss count), the goals at risk (company_goals + latest goal_period), the failing
--      metrics, and the prior steps' outcomes — then DERIVES the band, the gap, the attainment and the
--      cause class by the rules the metric_lifecycle playbooks themselves encode. facts_bound counts
--      how many facts the step actually had.
--   2. fn_workflow_step_render(facts, record) renders the playbook's structured_data AGAINST those facts:
--      a keyed map in structured_data (next/by_cause/causes/company_metric_bands/...) is resolved at the
--      derived band, cause, direction, event type or gate, and the selected entry is what the step
--      decided; the facts it decided from are printed first. Two runs with different inputs produce
--      different deliverables; the same input produces the same deliverable, which is what a
--      determination is.
--   3. fn_workflow_step_deterministic_done INVOKES the step's executor when it is deterministic:
--        kind rpc, zero required args, low/advisory_safe/reversible, notifies nobody -> called inline,
--          recorded as a succeeded/failed action_execution (idempotency_key workflow_step:<id>:det);
--        kind edge, no model (fn_executor_needs_model false), same policy -> a fresh action_execution is
--          queued for the HTTP invoker and the step stays running until the sweep settles it with the
--          executor's response merged over the determination (a step whose earlier execution the invoker
--          REFUSED is not re-queued: the refusal is recorded and the step closes);
--        model-backed executor -> not invoked, and the disposition says so;
--        notifies_human / risk / founder-reserved -> withheld by the same policy the sweep applies, said
--          in words. Never an email, never a paid call.
--   4. The disposition DISCRIMINATES, and each value is earned by a measurement:
--        determined            facts_bound > 0 and the executor is deterministic (ran, was queued, or was
--                              withheld by policy — executor_status says which)
--        advisory_held_model   facts_bound > 0 but the executor can only answer through the held model
--        needs_narrative       facts_bound = 0: nothing in the event, the context, the metric, the goals
--                              or the prior steps gave the close a fact to decide from
--      'deterministic_low_confidence' is no longer written by anything.
--   5. used_llm is a MEASUREMENT: llm_attempt and ai_cost_log rows written by workflow_dispatch since the
--      step was claimed, counted at close time; used_llm_basis carries the counts. determination_source
--      names what produced the deliverable: 'executor:<target>' or 'playbook_rendered'. Every existing
--      reader of used_llm (fn_workflow_step_claim's ceiling, rehearse_change_deployment_loop.mjs) reads a
--      measured value now and needed no change.
--   6. The false-success guards are TIGHTER, never looser: the close's own similarity floor rises from
--      0.42 to the applier's 0.85 and it now also requires terms_matched >= 2 (the keyword corroboration
--      apply_playbook_needs_corroboration.sql introduced), so a close cannot pass on cosine alone even if
--      a caller skips fn_apply_playbook.
--   7. fn_workflow_step_sweep's settle merges the step's existing output under the executor response, so
--      a determination stored before a queued executor ran is not overwritten when the executor lands.
--
--   node scripts/apply_sql.mjs scripts/sql/a_deterministic_close_performs_the_step_2026_09_05.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------------
-- 1. THE STEP'S OWN FACTS. Scalars throughout: a SELECT INTO that finds no row nulls every target, and
--    a RECORD assigned only by a no-row SELECT raises when read.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_facts(p_step_run_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  -- step + run
  v_step_no int; v_actor text; v_action_class text; v_input jsonb; v_started timestamptz; v_run uuid;
  v_wf text; v_ctx jsonb; v_trigger bigint; v_r_entity_type text; v_r_entity_id text;
  -- event
  v_ev_type text; v_ev_entity_type text; v_ev_entity_id text; v_ev_payload jsonb; v_ev_at timestamptz; v_ev_actor text;
  -- metric
  v_mk text; v_label text; v_owner text; v_val numeric; v_tgt numeric; v_dir text; v_state text; v_err text;
  v_taken timestamptz; v_definition text; v_in_scorecard boolean := false;
  v_hist jsonb; v_consec int := 0; v_ever_met boolean := false; v_n_snap int := 0; snap record; v_off boolean;
  v_metric jsonb := null; v_band text; v_gap numeric; v_att numeric; v_cause text; v_cause_why text;
  -- goals
  v_goals jsonb := null; v_failing jsonb := null; v_prior jsonb := '[]'::jsonb;
  v_bound int := 0; v_derived jsonb := '{}'::jsonb;
begin
  select s.step_no, s.actor, s.action_class, s.input, s.started_at, s.workflow_run_id,
         r.workflow_key, coalesce(r.context, '{}'::jsonb), r.trigger_event_id, r.entity_type, r.entity_id
    into v_step_no, v_actor, v_action_class, v_input, v_started, v_run,
         v_wf, v_ctx, v_trigger, v_r_entity_type, v_r_entity_id
    from public.workflow_step_run s
    join public.workflow_run r on r.id = s.workflow_run_id
   where s.id = p_step_run_id;
  if v_run is null then return null; end if;

  select e.event_type, e.entity_type, e.entity_id, e.payload, e.occurred_at, e.actor
    into v_ev_type, v_ev_entity_type, v_ev_entity_id, v_ev_payload, v_ev_at, v_ev_actor
    from public.company_event e where e.id = v_trigger;
  v_ev_payload := coalesce(v_ev_payload, '{}'::jsonb);

  -- THE METRIC THIS RUN IS ABOUT. Keyed by the event's entity (kpi.missed carries metric_key as
  -- entity_id), else by the context's metric_key, else by the label the emitter wrote.
  v_mk := case when v_ev_entity_type = 'metric' then v_ev_entity_id
               when v_ctx ? 'metric_key' then v_ctx->>'metric_key'
               when v_r_entity_type = 'metric' then v_r_entity_id
               else (select d.metric_key from public.metric_definition d
                      where d.label = coalesce(v_ctx->>'label', v_ev_payload->>'label') limit 1) end;
  -- the emitter's numbers are facts even when the metric is a fixture with no definition row
  v_label := coalesce(v_ctx->>'label', v_ev_payload->>'label');
  v_val   := coalesce(nullif(v_ev_payload->>'value','')::numeric, nullif(v_ctx->>'value','')::numeric);
  v_tgt   := coalesce(nullif(v_ev_payload->>'target','')::numeric, nullif(v_ctx->>'target','')::numeric);
  v_state := coalesce(v_ev_payload->>'state', v_ctx->>'state');
  v_dir   := coalesce(v_ev_payload->>'direction', v_ctx->>'direction');

  if v_mk is not null then
    select sc.label, sc.owner_dept, sc.value, sc.target, sc.direction, sc.state, sc.error, sc.taken_at, sc.definition, true
      into v_label, v_owner, v_val, v_tgt, v_dir, v_state, v_err, v_taken, v_definition, v_in_scorecard
      from public.v_bi_scorecard sc where sc.metric_key = v_mk;
    v_in_scorecard := coalesce(v_in_scorecard, false);
    if not v_in_scorecard then
      -- the scorecard select found nothing and nulled the targets: restore the emitter's numbers
      v_label := coalesce(v_ctx->>'label', v_ev_payload->>'label');
      v_val   := coalesce(nullif(v_ev_payload->>'value','')::numeric, nullif(v_ctx->>'value','')::numeric);
      v_tgt   := coalesce(nullif(v_ev_payload->>'target','')::numeric, nullif(v_ctx->>'target','')::numeric);
      v_state := coalesce(v_ev_payload->>'state', v_ctx->>'state');
      v_dir   := coalesce(v_ev_payload->>'direction', v_ctx->>'direction');
    end if;

    -- snapshot history, newest first, and the leading run of misses — the metric_lifecycle playbooks'
    -- TARGET_MIS_SET test reads ">= 3 consecutive measured periods, never met since the target was set"
    v_hist := '[]'::jsonb;
    for snap in
      select s.value, s.error, s.taken_at from public.metric_snapshot s
       where s.metric_key = v_mk order by s.taken_at desc limit 12
    loop
      v_n_snap := v_n_snap + 1;
      if v_n_snap <= 6 then
        v_hist := v_hist || jsonb_build_object('value', snap.value, 'error', snap.error, 'taken_at', snap.taken_at);
      end if;
      v_off := snap.error is null and snap.value is not null and v_tgt is not null
               and ((v_dir = 'up' and snap.value < v_tgt * 0.7) or (v_dir = 'down' and snap.value > v_tgt * 1.3));
      if v_off and v_consec = v_n_snap - 1 then v_consec := v_consec + 1; end if;
      if snap.error is null and snap.value is not null and v_tgt is not null
         and ((v_dir = 'up' and snap.value >= v_tgt) or (v_dir = 'down' and snap.value <= v_tgt)) then
        v_ever_met := true;
      end if;
    end loop;
  end if;

  if v_label is not null or v_val is not null or v_mk is not null then
    -- band by the scorecard's own rule when the scorecard did not already say
    v_band := coalesce(v_state,
                case when v_err is not null then 'ERROR'
                     when v_val is null or v_tgt is null then 'UNMEASURED'
                     when v_dir = 'up'   and v_val >= v_tgt then 'ON_TARGET'
                     when v_dir = 'down' and v_val <= v_tgt then 'ON_TARGET'
                     when v_dir = 'up'   and v_val >= v_tgt * 0.7 then 'BEHIND'
                     when v_dir = 'down' and v_val <= v_tgt * 1.3 then 'BEHIND'
                     when v_val is not null and v_tgt is not null then 'OFF_TARGET' end);
    v_gap := case when v_val is not null and v_tgt is not null then v_val - v_tgt end;
    v_att := case when v_val is null or v_tgt is null then null
                  when coalesce(v_dir,'up') = 'up' then
                       case when v_tgt > 0 then round(100 * v_val / v_tgt, 1)
                            when v_val <= 0 then 100 else null end
                  else case when v_val > 0 then least(100, round(100 * v_tgt / v_val, 1)) else 100 end end;
    -- cause class, by the "root cause" playbook's own definitions, from what is measurable here
    if v_band = 'ERROR' or v_err is not null then
      v_cause := 'INSTRUMENT'; v_cause_why := 'the latest snapshot carries an error: ' || coalesce(v_err, '(null)');
    elsif v_band = 'UNMEASURED' then
      v_cause := 'INSTRUMENT'; v_cause_why := 'value or target is null; the metric is UNMEASURED, not failing';
    elsif v_band in ('ON_TARGET', 'BEHIND') then
      v_cause := 'NONE'; v_cause_why := 'band ' || v_band || ': no miss to attribute';
    elsif v_consec >= 3 and not v_ever_met and coalesce(btrim(v_definition), '') = '' then
      v_cause := 'TARGET_MIS_SET';
      v_cause_why := v_consec || ' consecutive OFF_TARGET snapshots, never met in ' || v_n_snap
                     || ' recorded, and metric_definition.definition is empty (no documented basis)';
    else
      v_cause := 'EXECUTION';
      v_cause_why := 'default per the playbook: input existed and the instrument is sound. TARGET_MIS_SET test: '
                     || v_consec || ' consecutive OFF_TARGET snapshot(s) (needs >= 3), ever met = ' || v_ever_met
                     || ', documented basis = ' || (coalesce(btrim(v_definition), '') <> '')
                     || case when v_n_snap = 0 then '; no snapshot history for this key' else '' end;
    end if;
    v_metric := jsonb_strip_nulls(jsonb_build_object(
      'metric_key', v_mk, 'label', v_label, 'owner_dept', v_owner, 'in_scorecard', v_in_scorecard,
      'value', v_val, 'target', v_tgt, 'direction', v_dir, 'state', v_state, 'error', v_err,
      'taken_at', v_taken, 'snapshots_newest_first', v_hist, 'snapshots_read', v_n_snap,
      'consecutive_off_target', v_consec, 'ever_met', v_ever_met));
    v_bound := v_bound + (v_val is not null)::int + (v_tgt is not null)::int + (v_band is not null)::int
               + (v_n_snap > 0)::int;
    v_derived := jsonb_strip_nulls(jsonb_build_object(
      'band', v_band, 'gap', v_gap, 'attainment_pct', v_att, 'cause', v_cause, 'cause_evidence', v_cause_why,
      'direction', v_dir));
  end if;

  -- GOALS AT RISK and FAILING METRICS (goal.at_risk carries both as arrays of keys / labels)
  if jsonb_typeof(v_ctx->'goals_at_risk') = 'array' or jsonb_typeof(v_ev_payload->'goals_at_risk') = 'array' then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'key', g.key, 'goal', g.goal, 'metric', g.metric, 'target_value', g.target_value, 'unit', g.unit,
             'direction', g.direction, 'owner_dept', g.owner_dept, 'horizon', g.horizon, 'deadline', g.deadline,
             'active', g.active,
             'latest_period', (select jsonb_build_object('period', p.period_label, 'actual', p.actual_value,
                                                         'target', p.target_value, 'status', p.status)
                                 from public.goal_period p where p.goal_key = g.key
                                order by p.updated_at desc limit 1))) order by g.key), '[]'::jsonb)
      into v_goals
      from public.company_goals g
     where g.key in (select jsonb_array_elements_text(coalesce(v_ctx->'goals_at_risk', v_ev_payload->'goals_at_risk')));
    -- a fixture goal with no company_goals row is still a named fact of the trigger
    select coalesce(v_goals, '[]'::jsonb) || coalesce(jsonb_agg(jsonb_build_object('key', k, 'in_company_goals', false)), '[]'::jsonb)
      into v_goals
      from jsonb_array_elements_text(coalesce(v_ctx->'goals_at_risk', v_ev_payload->'goals_at_risk')) k
     where not exists (select 1 from public.company_goals g where g.key = k);
    v_bound := v_bound + coalesce(jsonb_array_length(v_goals), 0);
  end if;
  if jsonb_typeof(v_ctx->'failing_metrics') = 'array' or jsonb_typeof(v_ev_payload->'failing_metrics') = 'array' then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'label', lbl, 'metric_key', sc.metric_key, 'value', sc.value, 'target', sc.target,
             'direction', sc.direction, 'state', sc.state, 'error', sc.error, 'taken_at', sc.taken_at,
             'owner_dept', sc.owner_dept, 'in_scorecard', (sc.metric_key is not null))) order by lbl), '[]'::jsonb)
      into v_failing
      from jsonb_array_elements_text(coalesce(v_ctx->'failing_metrics', v_ev_payload->'failing_metrics')) lbl
      left join public.v_bi_scorecard sc on sc.label = lbl;
    v_bound := v_bound + coalesce(jsonb_array_length(v_failing), 0);
  end if;

  -- WHAT THIS RUN ALREADY CONCLUDED (outcome lines only, in order)
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'step_no', p.step_no, 'step', p.input->>'step', 'by', coalesce(p.output->>'employee', p.actor),
           'outcome', left(coalesce(p.output->>'outcome', p.output->>'note', ''), 600),
           'disposition', p.output->>'disposition', 'determination_source', p.output->>'determination_source',
           'executor_status', p.output->>'executor_status')) order by p.step_no), '[]'::jsonb)
    into v_prior
    from public.workflow_step_run p
   where p.workflow_run_id = v_run and p.step_no < v_step_no and p.status = 'done';
  v_bound := v_bound + (select count(*) from jsonb_array_elements(v_prior) x where coalesce(x->>'outcome','') <> '')::int;

  -- the trigger payload's own scalar facts, beyond the ones already read above
  v_bound := v_bound + (select count(*) from jsonb_each(v_ev_payload) e
                         where jsonb_typeof(e.value) in ('string','number','boolean')
                           and e.key not in ('label','value','target','state','direction'))::int;

  return jsonb_strip_nulls(jsonb_build_object(
    'step', jsonb_build_object('workflow_key', v_wf, 'step_no', v_step_no, 'step', v_input->>'step',
                               'gate', v_input->>'gate', 'actor', v_actor, 'action_class', v_action_class,
                               'claimed_at', v_started),
    'trigger', case when v_ev_type is null then null else
                 jsonb_build_object('event_id', v_trigger, 'event_type', v_ev_type, 'entity_type', v_ev_entity_type,
                                    'entity_id', v_ev_entity_id, 'actor', v_ev_actor, 'occurred_at', v_ev_at,
                                    'payload', v_ev_payload) end,
    'context', v_ctx,
    'metric', v_metric,
    'goals_at_risk', v_goals,
    'failing_metrics', v_failing,
    'prior_steps', v_prior,
    'derived', v_derived,
    'facts_bound', v_bound,
    'read_at', now()));
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- 2. RENDER the record against the facts. Pure text; the selection rule is the same for every record:
--    an object-valued key in structured_data is resolved at the derived band, the cause class, the
--    direction, the trigger's event type and the step's gate. What is selected is what was decided.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_render(p_facts jsonb, p_title text, p_record_type text,
                                                          p_content text, p_structured jsonb)
returns text
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
declare
  f jsonb := coalesce(p_facts, '{}'::jsonb);
  d jsonb := coalesce(p_facts->'derived', '{}'::jsonb);
  m jsonb := p_facts->'metric';
  t text := '';
  sel text[]; k text; v jsonb; s text; x jsonb; n int := 0; lines text := '';
begin
  t := 'DETERMINATION — ' || coalesce(f#>>'{step,workflow_key}', '?') || ' step ' || coalesce(f#>>'{step,step_no}', '?')
       || ': ' || coalesce(f#>>'{step,step}', '') || E'\n'
       || 'Decided by ' || coalesce(f#>>'{step,actor}', '?') || ' at ' || coalesce(f->>'read_at', '') || ' from '
       || coalesce(f->>'facts_bound', '0') || ' bound fact(s); no model call.' || E'\n\n';

  t := t || E'FACTS THIS STEP DECIDED FROM\n';
  if f ? 'trigger' then
    t := t || '- trigger: ' || coalesce(f#>>'{trigger,event_type}', '?') || ' on ' || coalesce(f#>>'{trigger,entity_type}', '?')
         || ' ' || coalesce(f#>>'{trigger,entity_id}', '?') || ' at ' || coalesce(f#>>'{trigger,occurred_at}', '?')
         || ' (event ' || coalesce(f#>>'{trigger,event_id}', '?') || ') payload ' || coalesce((f#>'{trigger,payload}')::text, '{}') || E'\n';
  else
    t := t || E'- trigger: none recorded on this run\n';
  end if;
  if m is not null then
    t := t || '- metric: ' || coalesce(m->>'label', m->>'metric_key', '?')
         || case when (m->>'metric_key') is not null then ' [' || (m->>'metric_key') || ']' else '' end
         || ' value=' || coalesce(m->>'value', 'null') || ' target=' || coalesce(m->>'target', 'null')
         || ' direction=' || coalesce(m->>'direction', 'unknown') || ' state=' || coalesce(m->>'state', d->>'band', 'unknown')
         || case when (m->>'error') is not null then ' ERROR=' || (m->>'error') else '' end
         || case when (m->>'taken_at') is not null then ' taken_at=' || (m->>'taken_at') else '' end
         || ' owner=' || coalesce(m->>'owner_dept', 'unknown')
         || ' in_scorecard=' || coalesce(m->>'in_scorecard', 'false') || E'\n'
         || '- snapshots (newest first, ' || coalesce(m->>'snapshots_read', '0') || ' read): ' || coalesce((m->'snapshots_newest_first')::text, '[]')
         || '; consecutive_off_target=' || coalesce(m->>'consecutive_off_target', '0') || ' ever_met=' || coalesce(m->>'ever_met', 'false') || E'\n';
  end if;
  if jsonb_typeof(f->'goals_at_risk') = 'array' then
    for x in select * from jsonb_array_elements(f->'goals_at_risk') loop
      t := t || '- goal at risk: ' || coalesce(x->>'key', '?')
           || case when coalesce(x->>'in_company_goals', 'true') = 'false' then ' (no company_goals row)'
                   else ' "' || coalesce(x->>'goal', '') || '" target ' || coalesce(x->>'target_value', 'null') || ' ' || coalesce(x->>'unit', '')
                        || ' dir=' || coalesce(x->>'direction', '?') || ' owner=' || coalesce(x->>'owner_dept', '?')
                        || ' deadline=' || coalesce(x->>'deadline', 'none')
                        || case when x ? 'latest_period' then ' latest period ' || (x->'latest_period')::text else ' (no goal_period yet)' end end
           || E'\n';
    end loop;
  end if;
  if jsonb_typeof(f->'failing_metrics') = 'array' then
    for x in select * from jsonb_array_elements(f->'failing_metrics') loop
      t := t || '- failing metric: ' || coalesce(x->>'label', '?')
           || case when coalesce(x->>'in_scorecard', 'false') = 'true'
                   then ' [' || (x->>'metric_key') || '] value=' || coalesce(x->>'value', 'null') || ' target=' || coalesce(x->>'target', 'null')
                        || ' state=' || coalesce(x->>'state', '?') || ' owner=' || coalesce(x->>'owner_dept', '?')
                        || case when (x->>'error') is not null then ' ERROR=' || (x->>'error') else '' end
                   else ' (not on v_bi_scorecard: the emitter''s label only)' end
           || E'\n';
    end loop;
  end if;
  if jsonb_typeof(f->'prior_steps') = 'array' and jsonb_array_length(f->'prior_steps') > 0 then
    for x in select * from jsonb_array_elements(f->'prior_steps') loop
      t := t || '- prior step ' || coalesce(x->>'step_no', '?') || ' (' || coalesce(x->>'by', '?') || ', '
           || coalesce(x->>'disposition', 'no disposition') || '): ' || coalesce(x->>'outcome', '') || E'\n';
    end loop;
  else
    t := t || E'- prior steps: none concluded yet; this is the first step of the run to decide anything\n';
  end if;
  if f ? 'context' and (f->'context') <> '{}'::jsonb then
    t := t || '- run context: ' || (f->'context')::text || E'\n';
  end if;

  t := t || E'\nDETERMINED\n';
  if m is not null then
    t := t || '- variance: ' || coalesce(m->>'label', '?') || ' is ' || coalesce(d->>'band', 'unknown')
         || case when d ? 'gap' then ' — gap ' || (d->>'gap') || ' against target ' || coalesce(m->>'target', 'null')
                                   || ' (direction ' || coalesce(d->>'direction', 'unknown') || ')' else '' end
         || case when d ? 'attainment_pct' then ', attainment ' || (d->>'attainment_pct') || '%' else '' end || E'\n'
         || '- cause class: ' || coalesce(d->>'cause', 'not established') || ' — ' || coalesce(d->>'cause_evidence', '') || E'\n';
  end if;

  -- resolve keyed maps in structured_data at the facts
  sel := array_remove(array[d->>'band', d->>'cause', d->>'direction', f#>>'{trigger,event_type}', f#>>'{step,gate}',
                            lower(d->>'band'), lower(d->>'cause')], null);
  if p_structured is not null and jsonb_typeof(p_structured) = 'object' then
    for k, v in select * from jsonb_each(p_structured) loop
      if jsonb_typeof(v) = 'object' then
        foreach s in array coalesce(sel, '{}'::text[]) loop
          if v ? s then
            n := n + 1;
            lines := lines || '- ' || k || '[' || s || '] → ' || case when jsonb_typeof(v->s) = 'string' then v->>s else (v->s)::text end || E'\n';
          end if;
        end loop;
      end if;
    end loop;
  end if;
  if n > 0 then
    t := t || 'Selected from "' || coalesce(p_title, '?') || '" at the facts above (' || n || ' rule(s)):' || E'\n' || lines;
  else
    t := t || 'No keyed rule in "' || coalesce(p_title, '?') || '" resolves at these facts; the record applies as written below.' || E'\n';
  end if;

  t := t || E'\nAPPLIED RECORD: ' || coalesce(p_record_type, '?') || ' "' || coalesce(p_title, '?') || E'"\n'
       || coalesce(p_content, '');
  if p_structured is not null and p_structured <> '{}'::jsonb then
    t := t || E'\n\nSTRUCTURED DATA OF THE RECORD:\n' || jsonb_pretty(p_structured);
  end if;
  return t;
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- 3. THE CLOSE. The ONLY way a deterministic determination closes a workflow step.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_deterministic_done(p_step_run_id bigint, p_output jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  sr           record;
  v_sim        numeric;
  v_floor      numeric := 0.85;
  v_terms      int;
  v_employee   text;
  v_dept       text;
  v_trace      uuid;
  v_review     bigint;
  v_superseded int := 0;
  v_res        text;
  v_out        jsonb;
  -- the record applied
  v_pb_id text; v_pb_title text; v_pb_type text; v_pb_content text; v_pb_sd jsonb;
  -- facts + rendering
  v_facts jsonb; v_bound int; v_deliv text; v_outcome text;
  -- executor
  ex record; v_has_ex boolean := false; v_needs_model boolean := false; v_exec_status text; v_exec_id uuid;
  v_exec_result jsonb; v_req_args int; v_kind text := null; v_source text := 'playbook_rendered';
  v_queued boolean := false; v_refused text; v_err text; v_target text;
  -- measurement
  v_llm int := 0; v_cost int := 0; v_used_llm boolean;
  v_disp text; v_mode text;
begin
  select s.id, s.workflow_run_id, s.step_no, s.actor, s.action_class, s.input, s.attempts, s.started_at, s.output as prev_output,
         r.workflow_key, r.context, r.correlation_id, r.trigger_event_id
    into sr
    from public.workflow_step_run s
    join public.workflow_run r on r.id = s.workflow_run_id
   where s.id = p_step_run_id and s.status = 'running' and s.finished_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'step is not held running by a dispatcher');
  end if;

  v_sim      := nullif(p_output->>'similarity', '')::numeric;
  v_terms    := nullif(p_output->>'terms_matched', '')::int;
  v_employee := coalesce(nullif(p_output->>'employee',''), sr.actor);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance. The floors are the
  -- applier's own (0.85 cosine AND keyword corroboration), so a caller cannot pass on cosine alone.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms is null or v_terms < 2 then
    return jsonb_build_object('ok', false, 'reason', 'terms_matched ' || coalesce(v_terms::text,'null') || ' is below the corroboration floor of 2 step terms');
  end if;
  select k.record_id, k.title, k.record_type, k.content, k.structured_data
    into v_pb_id, v_pb_title, v_pb_type, v_pb_content, v_pb_sd
    from public.ops_knowledge k
   where k.record_id = p_output->>'playbook_record_id' and k.runtime_eligible;
  if v_pb_id is null then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id') || ' is not a runtime-eligible ops_knowledge record');
  end if;
  if v_pb_type not in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook') then
    return jsonb_build_object('ok', false, 'reason', 'record ' || v_pb_id || ' is a ' || v_pb_type || ', not an actionable kind');
  end if;

  -- THE FACTS, then the deliverable AS A FUNCTION OF THEM.
  v_facts := public.fn_workflow_step_facts(sr.id);
  v_bound := coalesce((v_facts->>'facts_bound')::int, 0);

  -- THE EXECUTOR. Read the registry row and decide from it, in words.
  select e.action_class, e.kind, e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
         e.notifies_human, e.unattended_ok, e.required_authority, e.compensation_action_class
    into ex
    from public.org_action_executor e
   where e.action_class = sr.action_class and e.active
   order by e.kind limit 1;
  v_has_ex := found;
  if v_has_ex then v_target := ex.target; end if;
  if not v_has_ex then
    v_exec_status := 'none: no active executor is mapped to action_class ' || coalesce(sr.action_class, '(null)');
  else
    v_kind := ex.kind;
    v_needs_model := public.fn_executor_needs_model(ex.target);
    if v_needs_model then
      v_exec_status := 'held: ' || ex.target || ' is routed to a model task class by fn_task_class and the paid provider is held; not invoked';
    elsif coalesce(ex.required_authority, '') = 'founder' then
      v_exec_status := 'withheld: ' || ex.target || ' is reserved to the founder';
    elsif ex.notifies_human then
      v_exec_status := 'withheld: ' || ex.target || ' notifies a human (org_action_executor.notifies_human); the deterministic close never sends';
    elsif not (ex.risk_tier = 'low' and ex.advisory_safe and ex.reversible) then
      v_exec_status := format('withheld: %s is risk_tier=%s advisory_safe=%s reversible=%s; the close invokes low/advisory_safe/reversible only',
                              ex.target, ex.risk_tier, ex.advisory_safe, ex.reversible);
    elsif ex.kind not in ('rpc', 'edge') then
      v_exec_status := 'withheld: ' || ex.target || ' is a ' || ex.kind || ' executor and no invoker handles that kind';
    elsif exists (select 1 from public.action_execution x where x.workflow_step_run_id = sr.id and x.status in ('queued','running')) then
      return jsonb_build_object('ok', false, 'reason', 'executor ' || ex.target || ' is already queued or running for this step; the sweep settles it');
    elsif ex.kind = 'rpc' then
      select coalesce(p.pronargs - p.pronargdefaults, -1) into v_req_args
        from pg_proc p where p.proname = ex.target and p.pronamespace = 'public'::regnamespace
       order by p.pronargs limit 1;
      if v_req_args is null then
        v_exec_status := 'failed: public.' || ex.target || '() does not exist';
      elsif v_req_args > 0 then
        v_exec_status := 'withheld: public.' || ex.target || '() requires ' || v_req_args || ' argument(s) a workflow step cannot supply';
      else
        v_exec_id := gen_random_uuid();
        begin
          execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', ex.target) into v_exec_result;
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                  'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                     'actor', sr.actor, 'source', 'fn_workflow_step_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'succeeded', 'at', now(), 'kind', 'rpc', 'inline', true,
                                     'result_rows', coalesce(jsonb_array_length(v_exec_result), 0),
                                     'result', case when pg_column_size(v_exec_result) > 20000 then to_jsonb(left(v_exec_result::text, 20000)) else v_exec_result end),
                  'succeeded', 1, now(), now());
          v_exec_status := 'ran: public.' || ex.target || '() inline, ' || coalesce(jsonb_array_length(v_exec_result), 0)
                           || ' row(s), action_execution ' || v_exec_id;
          v_source := 'executor:' || ex.target;
        exception when others then
          v_err := sqlstate || ' ' || left(sqlerrm, 400);
          -- the failure is a fact: record it and refuse the close, so the step is released with the reason
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                  'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                     'actor', sr.actor, 'source', 'fn_workflow_step_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'failed', 'at', now(), 'kind', 'rpc', 'inline', true, 'error', v_err),
                  'failed', 1, now(), now());
          return jsonb_build_object('ok', false, 'reason', 'executor public.' || ex.target || '() failed: ' || v_err,
                                    'action_execution_id', v_exec_id);
        end;
      end if;
    else -- edge, deterministic
      select x.response->>'reason' into v_refused
        from public.action_execution x
       where x.workflow_step_run_id = sr.id and x.response->>'invoker' = 'refused'
       order by x.created_at desc limit 1;
      if v_refused is not null then
        v_exec_status := 'withheld: the invoker refused ' || ex.target || ' for this step earlier (' || left(v_refused, 200) || '); not re-queued';
      elsif exists (select 1 from public.action_execution x
                     where x.workflow_step_run_id = sr.id and x.request->>'source' = 'fn_workflow_step_deterministic_done') then
        select 'withheld: an earlier re-queue of ' || ex.target || ' for this step ended ' || x.status into v_exec_status
          from public.action_execution x
         where x.workflow_step_run_id = sr.id and x.request->>'source' = 'fn_workflow_step_deterministic_done'
         order by x.created_at desc limit 1;
      else
        v_exec_id := gen_random_uuid();
        insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                            risk_tier, reversible, request, status, attempts)
        values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                ex.risk_tier, ex.reversible,
                jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                   'actor', sr.actor, 'input', coalesce(sr.input, '{}'::jsonb),
                                   'source', 'fn_workflow_step_deterministic_done', 'kind', 'edge'),
                'queued', 0);
        v_queued := true;
        v_exec_status := 'queued: ' || ex.target || ' as action_execution ' || v_exec_id || ' for the HTTP invoker; the step closes when the sweep settles it';
        v_source := 'executor:' || ex.target;
      end if;
    end if;
  end if;

  -- THE DELIVERABLE, rendered from the facts, with the executor line.
  v_deliv := public.fn_workflow_step_render(v_facts, v_pb_title, v_pb_type, v_pb_content, v_pb_sd);
  v_deliv := regexp_replace(v_deliv, E'\nAPPLIED RECORD: ',
               E'- executor: ' || coalesce(v_exec_status, '?') || E'\n\nAPPLIED RECORD: ');

  -- THE DISPOSITION, earned.
  v_disp := case when v_bound = 0 then 'needs_narrative'
                 when v_needs_model then 'advisory_held_model'
                 else 'determined' end;
  v_mode := case when v_disp = 'determined' then 'determined' else 'advisory' end;
  v_outcome := case when v_disp = 'needs_narrative'
                    then 'No fact was bound for this step (no metric, goal, event payload or prior conclusion); the record "'
                         || v_pb_title || '" applies as written and the step needs narrative from a reviewer or the model path.'
                    else coalesce(nullif(v_facts#>>'{derived,band}', '') || ' ' || coalesce(v_facts#>>'{metric,label}', '') || ': ', '')
                         || 'applied ' || v_pb_type || ' "' || v_pb_title || '" to ' || v_bound || ' bound fact(s)'
                         || case when v_facts#>>'{derived,cause}' is not null then '; cause ' || (v_facts#>>'{derived,cause}') else '' end
                         || '; executor ' || split_part(coalesce(v_exec_status, 'none'), ':', 1) end;

  -- used_llm IS A MEASUREMENT: the provider ledgers since the dispatcher claimed this step.
  select count(*) into v_llm  from public.llm_attempt a where a.fn = 'workflow_dispatch' and a.created_at >= sr.started_at;
  select count(*) into v_cost from public.ai_cost_log c where c.fn = 'workflow_dispatch' and c.occurred_at >= sr.started_at;
  v_used_llm := (v_llm + v_cost) > 0;

  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, causation_event_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      coalesce(sr.correlation_id, gen_random_uuid()), sr.trigger_event_id,
      'workflow_step_run', sr.id::text, 'deterministic_playbook_application',
      v_employee, 'fn_workflow_step_deterministic_done', array['deterministic_first']::text[],
      jsonb_build_array(jsonb_build_object('record_id', v_pb_id, 'title', v_pb_title, 'record_type', v_pb_type,
                                           'similarity', v_sim, 'terms_matched', v_terms)),
      jsonb_build_array(jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'workflow_key', sr.workflow_key,
                                           'step_no', sr.step_no, 'step', sr.input->>'step',
                                           'facts', v_facts)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the corroborated nearest actionable company record is the applicable one for this step',
                        'the facts read at close time are the facts the step is about'),
      jsonb_build_object('level', 'low', 'note', case when v_source like 'executor:%'
                                                      then 'a low-risk, advisory-safe, reversible executor was invoked; moves no money, sends nothing, approves nobody'
                                                      else 'determination only; moves no money, sends nothing, approves nobody' end),
      v_sim,
      jsonb_build_object('mode', v_mode, 'gate', coalesce(sr.input->>'gate', 'none'), 'paid_provider', 'held', 'executor', v_exec_status),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', v_outcome, 'disposition', v_disp,
                         'determination_source', v_source, 'basis', 'facts of the step rendered against the corroborated record; no model call'),
      'pending', v_employee, v_dept, 'workflow_step',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time', 'facts_read_at', v_facts->>'read_at'),
      case when v_target is not null then array[v_target] else '{}'::text[] end,
      case when v_source like 'executor:%' then array[v_target] else '{}'::text[] end,
      case when v_exec_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('action_execution_id', v_exec_id)) end,
      case v_disp when 'determined' then 'determined from ' || v_bound || ' bound fact(s); queued for review'
                  when 'advisory_held_model' then 'determined from ' || v_bound || ' bound fact(s), but the step''s executor needs the held model; advisory until the hold lifts'
                  else 'no fact bound: the record applies as written; narrative is needed' end,
      'review_queued', 'close the workflow step with disposition ' || v_disp,
      'the run advances; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  -- Never a silent pass: the determination is queued for review, with everything needed to overturn it.
  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_step', v_dept,
          left(initcap(replace(v_disp, '_', ' ')) || ': ' || sr.workflow_key || ' step ' || sr.step_no || ' — ' || coalesce(sr.input->>'step',''), 240),
          left(v_outcome, 600),
          jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'step_run_id', sr.id, 'step_no', sr.step_no,
                             'employee', v_employee, 'playbook_record_id', v_pb_id,
                             'playbook_title', v_pb_title, 'similarity', v_sim, 'terms_matched', v_terms,
                             'decision_trace_id', v_trace, 'disposition', v_disp,
                             'determination_source', v_source, 'executor_status', v_exec_status,
                             'facts_bound', v_bound, 'used_llm', v_used_llm),
          'pending')
  returning id into v_review;

  -- The executor's parked/stranded attempt is superseded: fn_action_release_held must not re-run it at
  -- launch over a step that is already closed.
  update public.action_execution
     set status = 'cancelled', finished_at = coalesce(finished_at, now()),
         response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
           'superseded_at', now(), 'superseded_by', 'deterministic determination',
           'decision_trace_id', v_trace, 'prior_status', status)
   where workflow_step_run_id = sr.id and status in ('held','stalled');
  get diagnostics v_superseded = row_count;

  v_out := coalesce(p_output, '{}'::jsonb) || jsonb_build_object(
             'mode', v_mode,
             'deliverable', left(v_deliv, 20000),
             'outcome', left(v_outcome, 400),
             'disposition', v_disp,
             'determination_source', v_source,
             'executor_status', v_exec_status,
             'executor_kind', v_kind,
             'action_execution_id', v_exec_id,
             'facts_bound', v_bound,
             'facts', v_facts,
             'used_llm', v_used_llm,
             'used_llm_basis', 'measured at close: ' || v_llm || ' llm_attempt + ' || v_cost
                               || ' ai_cost_log row(s) by workflow_dispatch since the step was claimed at ' || sr.started_at,
             'decision_trace_id', v_trace,
             'review_queue_id', v_review,
             'review_status', 'pending',
             'superseded_executions', v_superseded);

  if v_queued then
    -- the step stays running with a queued execution; fn_workflow_step_sweep settles it when the
    -- executor answers, merging the response over this determination
    update public.workflow_step_run set output = v_out where id = sr.id;
    return jsonb_build_object('ok', true, 'advanced', 'awaiting executor ' || v_target, 'decision_trace_id', v_trace,
                              'review_queue_id', v_review, 'superseded_executions', v_superseded,
                              'disposition', v_disp, 'determination_source', v_source,
                              'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                              'facts_bound', v_bound, 'used_llm', v_used_llm);
  end if;

  v_res := public.fn_workflow_step_done(sr.workflow_run_id, sr.step_no, v_out, 'done');

  return jsonb_build_object('ok', true, 'advanced', v_res, 'decision_trace_id', v_trace,
                            'review_queue_id', v_review, 'superseded_executions', v_superseded,
                            'disposition', v_disp, 'determination_source', v_source,
                            'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                            'facts_bound', v_bound, 'used_llm', v_used_llm);
end
$function$;

revoke execute on function public.fn_workflow_step_facts(bigint) from public;
revoke execute on function public.fn_workflow_step_render(jsonb, text, text, text, jsonb) from public;

-- ---------------------------------------------------------------------------------------------------
-- 4. fn_workflow_step_sweep: the settle MERGES the step's existing output under the executor response
--    (one clause; everything else is workflow_loop_turns_model_off.sql verbatim).
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_sweep(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text; v_out jsonb; v_parked int; v_noclass int;
        v_cap int; v_reflection_today int; v_throttled int; v_true_stall int; v_status text; v_note text;
        v_ineligible int; v_why text; v_held boolean;
begin
  v_held := coalesce((public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean, false) = false;

  -- 1. SETTLE what the invoker has already finished. A determination stored on the step before its
  --    executor ran (fn_workflow_step_deterministic_done's queued-edge path) is kept under the response.
  for s in
    select x.status, x.response, x.executor, r.id sid, r.workflow_run_id, r.step_no, r.output prev_output
      from public.action_execution x
      join public.workflow_step_run r on r.id = x.workflow_step_run_id
     where x.workflow_step_run_id is not null
       and x.status in ('succeeded','failed')
       and r.finished_at is null
     order by r.id
     limit 50
  loop
    v_res := public.fn_workflow_step_done(
      s.workflow_run_id, s.step_no,
      coalesce(s.prev_output, '{}'::jsonb)
        || coalesce(s.response, '{}'::jsonb)
        || jsonb_build_object('worked_by', 'executor:' || coalesce(s.executor, '?'),
                              'executor_status', case when s.status = 'succeeded' then 'ran: ' else 'failed: ' end || coalesce(s.executor, '?'))
        || case when v_held then jsonb_build_object('used_llm', false, 'used_llm_basis', 'paid provider held (kernel K12) at settle time') else '{}'::jsonb end,
      case when s.status = 'succeeded' then 'done' else 'failed' end);
    v_settled := v_settled + 1;
  end loop;

  -- 1b. RE-QUEUE the executions the old fn_execution_sweep cancelled before the invoker ever ran them
  --     (observed=cancelled, never dispatched, no decision record, not superseded). A deterministic
  --     executor such as uptime_check or ai_health is simply run, late; a model-backed one stays for the
  --     dispatcher while the model is held. The idempotency key is the same row, so this is an UPDATE.
  for s in
    select x.id xid, r.id sid
      from public.action_execution x
      join public.workflow_step_run r on r.id = x.workflow_step_run_id
      join public.org_action_executor e on e.action_class = r.action_class and e.active
     where x.status = 'cancelled'
       and r.status = 'ready' and r.finished_at is null
       and x.response->>'invoker' is null
       and x.response->>'observed' = 'cancelled'
       and not (x.request ? 'decision_record_id')
       and not (x.response ? 'superseded_by')
       and e.kind in ('edge','rpc') and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human and coalesce(e.required_authority,'') <> 'founder'
       and not (v_held and public.fn_executor_needs_model(e.target))
     order by r.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    update public.action_execution
       set status = 'queued', finished_at = null,
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'requeued_at', now(),
             'requeue_reason', 'cancelled by fn_execution_sweep before the invoker ran it (no decision record was ever expected); re-queued 4 Sep 2026')
     where id = s.xid;
    update public.workflow_step_run set status = 'running' where id = s.sid and status = 'ready';
    v_q := v_q + 1;
  end loop;

  -- 2. QUEUE the ready steps a registered, low-risk, reversible edge executor can run WITHOUT
  --    delivering a message to a person — and, while the model is held, without needing the model.
  for s in
    select r.id, r.workflow_run_id, r.step_no, r.actor, r.action_class, r.input,
           e.target, e.risk_tier, e.reversible
      from public.workflow_step_run r
      join public.org_action_executor e on e.action_class = r.action_class
     where r.status = 'ready' and r.finished_at is null
       and e.kind in ('edge','rpc') and e.active
       and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human
       and coalesce(e.required_authority,'') <> 'founder'
       and not (v_held and public.fn_executor_needs_model(e.target))
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'workflow_step:' || r.id)
     order by r.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    v_key := 'workflow_step:' || s.id;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts,
                                        workflow_step_run_id)
    values (gen_random_uuid(), gen_random_uuid(), s.action_class, s.target, v_key,
            s.risk_tier, s.reversible,
            jsonb_build_object('workflow_step_run_id', s.id,
                               'workflow_run_id', s.workflow_run_id,
                               'step_no', s.step_no,
                               'actor', s.actor,
                               'input', coalesce(s.input, '{}'::jsonb),
                               'source', 'fn_workflow_step_sweep'),
            'queued', 0, s.id)
    on conflict (idempotency_key) do nothing;

    update public.workflow_step_run set status = 'running' where id = s.id and status = 'ready';
    v_q := v_q + 1;
  end loop;

  select count(*), count(*) filter (where action_class is null)
    into v_parked, v_noclass
    from public.workflow_step_run where status = 'ready' and finished_at is null;

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  select count(*) into v_reflection_today
    from public.action_execution x
   where x.workflow_step_run_id is not null
     and x.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(x.action_class);

  select count(*) into v_throttled
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready' and sr.finished_at is null
     and sr.action_class is not null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and not public.fn_task_is_demand(sr.action_class)
     and v_reflection_today >= v_cap;

  select count(*), string_agg(distinct why, '; ') into v_ineligible, v_why from (
    select sr.id,
           case when e.action_class is null then 'no executor is mapped to ' || sr.action_class
                when e.kind not in ('edge','rpc') then sr.action_class || ' is a ' || e.kind || ' executor and no invoker handles that kind'
                when not e.active then sr.action_class || ' executor is inactive'
                when e.risk_tier <> 'low' then sr.action_class || ' is risk_tier ' || e.risk_tier
                when not e.advisory_safe then sr.action_class || ' is not advisory_safe'
                when not e.reversible then sr.action_class || ' is not reversible'
                when e.notifies_human then sr.action_class || ' notifies a human'
                when v_held and public.fn_executor_needs_model(e.target) then
                     sr.action_class || ' runs on the paid model, which is held; the dispatcher works it deterministically'
                when exists(select 1 from public.action_execution x where x.workflow_step_run_id = sr.id)
                     and not exists(select 1 from public.action_execution x
                                     where x.workflow_step_run_id = sr.id
                                       and x.status in ('queued','running','succeeded')) then
                     sr.action_class || ' has only a terminal (cancelled/failed/held) action_execution; while the model is held the dispatcher works it deterministically'
           end as why
      from public.workflow_step_run sr
      left join public.org_action_executor e on e.action_class = sr.action_class
     where sr.status = 'ready' and sr.finished_at is null and sr.action_class is not null
  ) q where why is not null;
  v_ineligible := coalesce(v_ineligible, 0);
  v_true_stall := greatest(v_parked - v_noclass - v_throttled - v_ineligible, 0);

  v_out := jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(), 'model_held', v_held,
    'parked', v_parked, 'parked_without_action_class', v_noclass,
    'parked_throttled_by_reflection_ceiling', v_throttled,
    'reflection_worked_today', v_reflection_today, 'reflection_cap', v_cap,
    'parked_ineligible_by_policy', v_ineligible,
    'parked_ineligible_because', coalesce(v_why, ''),
    'parked_unexplained', v_true_stall,
    'ready_runnable', (select count(*) from public.workflow_step_run r
                         join public.org_action_executor e on e.action_class = r.action_class
                        where r.status = 'ready' and e.kind in ('edge','rpc') and e.active
                          and e.risk_tier='low' and e.advisory_safe and e.reversible
                          and not e.notifies_human),
    'ready_held_notifies_human', (select count(*) from public.workflow_step_run r
                                    join public.org_action_executor e on e.action_class = r.action_class
                                   where r.status = 'ready' and e.notifies_human),
    'never_finished', (select count(*) from public.workflow_step_run where finished_at is null));

  v_status := case when v_true_stall > 0 and v_q = 0 and v_settled = 0 then 'error' else 'ok' end;
  v_note := 'settled ' || v_settled || ', queued ' || v_q || ', parked ' || v_parked
         || ' (' || v_noclass || ' awaiting an action_class, ' || v_throttled
         || ' held by the reflection ceiling at ' || v_reflection_today || '/' || v_cap || ' today, '
         || v_ineligible || ' ineligible by policy'
         || case when v_why is null or v_why = '' then '' else ' (' || left(v_why, 300) || ')' end
         || ', ' || v_true_stall || ' unexplained)';
  if v_status = 'error' then
    v_note := 'STALLED: ' || v_true_stall || ' workflow step(s) are ready, carry an action_class, '
           || 'and are not explained by the reflection ceiling. ' || v_note;
  end if;

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('workflow_step_sweep', v_status, v_out, v_note, now(), now());

  if v_noclass > 0 then
    begin
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select 'exec', 'Classify the workflow steps no executor can run',
             v_noclass || ' workflow_step_run row(s) are ready with no action_class, so nothing can '
             || 'ever pick them up and their runs never complete. The gap is in the DEFINITIONS: '
             || 'employee_task, rfq_handling, payment, refund, complaint, supplier_onboarding, '
             || 'customer_registration, invoice_approval, campaign_publishing and '
             || 'supplier_suspension carry no action_class on any step. Classifying them will make '
             || 'the queued backlog FIRE, so check org_action_executor.notifies_human, risk_tier '
             || 'and reversible per class first - refund reaches Stripe and needs the founder.',
             'proposed', 'gated', false, 'incident_fix'
      where not exists (select 1 from public.org_tasks
                         where title = 'Classify the workflow steps no executor can run'
                           and status <> 'done');
    exception when others then null; end;
  end if;

  -- Stranded steps are the dispatcher's while the model is held (fn_workflow_step_claim). The dedup
  -- backlog task is raised only when the hold is NOT in force, i.e. when nothing else will take them.
  if not v_held and (select count(*) from public.workflow_step_run sr
               where sr.status='ready' and sr.finished_at is null and sr.action_class is not null
                 and exists(select 1 from public.action_execution x where x.workflow_step_run_id=sr.id)
                 and not exists(select 1 from public.action_execution x
                                 where x.workflow_step_run_id=sr.id and x.status in ('queued','running','succeeded'))) > 0 then
    begin
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select 'exec', 'Re-open workflow steps stranded by a cancelled action',
             (select count(*) from public.workflow_step_run sr
               where sr.status='ready' and sr.finished_at is null and sr.action_class is not null
                 and exists(select 1 from public.action_execution x where x.workflow_step_run_id=sr.id)
                 and not exists(select 1 from public.action_execution x
                                 where x.workflow_step_run_id=sr.id and x.status in ('queued','running','succeeded')))
             || ' workflow step(s) are ready but each has only a terminal (cancelled/failed) '
             || 'action_execution, so the sweep will not re-queue over it. Re-open them for a fresh '
             || 'attempt or drive the review-decision loop they await; a cancelled action must also settle its step.',
             'proposed', 'gated', false, 'incident_fix'
      where not exists (select 1 from public.org_tasks
                         where title = 'Re-open workflow steps stranded by a cancelled action'
                           and status <> 'done');
    exception when others then null; end;
  end if;

  return v_out;
end $function$;

-- ---------------------------------------------------------------------------------------------------
-- 5. fn_executor_needs_model reads fn_task_class, and that registry said cost_snapshot is
--    'content_drafting' ("Narrates the cost snapshot"). READ, not assumed: supabase/functions/
--    cost_snapshot/index.ts imports no llm helper and calls no gateway — its only outbound calls are
--    GET openrouter /credits (billing metadata, gated on paidOk), Apify and Twilio usage, and
--    alert_founder; scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs already
--    classifies it METADATA, not inference. A routing row for a function that never routes is a claim
--    the close was repeating as 'held: runs on the paid model' on every metric_lifecycle step 3.
--    Deactivated with the evidence in the note; the close now says the true reason it is withheld
--    (notifies_human) and the disposition is earned as 'determined'.
-- ---------------------------------------------------------------------------------------------------
update public.fn_task_class
   set active = false, updated_at = now(),
       note = coalesce(note, '') || ' | deactivated 5 Sep 2026: cost_snapshot/index.ts imports no llm helper and calls no gateway '
              || '(only openrouter /credits metadata, Apify/Twilio usage, alert_founder); it never routes through this class. '
              || 'See scripts/sql/a_deterministic_close_performs_the_step_2026_09_05.sql'
 where fn = 'cost_snapshot' and active;

commit;
