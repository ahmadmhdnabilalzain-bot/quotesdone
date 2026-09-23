-- GOVERNANCE READS KEYS AND REASONS, RATHER THAN SPOTTING WORDS — decision-point batch B7.
-- Seat: ceo (every point below is registered to the ceo seat in supabase/functions/_shared/decision_points.json;
-- the Arabic document cache is the sales_engineer's, the seat that prepares every customer and supplier document).
-- 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. Eight routines decided what a piece of text MEANS by spotting words in it. Measured on production today:
--   sql.fn_task_is_demand          action_class ~* '(invite|quote|rfq|...)'   -> is it revenue work (cost gate)
--   sql.fn_challenge               proposal ~* challenge_heuristic.pattern, headline's first word, a fee/price regex
--   sql.fn_what_if                 question ~* 'reveal fee|...' -> which scenario is simulated
--   sql.fn_notifications_founder_mail_policy  subject ~* 'critical|urgent' / 'fail|down|...' -> level of the routed task
--   sql.fn_notifications_digest    type ~* 'money|refund|...', subject ~* 'critical|...' -> never fold into the digest
--   sql.fn_governance_stamp        agent/kind ~* 'legal|financ|...' -> escalate for human review
--   sql.fn_kb_purge_clause         citation ~* '(\mUAE\M|...)' and fn_kb_is_us_code(citation) -> keep or delete knowledge
--   trade_glossary_ar (the cache half; the TS half is supabase/functions/_shared/reasoned_governance.ts)
--
-- WHAT. Each meaning now arrives as a KEY somebody chose or as a REASONED answer:
--   * a keyed registry where the input is already a closed vocabulary of our own keys: action_class_demand
--     (8 classes on production: analysis, knowledge_gap, routine_operational_decision + the ones the code writes),
--     governance_sensitive (agent_actions.kind values; 6 kinds on production, 6803 rows), notifications.severity
--     (the producer states it, exactly as fn_notify_founder already states p_level and p_kind);
--   * reasoning where the input is free text: fn_challenge, fn_what_if and the knowledge jurisdiction file a
--     question in the ceo seat's queue (fn_reason_hold) with named options; the replay (think.ts replayHeld, each
--     resilience_ping tick once the hold lifts) reasons it and fn_reason_apply_ceo__<surface> applies the answer.
--     Under the founder's hold nothing is guessed: the challenge is 'held' (the board abstains, the task review
--     records a non-blocking held dissent), the simulation is 'held', a citation with no reasoned jurisdiction is
--     KEPT (clause 4, never deleted), and an Arabic document with an untranslated line is not served.
--
-- MEASURED FACTS this rests on (production, 23 Sep 2026): kb_chunks 148,326 rows / 13,541 distinct citations;
-- challenge_heuristic 8 active rows; challenge_record 66 rows, last 7 Sep; decision_policy.alert_digest_types lists
-- 13 types; no org_task / workflow_step_run / action_execution carries an action_class outside the seeded list.
--
-- Follows a_reasoned_answer_is_applied_by_its_own_surface.sql (the resolver that calls fn_reason_apply_*).
-- Pending: scripts/sql/pending/governance_reads_keys_and_reasons_rather_than_spotting_words.txt.
-- Proved in one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs (the B7 probe).

-- ── 1. sql.fn_task_is_demand: the revenue path is a registered key, not a spelling ─────────────────────────
create table if not exists public.action_class_demand (
  action_class    text primary key check (action_class ~ '^[a-z_]+$'),
  on_revenue_path boolean not null,
  reason          text not null check (btrim(reason) <> ''),
  updated_at      timestamptz not null default now()
);
alter table public.action_class_demand enable row level security;
drop policy if exists action_class_demand_service_role_only on public.action_class_demand;
create policy action_class_demand_service_role_only on public.action_class_demand
  as permissive for all to public using (false) with check (false);
revoke all on public.action_class_demand from anon, authenticated;
comment on table public.action_class_demand is
  'Which org_task / workflow action_class is on the revenue path (someone outside the company at the other end). Read by fn_task_is_demand. A class with no row is NOT on the revenue path until someone registers it: its spelling decides nothing (founder_instruction 890).';

insert into public.action_class_demand (action_class, on_revenue_path, reason) values
  ('invite',                    true,  'a supplier is invited to the marketplace'),
  ('customer_onboarding_check', true,  'a customer is being onboarded'),
  ('matching',                  true,  'an inquiry is matched to suppliers'),
  ('refund',                    true,  'money goes back to a customer'),
  ('refund_within_window',      true,  'money goes back to a customer'),
  ('dispute_open',              true,  'a customer or supplier disputes an outcome'),
  ('pdpl_action',               true,  'a person exercises a data-protection right'),
  ('reputation_restore',        true,  'a supplier''s standing changes'),
  ('reputation_demote',         true,  'a supplier''s standing changes'),
  ('analysis',                  false, 'the company analysing itself'),
  ('knowledge_gap',             false, 'internal knowledge work'),
  ('knowledge_fill_gap',        false, 'internal knowledge work'),
  ('routine_operational_decision', false, 'internal operations'),
  ('recommend',                 false, 'an internal recommendation'),
  ('report_recommendation',     false, 'an internal recommendation'),
  ('exec_review',               false, 'an internal review'),
  ('investigate',               false, 'an internal investigation'),
  ('incident',                  false, 'platform operations'),
  ('incident_fix',              false, 'platform operations'),
  ('code_selfheal',             false, 'platform operations'),
  ('resilience_watch',          false, 'platform operations'),
  ('escalate_founder',          false, 'internal escalation'),
  ('coordinate',                false, 'internal coordination'),
  ('compliance_check',          false, 'internal compliance work'),
  ('change_deploy_baseline',    false, 'platform change control'),
  ('change_deploy_grade',       false, 'platform change control'),
  ('change_deploy_promote',     false, 'platform change control')
on conflict (action_class) do nothing;

-- STABLE (it reads a table now) and SECURITY DEFINER so the workspace's authenticated read of
-- fn_cos_work_gate keeps working while the registry itself stays service-role only.
create or replace function public.fn_task_is_demand(p_action_class text)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((select d.on_revenue_path from public.action_class_demand d where d.action_class = p_action_class), false)
$fn$;
revoke execute on function public.fn_task_is_demand(text) from public, anon;
grant execute on function public.fn_task_is_demand(text) to service_role, authenticated;
comment on function public.fn_task_is_demand(text) is
  'TRUE when the action_class is registered in action_class_demand as on the revenue path. Exact key, no pattern.';

-- ── 2. sql.fn_challenge: the proposal is reasoned against the principles, not pattern-matched ─────────────
-- The options are the active principles and the recent prior outcomes, by id; the replay picks the one the
-- proposal most directly conflicts with (or none) and fn_reason_apply_ceo__challenge writes the challenge.
drop function if exists public.fn_challenge(text, text, text);
create or replace function public.fn_challenge(p_proposal text, p_proposed_by text default 'founder',
  p_challenger text default 'brief', p_subject jsonb default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_opts jsonb; v_held bigint; v_req jsonb; v_q text;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', 'h' || h.id,
           'meaning', 'it conflicts with priority rank ' || h.rank_touched || ' (' || h.principle || '): ' || h.concern)
           order by h.rank_touched, h.id), '[]'::jsonb)
    into v_opts from public.challenge_heuristic h where h.active;
  v_opts := v_opts || coalesce((select jsonb_agg(jsonb_build_object('id', 'm' || m.id,
           'meaning', 'it repeats an earlier attempt that ended ' || m.outcome || ': ' || left(m.headline, 200)) order by m.created_at desc)
      from (select id, headline, outcome, created_at from public.institutional_memory
             where outcome in ('worse', 'improved') order by created_at desc limit 5) m), '[]'::jsonb);
  v_opts := v_opts || jsonb_build_array(jsonb_build_object('id', 'none',
           'meaning', 'it conflicts with none of these principles and repeats none of these attempts'));

  v_q := 'Proposal by ' || coalesce(p_proposed_by, 'unknown') || ': ' || coalesce(p_proposal, '');
  v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.challenge', 'question', left(v_q, 8000),
    'context', jsonb_build_object('audience', 'internal'),
    'decision', jsonb_build_object('name', 'challenge', 'options', v_opts),
    'subject', jsonb_build_object('proposal', p_proposal, 'proposed_by', p_proposed_by, 'challenger', p_challenger) || coalesce(p_subject, '{}'::jsonb),
    'dedupeKey', 'challenge:' || md5(coalesce(p_proposal, '') || '|' || coalesce(p_challenger, '')));
  v_held := public.fn_reason_hold('ceo', 'ceo.challenge', left(v_q, 8000), v_req, '{}'::jsonb, v_req->'subject',
                                  'sql_caller', v_req->>'dedupeKey');
  return jsonb_build_object('id', null, 'stance', 'held', 'held_id', v_held, 'confidence', 0,
    'conflicts_with', null, 'evidence', '[]'::jsonb, 'alternatives', '[]'::jsonb,
    'reasoning', 'The challenge of this proposal is filed for reasoning (held question #' || v_held
      || '); no stance is taken from the words it happens to use.');
end $fn$;
revoke execute on function public.fn_challenge(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_challenge(text, text, text, jsonb) to service_role;

create or replace function public.fn_reason_apply_ceo__challenge(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text; h record; m record;
  v_weight int := 0; v_stance text; v_conf numeric; v_reason text; v_alts jsonb := '[]'::jsonb;
  v_evidence jsonb := '[]'::jsonb; v_rank int; v_principle text; v_supply int; v_rev numeric; v_id bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    return jsonb_build_object('applied', false, 'reason', 'the choice is not one of the options filed');
  end if;
  if v_choice like 'h%' then
    select * into h from public.challenge_heuristic where id = substr(v_choice, 2)::bigint;
    if found then
      v_weight := case h.rank_touched when 1 then 3 when 2 then 2 else 1 end;
      v_rank := h.rank_touched; v_principle := h.principle; v_reason := h.concern;
      if h.alternative is not null then v_alts := jsonb_build_array(h.alternative); end if;
    end if;
  elsif v_choice like 'm%' then
    select * into m from public.institutional_memory where id = substr(v_choice, 2)::bigint;
    if found then
      v_evidence := jsonb_build_array(jsonb_build_object('type', 'prior_outcome', 'verdict', m.outcome, 'lesson', left(m.detail, 240)));
      if m.outcome = 'worse' then v_weight := 3; v_reason := 'A prior attempt on record ended worse: ' || left(coalesce(m.detail, m.headline), 200) || '.'; end if;
    end if;
  end if;

  select count(*) into v_supply from public.leads where approval_status = 'approved';
  select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0) into v_rev from public.transactions where revealed_at > now() - interval '30 days';
  v_evidence := v_evidence || jsonb_build_array(jsonb_build_object('type', 'current_state', 'onboarded_suppliers', v_supply, 'revenue_30d_aed', v_rev),
                              jsonb_build_object('type', 'reasoning', 'held_id', p_id, 'answer', left(coalesce(p_result->>'answer', ''), 600)));

  if v_weight >= 3 then v_stance := 'recommend_against'; v_conf := least(0.95, 0.60 + v_weight * 0.05);
  elsif v_weight >= 1 then v_stance := 'concern'; v_conf := 0.65;
  else v_stance := 'support'; v_conf := 0.6;
       v_reason := 'Reasoned: no conflict with the priority hierarchy and no contrary prior outcome on record.'; end if;
  v_reason := coalesce(v_reason, left(coalesce(p_result->>'answer', ''), 600));
  if v_alts = '[]'::jsonb and v_stance <> 'support' then
    v_alts := jsonb_build_array('Run it as a bounded test with a named metric and a captured baseline, so it can be graded and reversed.');
  end if;

  insert into public.challenge_record (proposal, proposed_by, challenged_by, stance, confidence, reasoning,
                                       violates_rank, violates_principle, evidence, alternatives)
  values (r.subject->>'proposal', r.subject->>'proposed_by', r.subject->>'challenger', v_stance, v_conf, v_reason,
          v_rank, v_principle, v_evidence, v_alts)
  returning id into v_id;
  return jsonb_build_object('challenge_record_id', v_id, 'stance', v_stance, 'choice', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__challenge(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__challenge(bigint, jsonb) to service_role;

-- The board no longer reads a guessed stance: while the challenge is held every advisor abstains.
create or replace function public.fn_board_review(p_subject text, p_subject_ref text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare adv record; ch jsonb; v_rec text; v_conf numeric; v_supply int; v_rev numeric;
  n_pro int:=0; n_cond int:=0; n_against int:=0; v_out jsonb := '[]'::jsonb; v_held boolean;
begin
  ch := fn_challenge(p_subject,'board','board');
  v_held := (ch->>'stance') = 'held';
  select count(*) into v_supply from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';

  for adv in select * from board_advisor where active order by advisor_key loop
    if v_held then
      v_rec:='abstain'; v_conf:=0.5;
    elsif adv.advisor_key='risk' and (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.85;
    elsif adv.advisor_key='economist' and v_rev=0 then
      v_rec:='proceed_with_conditions'; v_conf:=0.7;
    elsif adv.advisor_key in ('customer','supplier') and v_supply=0 then
      v_rec:='abstain'; v_conf:=0.5;
    elsif (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.75;
    elsif (ch->>'stance')='concern' then
      v_rec:='proceed_with_conditions'; v_conf:=0.65;
    else
      v_rec:='proceed'; v_conf:=0.6;
    end if;

    insert into board_opinion (subject,subject_ref,advisor_key,recommendation,rationale,confidence)
    values (p_subject,p_subject_ref,adv.advisor_key,v_rec,
      adv.name||' ('||adv.lens||') asks: '||adv.asks||' — '||
      case when v_held then 'The challenge of this proposal is held for reasoning (question #'||(ch->>'held_id')||'); an opinion before it is reasoned would be a guess.'
        when v_rec='do_not_proceed' then 'On the evidence available this fails that test.'
        when v_rec='proceed_with_conditions' then 'Proceed only with a named metric, a captured baseline and a reversal path.'
        when v_rec='abstain' then 'There is no data on this side of the marketplace yet; an opinion would be invention.'
        else 'Nothing in this lens argues against it.' end, v_conf);

    if v_rec='proceed' then n_pro:=n_pro+1;
    elsif v_rec='proceed_with_conditions' then n_cond:=n_cond+1;
    elsif v_rec='do_not_proceed' then n_against:=n_against+1; end if;

    v_out := v_out || jsonb_build_array(jsonb_build_object('advisor',adv.name,'lens',adv.lens,'recommendation',v_rec,'confidence',v_conf));
  end loop;

  return jsonb_build_object('subject',p_subject,'proceed',n_pro,'with_conditions',n_cond,
    'against',n_against,'abstained',(select count(*) from board_advisor where active)-n_pro-n_cond-n_against,
    'board_verdict', case when v_held then 'HELD — the challenge is not yet reasoned'
                          when n_against>0 then 'DO NOT PROCEED' when n_cond>0 then 'PROCEED WITH CONDITIONS' else 'PROCEED' end,
    'challenge_stance', ch->>'stance', 'challenge_held_id', ch->'held_id', 'opinions', v_out);
end $fn$;
revoke execute on function public.fn_board_review(text, text) from public, anon, authenticated;
grant execute on function public.fn_board_review(text, text) to service_role;

-- ── 3. sql.fn_what_if: the scenario is a reasoned choice (or the caller's key), never a question regex ────
drop function if exists public.fn_what_if(text, jsonb);
create or replace function public.fn_what_if(p_question text, p_change jsonb default '{}'::jsonb, p_scenario text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_sup int; v_rev numeric; v_cost numeric; v_conv numeric; v_pool int;
  v_impact jsonb; v_conf numeric; v_id bigint; v_held bigint; v_req jsonb;
  v_d_rev numeric; v_d_leads numeric; v_d_profit numeric;
begin
  -- WHICH SCENARIO: the caller's key, or reasoning. Nothing is read out of the question's words.
  if p_scenario is null then
    v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.what_if', 'question', left(coalesce(p_question, ''), 8000),
      'context', jsonb_build_object('audience', 'internal'),
      'decision', jsonb_build_object('name', 'scenario', 'options', jsonb_build_array(
        jsonb_build_object('id', 'reveal_fee_discount', 'meaning', 'what happens if the reveal fee (the price customers pay) is lowered or discounted'),
        jsonb_build_object('id', 'ai_cost_double',      'meaning', 'what happens if the cost of AI models / LLM calls rises, e.g. doubles'),
        jsonb_build_object('id', 'supplier_invites',    'meaning', 'what happens if we invite or onboard more suppliers, or scale the supply side'),
        jsonb_build_object('id', 'market_expansion',    'meaning', 'what happens if we expand to a new market or country'),
        jsonb_build_object('id', 'unmodelled',          'meaning', 'any other question: no simulation model exists for it yet'))),
      'subject', jsonb_build_object('question', p_question, 'change', coalesce(p_change, '{}'::jsonb)),
      'dedupeKey', 'what_if:' || md5(coalesce(p_question, '') || '|' || coalesce(p_change::text, '')));
    v_held := public.fn_reason_hold('ceo', 'ceo.what_if', left(coalesce(p_question, ''), 8000), v_req, '{}'::jsonb, v_req->'subject',
                                    'sql_caller', v_req->>'dedupeKey');
    return jsonb_build_object('status', 'held', 'held_id', v_held, 'question', p_question,
      'note', 'Which scenario this question asks about is being reasoned (held question #' || v_held || '); the simulation runs when it is.');
  end if;

  select count(*) into v_sup from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';
  select coalesce(sum(cost_aed),0) into v_cost from ai_cost_log where occurred_at>now()-interval '30 days';
  select coalesce(sum(sendable),0) into v_pool from v_supply_gap;
  v_conv := 0.05;

  if p_scenario = 'reveal_fee_discount' then
    v_impact := jsonb_build_object('revenue_per_reveal','down by the discount percentage',
      'reveal_volume','unknown - no reveals have occurred, so elasticity is unmeasured',
      'net_revenue','indeterminate',
      'honest_answer','This cannot be simulated. Zero reveals have happened, so there is no price-response curve to extrapolate from. Any number would be invented.');
    v_conf := 0.15;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;

  elsif p_scenario = 'ai_cost_double' then
    v_impact := jsonb_build_object('current_monthly_ai_cost_aed',round(v_cost,2),'if_doubled_aed',round(v_cost*2,2),
      'share_of_total_budget', round(100.0*v_cost*2/nullif((select sum(monthly_aed) from department_budget),0),1)||'%',
      'mitigation','Model policy already routes by task class. Prompt-cache reads are '
        ||coalesce((select round(100.0*sum(cached_in_tokens)/nullif(sum(prompt_tokens),0),1)::text
                      from ai_cost_log where occurred_at > now() - interval '30 days'),'0')
        ||'% of prompt tokens over 30 days ('
        ||coalesce((select sum(cached_in_tokens)::text from ai_cost_log
                     where occurred_at > now() - interval '30 days'),'0')
        ||' read against '
        ||coalesce((select sum(cache_write_tokens)::text from ai_cost_log
                     where occurred_at > now() - interval '30 days'),'0')
        ||' written at a 1.25x premium), so caching pays only above roughly 22% and is measured here rather than assumed.');
    v_conf := 0.8;
    v_d_rev := null; v_d_leads := null; v_d_profit := -round(v_cost,2);

  elsif p_scenario = 'supplier_invites' then
    v_impact := jsonb_build_object('sendable_pool',v_pool,'expected_approved_at_5pct',round(v_pool*v_conv),
      'target',860,'shortfall',greatest(0,860-round(v_pool*v_conv)),
      'note','Assumes a 5% invite-to-approved conversion, which is an assumption not an observation - no invite has converted yet.');
    v_conf := 0.45;
    v_d_rev := null; v_d_leads := round(v_pool*v_conv); v_d_profit := null;

  elsif p_scenario = 'market_expansion' then
    v_impact := jsonb_build_object('home_market_readiness',(select count(*) from v_supply_gap where approved>=10)||' of 86 categories at target',
      'assessment','Expanding before the home market has any onboarded supply spreads a thin pool thinner and the category knowledge is UAE-specific.');
    v_conf := 0.7;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;
  else
    v_impact := jsonb_build_object('assessment','No model exists for this question yet. Add a scenario to scenario_library so it can be simulated rather than guessed.');
    v_conf := 0.2;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;
  end if;

  v_impact := v_impact || jsonb_build_object(
    'projected_revenue_delta_aed', v_d_rev,
    'projected_leads_delta',       v_d_leads,
    'projected_profit_delta_aed',  v_d_profit,
    'scenario', p_scenario,
    'delta_note', 'A null delta means this scenario does not model that dimension. It does not mean the delta is zero.');

  insert into simulations (scenario, result)
  values (jsonb_build_object('question',p_question,'change',p_change,'confidence',v_conf,'scenario',p_scenario),
          v_impact || jsonb_build_object('confidence', coalesce((v_impact->>'confidence')::numeric, v_conf)))
  returning id into v_id;

  if v_conf >= 0.5 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail,
                              target_table, target_id, confidence, evidence)
    values ('strategy_director', 'simulation_apply', 'pending', 'medium',
            left('Act on the simulation: ' || p_question, 200),
            coalesce(v_impact->>'assessment',
                     'The simulation returned a projection; open it to see the modelled figures.')
              || ' Approving this accepts the modelled change; the projection and its basis are on '
              || 'simulation #' || v_id || '.',
            jsonb_build_object('simulation_id', v_id, 'question', p_question,
                               'change', p_change, 'projection', v_impact),
            'simulations', v_id::text, v_conf,
            jsonb_build_object('basis', 'simulation #' || v_id || ' of "' || p_question || '"',
                               'simulation_id', v_id, 'confidence', v_conf, 'projection', v_impact));
  end if;

  return jsonb_build_object('id',v_id,'question',p_question,'projection',v_impact,'confidence',v_conf,'scenario',p_scenario,
    'basis', jsonb_build_object('approved_suppliers',v_sup,'revenue_30d',v_rev,'ai_cost_30d',round(v_cost,2),'sendable_pool',v_pool));
end $fn$;
revoke execute on function public.fn_what_if(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_what_if(text, jsonb, text) to service_role;

create or replace function public.fn_reason_apply_ceo__what_if(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text; v jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    return jsonb_build_object('applied', false, 'reason', 'the choice is not one of the options filed');
  end if;
  v := public.fn_what_if(r.subject->>'question', coalesce(r.subject->'change', '{}'::jsonb), v_choice);
  return jsonb_build_object('simulation_id', v->'id', 'scenario', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__what_if(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__what_if(bigint, jsonb) to service_role;

-- ── 4 + 5. notifications: severity is stated by the producer, never read out of the subject ──────────────
alter table public.notifications add column if not exists severity text;
alter table public.notifications drop constraint if exists notifications_severity_check;
alter table public.notifications add constraint notifications_severity_check
  check (severity is null or severity in ('info', 'warn', 'high', 'critical'));
comment on column public.notifications.severity is
  'How urgent the producer says this is (info|warn|high|critical). Read by fn_notifications_digest and fn_notifications_founder_mail_policy. NULL = not stated: never inferred from the subject.';

create or replace function public.fn_notifications_founder_mail_policy()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_admin text; v_phone text; v_kind text; v_allowed boolean; v_level text;
begin
  if coalesce(NEW.channel, 'email') not in ('email', 'whatsapp') then return NEW; end if;
  -- a format guard on OUR OWN fixture addresses (the reserved .invalid domain), not a reading of meaning
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;

  select lower(nullif(split_part(coalesce(value, ''), ',', 1), '')) into v_admin from public.app_secrets where key = 'admin_emails';
  select regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g') into v_phone from public.app_secrets where key = 'admin_mfa_phone';
  if not (coalesce(NEW.to_role, '') in ('founder', 'admin', 'owner')
          or (NEW.to_email is not null and lower(NEW.to_email) = coalesce(v_admin, 'management@quotesdone.com'))
          or (NEW.to_phone is not null and coalesce(v_phone, '') <> ''
              and regexp_replace(NEW.to_phone, '[^0-9]', '', 'g') = v_phone)) then
    return NEW;
  end if;

  v_kind := coalesce(nullif(btrim(NEW.kind), ''), nullif(btrim(NEW.type), ''), 'unregistered');
  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;
  if coalesce(v_allowed, false) then
    NEW.kind := v_kind;
    return NEW;
  end if;

  -- The routed task's level is what the producer STATED; unstated is filed at the normal level.
  v_level := coalesce(NEW.severity, case when NEW.type = 'founder_alert' then 'high' end, 'warn');
  begin
    perform public.fn_founder_mail_route(v_kind, NEW.subject, NEW.body, v_level);
  exception when others then
    insert into public.founder_alerts (level, event, detail, channel)
    values ('high', 'founder_mail:route_failed', left('kind ' || v_kind || ' / ' || coalesce(NEW.subject, '') || ' — ' || sqlerrm, 1000), 'os');
  end;
  return null;
end $fn$;
revoke execute on function public.fn_notifications_founder_mail_policy() from public, anon, authenticated;
grant execute on function public.fn_notifications_founder_mail_policy() to service_role;

create or replace function public.fn_notifications_digest()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare types jsonb;
begin
  if coalesce(NEW.channel,'email') <> 'email' then return NEW; end if;
  if NEW.status is not null and NEW.status not in ('queued','pending') then return NEW; end if;
  if coalesce(NEW.to_role,'') not in ('admin','founder','owner') then return NEW; end if;
  -- What the producer marked urgent always goes at once. Nothing else is inferred: only a type the policy
  -- lists BY NAME is folded into the brief.
  if NEW.severity in ('high', 'critical') then return NEW; end if;
  select value into types from public.decision_policy where key='alert_digest_types';
  if types is not null and types ? coalesce(NEW.type,'') then
    NEW.status := 'digest';
  end if;
  return NEW;
exception when others then
  return NEW;  -- a classifier error must never block a notification insert
end $fn$;
revoke execute on function public.fn_notifications_digest() from public, anon, authenticated;
grant execute on function public.fn_notifications_digest() to service_role;

-- ── 6. sql.fn_governance_stamp: sensitivity is a registered key ─────────────────────────────────────────
create table if not exists public.governance_sensitive (
  subject    text not null check (subject in ('agent', 'kind')),
  key        text not null check (btrim(key) <> ''),
  reason     text not null check (btrim(reason) <> ''),
  updated_at timestamptz not null default now(),
  primary key (subject, key)
);
alter table public.governance_sensitive enable row level security;
drop policy if exists governance_sensitive_service_role_only on public.governance_sensitive;
create policy governance_sensitive_service_role_only on public.governance_sensitive
  as permissive for all to public using (false) with check (false);
revoke all on public.governance_sensitive from anon, authenticated;
comment on table public.governance_sensitive is
  'agent_actions agents and kinds that always need human review (legal, financial, compliance, security, money). Read by fn_governance_stamp by exact key; a kind is sensitive because it is registered here, never because of how it is spelled.';
insert into public.governance_sensitive (subject, key, reason) values
  ('kind', 'finance_alert',      'financial'),
  ('kind', 'finance_reminder',   'financial'),
  ('kind', 'refund',             'money back to a customer'),
  ('kind', 'duplicate_refund',   'money back to a customer'),
  ('kind', 'refund_ceo_summary', 'money back to a customer'),
  ('kind', 'price_move',         'pricing'),
  ('kind', 'payment',            'money'),
  ('kind', 'payout',             'money'),
  ('kind', 'pdpl_action',        'data-protection law')
on conflict (subject, key) do nothing;

create or replace function public.fn_governance_stamp()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_sensitive boolean;
begin
  v_sensitive := exists (select 1 from public.governance_sensitive g
                          where (g.subject = 'agent' and g.key = NEW.agent) or (g.subject = 'kind' and g.key = NEW.kind));
  if NEW.confidence is null then
    NEW.confidence := 0.9;
  end if;
  if NEW.evidence is null then
    NEW.evidence := jsonb_build_object('basis','deterministic rule from live platform data',
                                       'agent',NEW.agent,'kind',NEW.kind);
  end if;
  if NEW.escalated is not true and (coalesce(NEW.confidence,0) < 0.6 or v_sensitive) then
    NEW.escalated := true;
    NEW.escalation_reason := coalesce(NEW.escalation_reason,
      case when coalesce(NEW.confidence,0) < 0.6
           then 'Confidence below 0.60 threshold — human review required.'
           else 'Sensitive domain (registered in governance_sensitive) — human review required.' end);
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_governance_stamp() from public, anon, authenticated;
grant execute on function public.fn_governance_stamp() to service_role;

-- ── 7. sql.fn_kb_purge_clause: a citation's jurisdiction is reasoned, and undecided knowledge is KEPT ────
create table if not exists public.kb_citation_jurisdiction (
  citation_md5 text primary key check (citation_md5 ~ '^[0-9a-f]{32}$'),
  citation     text not null,
  jurisdiction text not null check (jurisdiction in ('quotesdone', 'uae', 'gcc', 'international', 'us', 'other_foreign')),
  held_id      bigint,
  reasoned_at  timestamptz not null default now()
);
alter table public.kb_citation_jurisdiction enable row level security;
drop policy if exists kb_citation_jurisdiction_service_role_only on public.kb_citation_jurisdiction;
create policy kb_citation_jurisdiction_service_role_only on public.kb_citation_jurisdiction
  as permissive for all to public using (false) with check (false);
revoke all on public.kb_citation_jurisdiction from anon, authenticated;
comment on table public.kb_citation_jurisdiction is
  'Which jurisdiction a kb_chunks citation belongs to, REASONED (surface ceo.kb_jurisdiction), keyed by md5(citation). A citation with no row is undecided and its knowledge is kept (fn_kb_purge_clause 4). US law is out of scope (UAE/GCC/international only).';

drop function if exists public.fn_kb_purge_clause(text, text, text);
create or replace function public.fn_kb_purge_clause(p_source_kind text, p_category text, p_jurisdiction text)
returns smallint
language sql immutable parallel safe
set search_path to 'public', 'pg_temp'
as $fn$
  select (case
    -- 1. KEEP — QuotesDone-authored (the source kind we wrote, our own category key namespaces, or reasoned ours)
    when p_source_kind in ('qd_kb_pack','company_faq','memory','generated','trade','material','document','library')
      or split_part(coalesce(p_category, ''), ':', 1) in ('cat', 'exec')
      or p_jurisdiction = 'quotesdone' then 1
    -- 2. KEEP — ever cited: a row-id join, applied by the caller (see fn_kb_purge_batch)
    -- 3. KEEP — a UAE or GCC authority
    when p_jurisdiction in ('uae', 'gcc') then 3
    -- 5. DELETE — US law or a US standard (founder instruction 535), or any other foreign body
    when p_jurisdiction in ('us', 'other_foreign') then 5
    -- 4. UNSURE, KEPT — an international standard a UAE document may adopt, or NOT YET REASONED
    else 4 end)::smallint;
$fn$;
revoke execute on function public.fn_kb_purge_clause(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_kb_purge_clause(text, text, text) to service_role;
drop function if exists public.fn_kb_is_us_code(text);

create or replace function public.fn_kb_purge_batch(p_limit integer default 2000)
returns table(batch_no integer, deleted_count bigint, deleted_bytes bigint, cursor_from bigint, cursor_to bigint, remaining_count bigint)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
set enable_seqscan to 'off'
set max_parallel_workers_per_gather to '0'
set lock_timeout to '2s'
as $fn$
declare
  v_planned bigint;
  v_done    bigint;
  v_from    bigint;
  v_to      bigint;
  v_batch   integer;
  v_deleted bigint;
  v_bytes   bigint;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_kb_purge_batch: p_limit must be 1..5000 (got %) — scripts/sql/the_purge_cannot_take_the_database_down.sql', p_limit;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then
    raise exception 'fn_kb_purge_batch: another purge batch is running — refusing to overlap it';
  end if;

  select sum(l.rows) into v_planned
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.clause = 5 and l.batch_no is null;
  if v_planned is null then
    raise exception 'fn_kb_purge_batch: no census in kb_purge_ledger — run scripts/kb/purge_kb_bulk.mjs, which writes it before the first batch';
  end if;

  select coalesce(max(l.id_to), 0), coalesce(max(l.batch_no), 0), coalesce(sum(l.rows), 0)
    into v_from, v_batch, v_done
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.batch_no is not null;
  v_batch := v_batch + 1;

  perform set_config('qd.export_change_bulk', 'kb_chunks', true);

  with pick as (
    select k.id
      from public.kb_chunks k
      left join public.kb_citation_jurisdiction j on j.citation_md5 = md5(k.citation)
     where k.id > v_from
       and public.fn_kb_purge_clause(k.source_kind, k.category, j.jurisdiction) = 5
       and k.id not in (select split_part(x, ':', 2)::bigint
                          from public.sales_decision_log s, unnest(s.cited) x
                         where x ~ '^kb_chunks:[0-9]+$')            -- clause 2 (a row-id FORMAT, not a meaning)
     order by k.id
     limit p_limit
  ), del as (
    delete from public.kb_chunks k
     using pick p
     where k.id = p.id
    returning k.id, k.source_kind, k.category, octet_length(k.content) as b
  ), rec as (
    insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, bytes, batch_no, id_from, id_to)
    select 'DELETE', 5, d.source_kind, d.category, count(*), sum(d.b), v_batch, v_from, (select max(id) from del)
      from del d
     group by d.source_kind, d.category
    returning rows, bytes, id_to
  )
  select coalesce(sum(r.rows), 0), coalesce(sum(r.bytes), 0), coalesce(max(r.id_to), v_from)
    into v_deleted, v_bytes, v_to
    from rec r;

  return query select v_batch, v_deleted, v_bytes, v_from, v_to,
                      greatest(v_planned - v_done - v_deleted, 0);
end $fn$;
revoke execute on function public.fn_kb_purge_batch(integer) from public, anon, authenticated;
grant execute on function public.fn_kb_purge_batch(integer) to service_role;

-- Files the next p_limit undecided citations in the ceo seat's queue (one question per distinct citation).
-- Run by the release operator after the hold lifts; under the hold the questions simply wait, and the
-- knowledge they cover is kept meanwhile (clause 4).
create or replace function public.fn_kb_jurisdiction_file(p_limit integer default 50)
returns integer
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c record; n integer := 0; v_req jsonb; v_opts jsonb;
begin
  v_opts := jsonb_build_array(
    jsonb_build_object('id', 'quotesdone',    'meaning', 'written by QuotesDone itself'),
    jsonb_build_object('id', 'uae',           'meaning', 'issued by or adopted by a UAE federal or emirate authority, free zone, municipality, civil defence or UAE utility'),
    jsonb_build_object('id', 'gcc',           'meaning', 'issued by a GCC body (e.g. GSO) or another GCC state''s authority'),
    jsonb_build_object('id', 'international', 'meaning', 'an international or European/British standard (ISO, IEC, EN, BS, Eurocode, CIBSE ...) that UAE specifications commonly adopt'),
    jsonb_build_object('id', 'us',            'meaning', 'United States law, a US agency or a US standards body, not cited as adopted by a UAE authority — out of scope'),
    jsonb_build_object('id', 'other_foreign', 'meaning', 'any other country''s law or body, or material unrelated to UAE construction and procurement'));
  for c in
    select distinct on (md5(k.citation)) md5(k.citation) as h, k.citation
      from public.kb_chunks k
     where k.citation is not null and btrim(k.citation) <> ''
       and public.fn_kb_purge_clause(k.source_kind, k.category, null) <> 1
       and not exists (select 1 from public.kb_citation_jurisdiction j where j.citation_md5 = md5(k.citation))
       and not exists (select 1 from public.reasoning_held_question q where q.dedupe_key = 'kb_jurisdiction:' || md5(k.citation))
     limit greatest(1, least(coalesce(p_limit, 50), 500))
  loop
    v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.kb_jurisdiction',
      'question', 'Which jurisdiction does this knowledge-library citation belong to? Citation: ' || left(c.citation, 2000),
      'context', jsonb_build_object('audience', 'internal'),
      'decision', jsonb_build_object('name', 'jurisdiction', 'options', v_opts),
      'subject', jsonb_build_object('citation_md5', c.h, 'citation', left(c.citation, 4000)),
      'dedupeKey', 'kb_jurisdiction:' || c.h);
    perform public.fn_reason_hold('ceo', 'ceo.kb_jurisdiction', v_req->>'question', v_req, '{}'::jsonb, v_req->'subject',
                                  'sql_caller', v_req->>'dedupeKey');
    n := n + 1;
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_kb_jurisdiction_file(integer) from public, anon, authenticated;
grant execute on function public.fn_kb_jurisdiction_file(integer) to service_role;

create or replace function public.fn_reason_apply_ceo__kb_jurisdiction(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  if v_choice is null or v_choice not in ('quotesdone', 'uae', 'gcc', 'international', 'us', 'other_foreign')
     or (r.subject->>'citation_md5') is null then
    return jsonb_build_object('applied', false, 'reason', 'no valid jurisdiction in the answer');
  end if;
  insert into public.kb_citation_jurisdiction (citation_md5, citation, jurisdiction, held_id)
  values (r.subject->>'citation_md5', r.subject->>'citation', v_choice, p_id)
  on conflict (citation_md5) do update set jurisdiction = excluded.jurisdiction, held_id = excluded.held_id, reasoned_at = now();
  return jsonb_build_object('citation_md5', r.subject->>'citation_md5', 'jurisdiction', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__kb_jurisdiction(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__kb_jurisdiction(bigint, jsonb) to service_role;

-- ── 8. trade_glossary_ar: Arabic is translated natively by reasoning and cached; never substituted ─────────
create table if not exists public.arabic_translation (
  source_md5 text primary key check (source_md5 ~ '^[0-9a-f]{32}$'),
  source     text not null,
  arabic     text not null check (arabic ~ '[؀-ۿ]'),
  held_id    bigint,
  created_at timestamptz not null default now()
);
alter table public.arabic_translation enable row level security;
drop policy if exists arabic_translation_service_role_only on public.arabic_translation;
create policy arabic_translation_service_role_only on public.arabic_translation
  as permissive for all to public using (false) with check (false);
revoke all on public.arabic_translation from anon, authenticated;
comment on table public.arabic_translation is
  'Native Arabic of a supplier''s or customer''s own words, written by reasoning (surface sales_engineer.document_arabic, _shared/reasoned_governance.ts). A document line with no row here is not printed half-translated: the Arabic document is held.';

create or replace function public.fn_arabic_translations(p_sources text[])
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_object_agg(t.source, t.arabic), '{}'::jsonb)
    from public.arabic_translation t
   where t.source_md5 = any (select md5(s) from unnest(coalesce(p_sources, '{}'::text[])) s)
$fn$;
revoke execute on function public.fn_arabic_translations(text[]) from public, anon, authenticated;
grant execute on function public.fn_arabic_translations(text[]) to service_role;

-- p_pairs: {"<source>": "<arabic>", ...}. A value with no Arabic script (a format check) is not stored.
create or replace function public.fn_arabic_translation_store(p_pairs jsonb, p_held_id bigint default null)
returns integer
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n integer;
begin
  if jsonb_typeof(p_pairs) is distinct from 'object' then return 0; end if;
  insert into public.arabic_translation (source_md5, source, arabic, held_id)
  select md5(e.key), e.key, btrim(e.value), p_held_id
    from jsonb_each_text(p_pairs) e
   where btrim(e.key) <> '' and e.value ~ '[؀-ۿ]'
  on conflict (source_md5) do update set arabic = excluded.arabic, held_id = excluded.held_id, created_at = now();
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke execute on function public.fn_arabic_translation_store(jsonb, bigint) from public, anon, authenticated;
grant execute on function public.fn_arabic_translation_store(jsonb, bigint) to service_role;

-- The replay of a held translation: the answer is ONE JSON object {"1": "<arabic of line 1>", ...} (the shape
-- reasoned_governance.arabicQuestion asks for); the numbers index subject.sources. Parsing it is a format.
create or replace function public.fn_reason_apply_sales_engineer__document_arabic(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_ans jsonb; v_pairs jsonb := '{}'::jsonb; i integer; v_src text; v_ar text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  begin
    v_ans := regexp_replace(btrim(coalesce(p_result->>'answer', '')), '^```(json)?\s*|\s*```$', '', 'g')::jsonb;
  exception when others then
    return jsonb_build_object('applied', false, 'reason', 'the answer is not one JSON object');
  end;
  if jsonb_typeof(v_ans) is distinct from 'object' or jsonb_typeof(r.subject->'sources') is distinct from 'array' then
    return jsonb_build_object('applied', false, 'reason', 'no sources or no object');
  end if;
  for i in 0 .. jsonb_array_length(r.subject->'sources') - 1 loop
    v_src := r.subject->'sources'->>i;
    v_ar := v_ans->>((i + 1)::text);
    if v_src is not null and v_ar is not null then v_pairs := v_pairs || jsonb_build_object(v_src, v_ar); end if;
  end loop;
  return jsonb_build_object('stored', public.fn_arabic_translation_store(v_pairs, p_id));
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__document_arabic(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sales_engineer__document_arabic(bigint, jsonb) to service_role;
