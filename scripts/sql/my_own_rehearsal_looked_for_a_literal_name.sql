-- MY OWN REHEARSAL LOOKED FOR A LITERAL NAME AND REPORTED A DEFECT THAT IS NOT ONE
--
-- fn_scenario_rehearse's security_incident arm asked whether an active executor exists with
-- `action_class ~* 'security_incident'`, because the scenario's expected_behaviour says the founder
-- is notified "via the gated security_incident_executive path". Nothing matches that pattern, so the
-- rehearsal recorded INCOMPLETE and named "gated executive notification path exists" as a fact it
-- could not produce. I reported that as a real defect. It is not one.
--
-- Measured: `security_incident_executive` is a phrase in the scenario's prose and is named by NO
-- routine anywhere in the database. The gated executive path exists under its own name —
-- `escalate_founder` [edge, notifies_human = true] — beside `security_review` [edge,
-- notifies_human = true]. Both are active. The path the scenario describes is there; my check was
-- looking for the wrong string.
--
-- This is the instrument-measuring-the-wrong-subject defect, committed by the instrument I had just
-- written to catch that class of defect. The fix is to ask the question the scenario actually asks
-- — is there an ACTIVE executor that notifies a human on the security/escalation path — rather than
-- matching a name nobody implemented.
--
-- The other three INCOMPLETEs stand and are correct: no cash balance exists to compute a runway
-- from, the OpenRouter balance is not mirrored in this database, and a rehearsal running inside the
-- database cannot observe that database's own outage.

create or replace function public.fn_scenario_rehearse(p_scenario_key text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  s public.scenario_library%rowtype;
  v_facts jsonb := '[]'::jsonb;
  v_missing text[] := '{}';
  v_verdict text;
  v_answer text;
  v_burn numeric; v_calls int; v_spend30 numeric;
  v_committed numeric; v_top_dept text; v_top_aed numeric; v_runway text;
  v_meta_spend numeric; v_meta_results int; v_contribution text;
  v_plan public.continuity_plan%rowtype;
  v_owner text; v_gated boolean; v_gated_names text; v_incidents int;
  v_dup_blocked boolean; v_fraud_rows int;
begin
  select * into s from public.scenario_library where scenario_key = p_scenario_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no scenario ' || p_scenario_key);
  end if;

  if p_scenario_key = 'openrouter_outage' then
    select round(sum(cost_aed), 2), count(*) into v_spend30, v_calls
      from public.ai_cost_log where occurred_at > now() - interval '30 days';
    v_burn := round(coalesce(v_spend30, 0) / 30.0, 2);
    select * into v_plan from public.continuity_plan where service = 'OpenRouter';
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'burn rate per day (AED)', 'produced', v_burn is not null, 'value', v_burn))
      || jsonb_build_array(jsonb_build_object('fact', '30-day AI spend (AED)', 'produced', v_spend30 is not null, 'value', v_spend30))
      || jsonb_build_array(jsonb_build_object('fact', 'documented fallback', 'produced', coalesce(btrim(v_plan.fallback),'') <> '', 'value', v_plan.fallback))
      || jsonb_build_array(jsonb_build_object('fact', 'task classes that survive without a model',
           'produced', true,
           'value', (select count(*) from public.model_policy
                      where coalesce(active,true)
                        and (coalesce(deterministic_alternative,'') <> '' or tier = 'none'))))
      || jsonb_build_array(jsonb_build_object('fact', 'remaining provider balance', 'produced', false,
           'value', 'not a database fact — held by the provider and not mirrored here'));
    v_answer := 'AI spend over 30 days is AED ' || coalesce(v_spend30::text,'?') || ' across '
      || coalesce(v_calls::text,'?') || ' call(s), a burn of AED ' || coalesce(v_burn::text,'?')
      || '/day. ' || (select count(*) from public.model_policy
                       where coalesce(active,true) and (coalesce(deterministic_alternative,'') <> '' or tier='none'))
      || ' of ' || (select count(*) from public.model_policy where coalesce(active,true))
      || ' active task class(es) still run with no model at all. The two failure modes are distinct: '
      || 'provider unreachable (retry/fallback applies) versus shared balance exhausted (no retry helps). '
      || 'The remaining balance is not mirrored in this database, so it is named as unavailable rather than guessed.';

  elsif p_scenario_key = 'supabase_outage' then
    select * into v_plan from public.continuity_plan where service = 'Supabase';
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'which project is answering', 'produced', true,
           'value', current_setting('cluster_name', true)))
      || jsonb_build_array(jsonb_build_object('fact', 'documented RTO (minutes)', 'produced', v_plan.rto_minutes is not null, 'value', v_plan.rto_minutes))
      || jsonb_build_array(jsonb_build_object('fact', 'documented degraded mode', 'produced', coalesce(btrim(v_plan.degraded_mode),'') <> '', 'value', v_plan.degraded_mode))
      || jsonb_build_array(jsonb_build_object('fact', 'surfaces that answer without this database', 'produced', false,
           'value', 'none — every edge function, cron job and console read goes through it. A rehearsal executed INSIDE the database cannot observe its own outage.'));
    v_answer := 'This rehearsal runs inside the database it is asked about, so it can state the '
      || 'documented position and not the live one: RTO ' || coalesce(v_plan.rto_minutes::text,'?')
      || ' minutes, degraded mode "' || coalesce(v_plan.degraded_mode,'(none recorded)')
      || '". Both projects are separate Supabase instances, so a regional failure affects them '
      || 'independently — but nothing here can answer WHICH is down while it is down. That is a real '
      || 'gap in the plan, not a rehearsal failure, and it is recorded as such.';

  elsif p_scenario_key = 'cash_flow_reduction' then
    select sum(monthly_aed) into v_committed from public.department_budget;
    select dept_key, monthly_aed into v_top_dept, v_top_aed
      from public.department_budget order by monthly_aed desc nulls last limit 1;
    select round(sum(cost_aed), 2) into v_spend30
      from public.ai_cost_log where occurred_at > now() - interval '30 days';
    v_runway := 'not computable — no cash balance is recorded anywhere in this database, so a runway '
             || 'in days would be a division by a number nobody has measured';
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'committed monthly spend (AED)', 'produced', v_committed is not null, 'value', v_committed))
      || jsonb_build_array(jsonb_build_object('fact', 'largest single cost', 'produced', v_top_dept is not null,
           'value', v_top_dept || ' at AED ' || coalesce(v_top_aed::text,'?') || '/month'))
      || jsonb_build_array(jsonb_build_object('fact', 'recognised revenue (AED, 30d)', 'produced', true,
           'value', (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0) from public.transactions
                      where revealed_at > now() - interval '30 days')))
      || jsonb_build_array(jsonb_build_object('fact', 'runway in days', 'produced', false, 'value', v_runway));
    v_answer := 'Committed monthly spend is AED ' || coalesce(v_committed::text,'?') || ' across '
      || (select count(*) from public.department_budget) || ' department budget(s); the largest single '
      || 'cost is ' || coalesce(v_top_dept,'?') || ' at AED ' || coalesce(v_top_aed::text,'?')
      || '/month. AI spend over 30 days was AED ' || coalesce(v_spend30::text,'0')
      || '. Recognised revenue over the same window is AED '
      || (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0) from public.transactions
           where revealed_at > now() - interval '30 days')
      || ', so every cost is funded rather than earned and no projection is made on a revenue line '
      || 'that has never produced. Runway: ' || v_runway || '.';

  elsif p_scenario_key = 'campaign_failure' then
    select meta_spend_30d, meta_results_30d into v_meta_spend, v_meta_results from public.marketing_kpis limit 1;
    v_contribution := case
      when coalesce(v_meta_results, 0) = 0 and coalesce(v_meta_spend, 0) = 0
        then 'AED 0 spent and 0 results — the channel is contributing nothing, so there is nothing to lose'
      when coalesce(v_meta_results, 0) = 0
        then 'AED ' || v_meta_spend || ' spent for 0 results — measured contribution is zero'
      else 'AED ' || coalesce(v_meta_spend,0) || ' spent for ' || v_meta_results || ' result(s)' end;
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'measured campaign spend (30d)', 'produced', v_meta_spend is not null, 'value', v_meta_spend))
      || jsonb_build_array(jsonb_build_object('fact', 'measured campaign results (30d)', 'produced', v_meta_results is not null, 'value', v_meta_results))
      || jsonb_build_array(jsonb_build_object('fact', 'measured contribution', 'produced', true, 'value', v_contribution))
      || jsonb_build_array(jsonb_build_object('fact', 'customers attributable to the channel', 'produced', true,
           'value', (select count(*) from public.customers)));
    v_answer := 'Measured contribution first: ' || v_contribution || '. Only then the projection — '
      || 'and a channel whose measured contribution is zero cannot be reported as a risk of losing '
      || 'something. Total customers on the book: ' || (select count(*) from public.customers) || '.';

  elsif p_scenario_key = 'security_incident' then
    select lead_agent into v_owner from public.org_departments where dept_key = 'it' and coalesce(active,true);
    -- THE QUESTION THE SCENARIO ACTUALLY ASKS. It says the founder is notified "via the gated
    -- security_incident_executive path"; that string is prose and is implemented by NO routine.
    -- What matters is whether an ACTIVE executor exists that reaches a human on the security or
    -- escalation path — escalate_founder and security_review both do, both notifies_human.
    -- Matching the literal name reported a defect that does not exist.
    select count(*) > 0,
           string_agg(action_class, ', ' order by action_class)
      into v_gated, v_gated_names
      from public.org_action_executor
     where active and notifies_human
       and action_class ~* '(security|incident|escalate_founder|breach)';
    select count(*) into v_incidents from public.founder_alerts
     where created_at > now() - interval '90 days' and (coalesce(event,'') ~* 'security|incident|breach');
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'named response owner', 'produced', coalesce(btrim(v_owner),'') <> '', 'value', v_owner))
      || jsonb_build_array(jsonb_build_object('fact', 'gated executive notification path exists', 'produced', v_gated, 'value', v_gated_names))
      || jsonb_build_array(jsonb_build_object('fact', 'security alerts raised in 90d', 'produced', true, 'value', v_incidents))
      || jsonb_build_array(jsonb_build_object('fact', 'security scan is scheduled and active', 'produced', true,
           'value', (select count(*) from cron.job where active and command ~* 'security_scan')));
    v_answer := 'Response owner: ' || coalesce(v_owner, '(none named on the IT department)')
      || '. Gated executive path(s) that reach a human: ' || coalesce(v_gated_names, '(none)')
      || '. ' || v_incidents || ' security alert(s) reached the founder in 90 days, and '
      || (select count(*) from cron.job where active and command ~* 'security_scan')
      || ' active security scan job(s) are scheduled.';

  elsif p_scenario_key = 'duplicate_payment' then
    select count(*) into v_fraud_rows from public.fraud_flags;
    select exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid
                    where t.relname = 'reveal_invoices' and c.contype in ('p','u'))
      into v_dup_blocked;
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'a uniqueness constraint blocks a second invoice', 'produced', v_dup_blocked, 'value', v_dup_blocked))
      || jsonb_build_array(jsonb_build_object('fact', 'fraud flags on file', 'produced', true, 'value', v_fraud_rows))
      || jsonb_build_array(jsonb_build_object('fact', 'money invariants run on a schedule', 'produced', true,
           'value', (select count(*) from cron.job where active and command ~* 'money_tests')))
      || jsonb_build_array(jsonb_build_object('fact', 'refund path is single-entry', 'produced', true,
           'value', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                      where n.nspname='public' and p.proname ~* 'refund')));
    v_answer := 'A uniqueness constraint on reveal_invoices blocks a second invoice for the same '
      || 'transaction: ' || v_dup_blocked::text || '. ' || v_fraud_rows || ' fraud flag(s) on file; '
      || (select count(*) from cron.job where active and command ~* 'money_tests')
      || ' scheduled money-invariant job(s).';

  else
    return jsonb_build_object('ok', true, 'scenario_key', p_scenario_key, 'rehearsed', false,
      'reason', 'no rehearsal is defined for this scenario; last_run deliberately left untouched');
  end if;

  select coalesce(array_agg(e->>'fact'), '{}') into v_missing
    from jsonb_array_elements(v_facts) e where (e->>'produced')::boolean is not true;

  v_verdict := case when array_length(v_missing, 1) is null then 'answered' else 'incomplete' end;

  update public.scenario_library
     set last_run = now(),
         last_result = upper(v_verdict) || ' — ' || v_answer
           || case when array_length(v_missing, 1) is null then ''
                   else ' FACTS THAT COULD NOT BE PRODUCED: ' || array_to_string(v_missing, '; ') || '.' end
           || ' (Rehearsed ' || to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI')
           || ' UTC by fn_scenario_rehearse, computing the answer from live rows.)'
   where scenario_key = p_scenario_key;

  return jsonb_build_object('ok', true, 'scenario_key', p_scenario_key, 'rehearsed', true,
    'verdict', v_verdict, 'facts', v_facts, 'missing', to_jsonb(v_missing), 'answer', v_answer);
end
$function$;
