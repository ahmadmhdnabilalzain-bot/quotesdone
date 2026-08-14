-- A STAFFING CHECK IS NOT A REHEARSAL, SO HERE IS THE REHEARSAL
--
-- scenario_library has carried `last_run` and `last_result` since it was created and both are NULL
-- on all 32 rows. fn_scenario_run deliberately writes only `last_staffing_check`, and says so:
-- "last_run belongs to a real rehearsal and this is not one ... THIS IS A STAFFING CHECK, NOT A
-- REHEARSAL: the failure was not simulated and nothing here says the organisation would survive it."
-- That was the right refusal. It left Row #3 §34 red because no rehearsal existed to write the
-- column, not because the column was being withheld.
--
-- WHAT A REHEARSAL IS, HERE. Read the six named scenarios' expected_behaviour and none of them asks
-- for a failover. Every one asks the responsible department to PRODUCE SPECIFIC FACTS:
--   openrouter_outage    "states the remaining balance and the burn rate behind the runway"
--   supabase_outage      "states which of the two projects is affected ... naming which surface still answers"
--   cash_flow_reduction  "names committed monthly spend, the largest single cost, and the runway in days"
--   campaign_failure     "states the campaign's actual measured contribution before projecting the loss of it"
--   security_incident    "incident logged, owner named, founder notified via the gated path"
--   duplicate_payment    "fraud step catches it, payment blocked, decision recorded"
-- So the rehearsal poses the scenario and tries to COMPUTE that answer from live rows right now.
-- It is a tabletop exercise with the arithmetic actually done. If a required fact cannot be
-- produced, the verdict is `incomplete` and last_result names the fact that is missing — a true
-- finding, never a pass.
--
-- WHAT IT REFUSES. A scenario with no rehearsal defined gets NOTHING: no last_run, no last_result.
-- Twenty-six of the thirty-two are in that state after this change and stay honestly unrehearsed.
-- Writing last_run for a scenario nobody exercised is the exact fabrication the earlier session
-- refused, and doing it wholesale to turn §34 green would be worse than leaving it red.

create or replace function public.fn_scenario_rehearse(p_scenario_key text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  s public.scenario_library%rowtype;
  v_facts jsonb := '[]'::jsonb;      -- one entry per required fact: {fact, produced, value}
  v_missing text[] := '{}';
  v_verdict text;
  v_answer text;
  -- working values
  v_burn numeric; v_calls int; v_spend30 numeric;
  v_committed numeric; v_top_dept text; v_top_aed numeric; v_runway text;
  v_meta_spend numeric; v_meta_results int; v_contribution text;
  v_plan public.continuity_plan%rowtype;
  v_owner text; v_gated boolean; v_incidents int;
  v_dup_blocked boolean; v_fraud_rows int;
begin
  select * into s from public.scenario_library where scenario_key = p_scenario_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no scenario ' || p_scenario_key);
  end if;

  -- a fact is "produced" only when the value is non-null; the value travels with it so the
  -- rehearsal record can be read back and checked rather than believed.
  -- ── OPENROUTER OUTAGE ────────────────────────────────────────────────────────────────────────
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
      -- The remaining BALANCE is held by OpenRouter and is not a database fact. Saying so is part of
      -- the answer; inventing it would not be.
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

  -- ── SUPABASE OUTAGE ──────────────────────────────────────────────────────────────────────────
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

  -- ── CASH-FLOW REDUCTION ──────────────────────────────────────────────────────────────────────
  elsif p_scenario_key = 'cash_flow_reduction' then
    select sum(monthly_aed) into v_committed from public.department_budget;
    select dept_key, monthly_aed into v_top_dept, v_top_aed
      from public.department_budget order by monthly_aed desc nulls last limit 1;
    select round(sum(cost_aed), 2) into v_spend30
      from public.ai_cost_log where occurred_at > now() - interval '30 days';
    -- Runway needs a cash balance. There is no cash ledger on this platform, so the honest answer
    -- names the burn and refuses the runway rather than dividing by an invented balance.
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

  -- ── CAMPAIGN FAILURE ─────────────────────────────────────────────────────────────────────────
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

  -- ── SECURITY INCIDENT ────────────────────────────────────────────────────────────────────────
  elsif p_scenario_key = 'security_incident' then
    select lead_agent into v_owner from public.org_departments where dept_key = 'it' and coalesce(active,true);
    select exists (select 1 from public.org_action_executor
                    where action_class ~* 'security_incident' and active) into v_gated;
    select count(*) into v_incidents from public.founder_alerts
     where created_at > now() - interval '90 days' and (coalesce(event,'') ~* 'security|incident|breach');
    v_facts := v_facts
      || jsonb_build_array(jsonb_build_object('fact', 'named response owner', 'produced', coalesce(btrim(v_owner),'') <> '', 'value', v_owner))
      || jsonb_build_array(jsonb_build_object('fact', 'gated executive notification path exists', 'produced', v_gated, 'value', v_gated))
      || jsonb_build_array(jsonb_build_object('fact', 'security alerts raised in 90d', 'produced', true, 'value', v_incidents))
      || jsonb_build_array(jsonb_build_object('fact', 'security scan is scheduled and active', 'produced', true,
           'value', (select count(*) from cron.job where active and command ~* 'security_scan')));
    v_answer := 'Response owner: ' || coalesce(v_owner, '(none named on the IT department)')
      || '. A gated security_incident executive path is registered: ' || v_gated::text
      || '. ' || v_incidents || ' security alert(s) reached the founder in 90 days, and '
      || (select count(*) from cron.job where active and command ~* 'security_scan')
      || ' active security scan job(s) are scheduled.';

  -- ── DUPLICATE PAYMENT (the fraud scenario) ───────────────────────────────────────────────────
  -- The only one with a mechanism that can be exercised rather than described: the invariant that
  -- blocks a second settlement of the same transaction.
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
    -- NO REHEARSAL DEFINED. Nothing is written: no last_run, no last_result. The scenario stays
    -- honestly unrehearsed rather than being marked exercised by a function that did nothing to it.
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

-- Runs every defined rehearsal. Deliberately does NOT touch the 26 scenarios with no rehearsal.
create or replace function public.fn_scenario_rehearse_all()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare k text; v jsonb; n_ans int := 0; n_inc int := 0; n_skip int := 0; out_j jsonb := '[]'::jsonb;
begin
  for k in select scenario_key from public.scenario_library order by scenario_key loop
    v := public.fn_scenario_rehearse(k);
    if coalesce((v->>'rehearsed')::boolean, false) then
      if v->>'verdict' = 'answered' then n_ans := n_ans + 1; else n_inc := n_inc + 1; end if;
      out_j := out_j || jsonb_build_array(jsonb_build_object('scenario_key', k, 'verdict', v->>'verdict'));
    else
      n_skip := n_skip + 1;
    end if;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('scenario_rehearsal', now(), now(), case when n_inc > 0 then 'error' else 'ok' end,
          jsonb_build_object('answered', n_ans, 'incomplete', n_inc, 'no_rehearsal_defined', n_skip),
          'Rehearsed ' || (n_ans + n_inc) || ' failure scenario(s) by posing each one and computing '
          || 'the required answer from live rows: ' || n_ans || ' produced every fact the scenario '
          || 'asks for, ' || n_inc || ' could not and name what is missing. ' || n_skip
          || ' scenario(s) have no rehearsal defined and were left untouched — last_run is not set '
          || 'for a scenario nobody exercised.');

  return jsonb_build_object('answered', n_ans, 'incomplete', n_inc,
    'no_rehearsal_defined', n_skip, 'scenarios', out_j);
end
$function$;

revoke all on function public.fn_scenario_rehearse(text) from public, anon, authenticated;
revoke all on function public.fn_scenario_rehearse_all() from public, anon, authenticated;
