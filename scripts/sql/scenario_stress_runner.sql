-- SECTION 34 — ORGANIZATIONAL STRESS TESTING. "All six named failure scenarios can be simulated."
--
-- TWO THINGS WERE MISSING, AND ONLY ONE OF THEM WAS THE DATA.
--
-- 1. Four of the six named scenarios were not in the library at all: OpenRouter outage, Supabase
--    outage, cash-flow reduction and campaign failure. (cyberattack and supplier fraud spike are
--    already covered by security_incident and duplicate_payment.)
--
-- 2. NOTHING IN THE DATABASE EVER RAN A SCENARIO. Measured 11 Aug 2026: the only two routines that
--    mention scenario_library are fn_capability_verify and fn_what_if, and neither writes last_run.
--    The twelve rows carrying a last_run are all dated 26-27 July and nothing has stamped one since.
--    scenario_library_three_forward_classes.sql (10 Aug) says so in its own header and correctly
--    refused to stamp last_run on the three scenarios it added: "none has been exercised yet and
--    pretending otherwise would be the fabrication."
--
--    So the honest way to make this requirement true is to build the thing that exercises a
--    scenario, not to write a timestamp into a column. That is fn_scenario_run below.
--
-- WHAT "EXERCISING" A SCENARIO MEANS HERE, AND WHAT IT REFUSES TO MEAN.
-- A stress test asks whether the ORGANISATION can respond to the failure. That is answerable
-- entirely from stored org state, deterministically and at zero model cost, and — critically — it
-- can FAIL: every department the scenario names must exist, be active, be staffed by at least one
-- active agent, and have a named manager. A scenario naming a department that is unstaffed returns
-- 'gap' and says which one. This is a test, not a stamp: if the org regresses, the next run says so.
--
-- It deliberately does NOT claim to have simulated the outage itself. Nothing here pretends to have
-- taken OpenRouter down. last_result records what was actually checked and what was actually found,
-- so a reader can tell the difference between "the org is staffed to answer this" and "this failure
-- was rehearsed end to end". The second is a bigger build and this file does not pretend to be it.

-- ── THE FOUR MISSING SCENARIOS ───────────────────────────────────────────────────────────────────
-- Each is grounded in a fact this company can point at today, not a generic risk-register entry.
insert into public.scenario_library (scenario_key, name, category, situation, expected_behaviour, departments, notes)
values
 ('openrouter_outage', 'OpenRouter becomes unavailable', 'continuity',
  'OpenRouter is unavailable or the shared balance reaches zero. Every AI call the company makes — all 93 employees, the Secretary, document reading, translation and supplier matching — runs on that one provider and one balance, so they stop together. On 11 Aug 2026 the balance was USD 10.70 against a measured burn, which is the state this scenario is written from.',
  'The AI department names the single point of failure explicitly rather than reporting a degraded service, states the remaining balance and the burn rate behind the runway, and distinguishes the two failure modes: a provider outage (transient, retry) and an exhausted balance (needs money, and only the founder can add it). Deterministic paths that do not need a model — FAQ answers, template replies, the level-0 router — must be named as what keeps working, because a company that reports total stoppage when 70% of its answers never needed a model is misreporting its own resilience. Escalation goes to the founder as a money decision, not as an incident.',
  array['ai_dept','engineering','exec','finance'],
  'Added 2026-08-11. The balance alert already fires below USD 20 via cost_snapshot and alert_founder; this scenario exists so the ORGANISATIONAL answer is rehearsed, not just the alarm.'),

 ('supabase_outage', 'The Supabase platform is unavailable', 'continuity',
  'The Supabase platform is down or the database is unreachable. Both projects, every edge function, every cron job, the OS console and the customer and supplier portals all sit on it, so a platform outage is a total stop rather than a degraded mode.',
  'Engineering states which of the two projects is affected and whether the failure is regional, and does not report a partial outage without naming which surface still answers. IT confirms whether the status page or the client is the source of the claim, because a client-side failure that looks like an outage has a different owner. The answer names what a reader can still be told — the last known-good state and when it was captured — rather than going silent, and it does not propose a migration in the middle of an incident.',
  array['engineering','it','exec'],
  'Added 2026-08-11. There is no second platform and no read replica, so the honest expected behaviour is a communication plan, not a failover. Saying that plainly is the point of the scenario.'),

 ('cash_flow_reduction', 'Cash flow drops and runway shortens', 'financial',
  'Cash flow reduces sharply. The marketplace has recognised AED 0 in revenue, so every cost the company carries is funded rather than earned and the runway is a function of spend alone. A liquidity reduction therefore hits the AI budget, the paid channel and any supplier onboarding spend at the same time.',
  'Finance answers with the measured position and refuses to project on a revenue line that has never produced: it names committed monthly spend, the largest single cost, and the resulting runway in days, and says explicitly that revenue is zero rather than folding a forecast into the number. The answer ranks what is cut first against the priority hierarchy rather than cutting proportionally, and it distinguishes spend that stops the company (the AI balance) from spend that only slows it (paid acquisition). Any cut that would halt the operating loop escalates to the founder.',
  array['finance','exec','marketing','ai_dept'],
  'Added 2026-08-11. fn_goal_attainment already refuses to quote an attainment rate without its denominator; this scenario asks the same discipline of the cash answer.'),

 ('campaign_failure', 'The marketing campaign fails to return', 'commercial',
  'A marketing campaign fails: spend goes out and no return comes back. Meta is the only paid acquisition channel and both campaigns sit paused at AED 0 spend, so this scenario is asked from a standing start rather than against a running baseline.',
  'Marketing states the campaign''s actual measured contribution before projecting the loss of it, so a channel contributing nothing cannot be reported as a risk of losing something. The answer separates the paid channel from SEO and direct, gives inquiries against target, and names the amount before recommending that anything be launched or refunded. A recommendation to spend more after a failure must carry the money and the metric that would grade it, or it is not a recommendation.',
  array['marketing','finance','exec'],
  'Added 2026-08-11. fn_marketing_ai recommended launching the campaign daily from 30 July without ever naming an amount; that is the failure mode this scenario is written to catch.')
on conflict (scenario_key) do nothing;

-- ── THE RUNNER ───────────────────────────────────────────────────────────────────────────────────
-- Returns the verdict AND writes it. A scenario that names a department the org does not have, or
-- has but has not staffed, comes back 'gap' with the department named.
create or replace function public.fn_scenario_run(p_scenario_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  s public.scenario_library%rowtype;
  v_named text[]; v_missing text[] := '{}'; v_unstaffed text[] := '{}'; v_unmanaged text[] := '{}';
  v_dept text; v_verdict text; v_result text; v_staff int;
begin
  select * into s from public.scenario_library where scenario_key = p_scenario_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no scenario '||p_scenario_key);
  end if;

  v_named := coalesce(s.departments, '{}'::text[]);
  if array_length(v_named, 1) is null then
    -- A scenario that names nobody cannot be answered by anybody. That is a finding, not a pass.
    v_verdict := 'gap';
    v_result  := 'NOT RUNNABLE: the scenario names no department, so there is no owner to respond.';
  else
    foreach v_dept in array v_named loop
      if not exists (select 1 from public.org_departments d
                      where d.dept_key = v_dept and coalesce(d.active, true)) then
        v_missing := v_missing || v_dept;
      else
        select count(*) into v_staff from public.org_agents a
         where a.department = v_dept and coalesce(a.active, true);
        if coalesce(v_staff, 0) = 0 then v_unstaffed := v_unstaffed || v_dept; end if;
        -- org_departments names its manager in lead_agent; there is no manager_key on this table.
        if not exists (select 1 from public.org_departments d
                        where d.dept_key = v_dept
                          and nullif(btrim(coalesce(d.lead_agent, '')), '') is not null)
        then v_unmanaged := v_unmanaged || v_dept; end if;
      end if;
    end loop;

    if array_length(v_missing, 1) is not null or array_length(v_unstaffed, 1) is not null then
      v_verdict := 'gap';
    elsif array_length(v_unmanaged, 1) is not null then
      v_verdict := 'partial';
    else
      v_verdict := 'ready';
    end if;

    v_result := format(
      'ORG READINESS %s. %s department(s) named: %s. Absent or inactive: %s. Active but unstaffed: %s. Staffed but unmanaged: %s. Checked against org_departments and org_agents at %s UTC. This verifies the organisation can answer the scenario; it does not claim the failure itself was rehearsed.',
      upper(v_verdict), array_length(v_named, 1), array_to_string(v_named, ', '),
      coalesce(nullif(array_to_string(v_missing, ', '), ''), 'none'),
      coalesce(nullif(array_to_string(v_unstaffed, ', '), ''), 'none'),
      coalesce(nullif(array_to_string(v_unmanaged, ', '), ''), 'none'),
      to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI'));
  end if;

  update public.scenario_library
     set last_run = now(), last_result = v_result
   where scenario_key = p_scenario_key;

  return jsonb_build_object('ok', true, 'scenario_key', p_scenario_key, 'verdict', v_verdict,
    'departments', to_jsonb(v_named), 'missing', to_jsonb(v_missing),
    'unstaffed', to_jsonb(v_unstaffed), 'unmanaged', to_jsonb(v_unmanaged), 'result', v_result);
end $function$;

revoke all on function public.fn_scenario_run(text) from public;
revoke all on function public.fn_scenario_run(text) from anon;

create or replace function public.fn_scenario_run_all()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_out jsonb := '[]'::jsonb; v_one jsonb;
        v_ready int := 0; v_partial int := 0; v_gap int := 0;
begin
  for r in select scenario_key from public.scenario_library order by scenario_key loop
    v_one := public.fn_scenario_run(r.scenario_key);
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'scenario_key', r.scenario_key, 'verdict', v_one->>'verdict'));
    if v_one->>'verdict' = 'ready' then v_ready := v_ready + 1;
    elsif v_one->>'verdict' = 'partial' then v_partial := v_partial + 1;
    else v_gap := v_gap + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'ran', jsonb_array_length(v_out),
    'ready', v_ready, 'partial', v_partial, 'gap', v_gap, 'scenarios', v_out);
end $function$;

revoke all on function public.fn_scenario_run_all() from public;
revoke all on function public.fn_scenario_run_all() from anon;
