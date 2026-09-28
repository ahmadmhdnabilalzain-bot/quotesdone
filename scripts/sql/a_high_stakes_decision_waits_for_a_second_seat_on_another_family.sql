-- A HIGH-STAKES DECISION WAITS FOR A SECOND SEAT ON ANOTHER MODEL FAMILY. Seat: it_engineer (shared platform,
-- every seat). 29 Sep 2026, founder_instruction 1009 upgrade 10 ("cross-seat challenge"); the family rule is
-- founder_instruction 841/844/873 (23 Sep); no spend caps is founder_instruction 987 (24 Sep).
--
-- WHAT ALREADY EXISTS AND IS REUSED, NOT COPIED: seat_deliberation (a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql).
-- It opens a review from one seat to another, runs the reviewer blind first, routes it through fn_ai_route_review to
-- another family than the author's, refuses a same-family turn in its trigger (SAME_FAMILY_REVIEW), and refuses a
-- comparison that does not state its agreements AND its disagreements. What it lacked was the RULE (which decisions
-- must pass through it) and a gate a decision path asks before it acts.
--
-- WHAT THIS FILE DOES
--   1. NO CAP HOLDS A REVIEW (instruction 987). fn_seat_deliberation_budget answered ok only for a pair with a
--      seat_deliberation_ceiling row, so every pair but marketing -> ceo was held as "pair_ceiling". It now answers ok
--      for every pair; the row, where there is one, only names the department the spend is reported against.
--   2. A DECISION TAKEN BY CODE CAN BE REVIEWED. A CEO refund approval and a founder-approved campaign are not written
--      by a model, so there is no model call to prove and no family to avoid. fn_seat_deliberation_open accepts
--      author model 'deterministic' (the router already answers "any family" for it) and the two guards record the
--      proposal's provider as 'deterministic'. Only these two lines change in each body.
--   3. THE RULE. fn_high_stakes_reviewer: pricing_change | campaign_launch | supplier_choice | refund. The CEO holds every
--      approval (8 Sep ruling), so the CEO challenges; when the CEO is the author, the accountant does. Every pair is
--      already registered in seat_handoff_kind (measured 29 Sep 2026).
--   4. THE GATE. fn_high_stakes_gate opens (or finds) the one deliberation for the decision and answers `proceed`:
--        agreed                          proceed
--        the model hold is on            proceed; the review is OWED (seat_deliberation.proceeded_at), and runs
--                                        on the resilience_ping heartbeat once the hold lifts
--        disagreed / pending / no reviewer / could not open, with no hold   do not proceed
--      fn_high_stakes_may_proceed is the read-only form for a STABLE check (the campaign publish refusal).
--   5. AFTER THE REVIEW (trg_high_stakes_review on seat_deliberation_turn): a disagreement with a decision that already
--      went ahead opens an it_engineer_finding owned by the deciding seat and lays the disagreement on its judgement as
--      a wrong outcome (fn_outcome_record, the sister file); an agreement with a pricing proposal that waited sends it
--      to the founder.
--   6. WIRED INTO THE FOUR REAL PATHS (bodies copied from their canonical files, only the gate added):
--        refund           fn_refund_decide, the approve branch      (payments_are_the_accountant_..._together.sql)
--        pricing_change   fn_ceo_review_applies, a propose_change   (routine_work_is_code_and_the_model_answers_only_real_judgement.sql)
--        campaign_launch  trg_high_stakes_campaign_approved opens the review when the founder approves; the publish
--                         refusal fn_marketing_post_publish_refusal waits for it (one_approve_schedules_...days.sql)
--        supplier_choice  quote_compare's top-three recommendation on a large job (supabase/functions/quote_compare)
--
-- APPLY ORDER: every_real_outcome_lands_on_the_seat_that_decided_it_with_its_reason.sql first (fn_outcome_record).
-- Pending: scripts/sql/pending/a_high_stakes_decision_waits_for_a_second_seat_on_another_family.txt.
-- Proved by: scripts/eval/outcomes_and_cross_seat_challenge_proof.mjs (aborted transaction, stubbed reviewer) and
-- supabase/functions/_shared/high_stakes_challenge.test.ts (stubbed model and database).
-- Prevented by: scripts/checks/every_real_outcome_lands_on_the_seat_that_decided_it.test.mjs.

alter table public.seat_deliberation add column if not exists proceeded_at timestamptz;
comment on column public.seat_deliberation.proceeded_at is
  'A high-stakes decision went ahead before its review (the model hold was on): the review is owed, and a later disagreement opens a finding.';

-- 1. NO CAP HOLDS A REVIEW. Spend is reported, never compared with a limit; every pair is allowed.
create or replace function public.fn_seat_deliberation_budget(p_author_seat text, p_reviewer_seat text, p_at timestamptz default now())
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('ok', true, 'dept', c.dept_key, 'spent_aed', s.spent,
           'why', 'reviews ' || p_author_seat || ' -> ' || p_reviewer_seat || ' spent AED ' || s.spent
                  || ' this month' || coalesce(' (' || c.dept_key || ')', '') || '; no limit (founder_instruction 987)')
    from (select 1) one
    left join public.seat_deliberation_ceiling c on c.author_seat = p_author_seat and c.reviewer_seat = p_reviewer_seat
    left join lateral (select coalesce(sum(l.cost_aed), 0) spent from public.ai_cost_log l
                        where l.task_class in ('seat_deliberation_blind', 'seat_deliberation_compare') and l.agent_key = p_reviewer_seat
                          and l.occurred_at >= (date_trunc('month', p_at at time zone 'Asia/Dubai') at time zone 'Asia/Dubai')) s on true
$fn$;

-- 2. A DECISION TAKEN BY CODE CAN BE REVIEWED (the two bodies below are the canonical ones with one change each).

create or replace function public.trg_seat_deliberation_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.author_model = 'deterministic' then
    new.author_provider := 'deterministic';   -- a decision taken by code (29 Sep 2026, instruction 1009)
  elsif tg_op = 'INSERT' or new.author_model is distinct from old.author_model then
    select lower(btrim(r.provider)) into new.author_provider from public.model_registry r where r.model_id = new.author_model;
    if new.author_provider is null then
      raise exception 'seat_deliberation: author model % is not in model_registry; its family cannot be known', new.author_model;
    end if;
  end if;
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.org_agents a where a.agent_key = new.author_seat and a.active)
       or not exists (select 1 from public.org_agents a where a.agent_key = new.reviewer_seat and a.active) then
      raise exception 'seat_deliberation: % and % must both be active seats', new.author_seat, new.reviewer_seat;
    end if;
  end if;
  return new;
end $fn$;

create or replace function public.trg_seat_deliberation_turn_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d public.seat_deliberation;
  v_prov text; v_auth_prov text; v_auth_model text; v_steel text;
begin
  if tg_op = 'UPDATE' then
    raise exception 'seat_deliberation_turn % is append-only: record a new turn instead', old.id;
  end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id;

  if new.model = 'deterministic' and new.phase = 'proposal' then
    -- A DECISION TAKEN BY CODE (29 Sep 2026, instruction 1009): no model wrote it, so any family may review it.
    new.provider := 'deterministic';
  elsif new.model is not null then
    select lower(btrim(r.provider)) into v_prov from public.model_registry r where r.model_id = new.model;
    if v_prov is null then
      raise exception 'seat_deliberation_turn: model % is not in model_registry', new.model;
    end if;
    if new.provider is not null and lower(btrim(new.provider)) <> v_prov then
      raise exception 'seat_deliberation_turn: provider % does not match model_registry (% is %)', new.provider, new.model, v_prov;
    end if;
    new.provider := v_prov;
  end if;

  if new.phase = 'proposal' then
    if new.seat <> d.author_seat or new.model is null or new.status <> 'recorded' then
      raise exception 'seat_deliberation_turn: a proposal is a recorded turn by the author seat % on a named model', d.author_seat;
    end if;
    return new;
  end if;

  if new.seat <> d.reviewer_seat then
    raise exception 'seat_deliberation_turn: a % turn belongs to the reviewer seat %, not %', new.phase, d.reviewer_seat, new.seat;
  end if;
  if new.reviews_turn_id is null then
    select t.id into new.reviews_turn_id from public.seat_deliberation_turn t
     where t.deliberation_id = new.deliberation_id and t.phase = 'proposal' and t.status = 'recorded' and t.round <= new.round
     order by t.round desc, t.id desc limit 1;
  end if;
  select lower(btrim(t.provider)), t.model into v_auth_prov, v_auth_model from public.seat_deliberation_turn t
   where t.id = new.reviews_turn_id and t.deliberation_id = new.deliberation_id and t.phase = 'proposal';
  if v_auth_prov is null then
    raise exception 'seat_deliberation_turn: a % turn must review a recorded proposal of the same deliberation', new.phase;
  end if;

  if new.provider = v_auth_prov then
    raise exception using errcode = 'check_violation',
      message = 'SAME_FAMILY_REVIEW: ' || new.model || ' (' || new.provider || ') may not review a proposal written on '
                || v_auth_model || ' (' || v_auth_prov || '). founder_instruction 873: the reviewer comes from another family.';
  end if;

  if new.status = 'recorded' then
    if new.model is null or new.verdict is null then
      raise exception 'MALFORMED_REVIEW: a recorded % turn names its model and its verdict', new.phase;
    end if;
    -- A steelman is a sentence of at least six words that is not a placeholder, and the comparison's is not
    -- the blind pass's copied forward. fn_seat_deliberation_record passes a steelman only when it is a JSON string.
    v_steel := public.fn_seat_deliberation_norm(new.steelman_against);
    if coalesce(array_length(regexp_split_to_array(nullif(v_steel, ''), ' '), 1), 0) < 6
       or v_steel ~ '^(none|n a|na|nil|nothing|tbd|not applicable|no (real |strong |serious |obvious )?(counter ?case|case against|counter ?argument|objection|concern|argument|risk|downside)s?|there (is|are) (nothing|no (counter ?case|case|objection|argument|risk|downside)s?))( |$)' then
      raise exception using errcode = 'check_violation',
        message = case when new.verdict = 'approve'
                       then 'MALFORMED_REVIEW: an approval without the strongest case against the proposal is malformed and is rejected'
                       else 'MALFORMED_REVIEW: every review turn states the strongest case against the proposal' end
                  || ' (at least six words, not a placeholder)';
    end if;
    if new.phase = 'compare' and exists (select 1 from public.seat_deliberation_turn b where b.deliberation_id = new.deliberation_id
          and b.phase = 'blind' and b.status = 'recorded' and public.fn_seat_deliberation_norm(b.steelman_against) = v_steel) then
      raise exception using errcode = 'check_violation',
        message = 'MALFORMED_REVIEW: the comparison''s steelman repeats the blind one; argue against the proposal now revealed';
    end if;
    if new.phase = 'compare' then
      if not exists (select 1 from public.seat_deliberation_turn b where b.deliberation_id = new.deliberation_id
                        and b.phase = 'blind' and b.status = 'recorded' and b.round <= new.round) then
        raise exception 'BLIND_FIRST: the reviewer compares only after its own blind verdict is recorded';
      end if;
      if coalesce(btrim(new.agreements), '') = '' or coalesce(btrim(new.disagreements), '') = '' then
        raise exception 'MALFORMED_REVIEW: a comparison states its agreements and its disagreements explicitly (write "none" if there are none)';
      end if;
    end if;
  end if;
  return new;
end $fn$;

create or replace function public.fn_seat_deliberation_open(p_kind text, p_author_seat text, p_reviewer_seat text,
  p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text, p_author_task_class text default null,
  p_subject_table text default null, p_subject_id text default null, p_demo boolean default false)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_h bigint; v_leak text; v_last text;
begin
  if not exists (select 1 from public.seat_handoff_kind k
                  where k.type = 'deliberation.review' and k.from_seat = p_author_seat and k.to_seat = p_reviewer_seat) then
    raise exception 'no deliberation.review conversation from % to % in seat_handoff_kind: register the pair in the file of the build that starts it',
      p_author_seat, p_reviewer_seat;
  end if;
  v_leak := public.fn_seat_deliberation_proposal_leak(p_proposal, coalesce(p_question, '') || ' ' || public.fn_seat_deliberation_strings(p_evidence));
  if v_leak is not null then
    raise exception 'BLIND_PASS_LEAK: the question or the evidence carries the proposal ("%"); the reviewer would not be blind', v_leak;
  end if;
  -- THE AUTHOR'S MODEL IS A MEASUREMENT, NOT A CLAIM: ai_gateway logged a call by this seat on this model in the
  -- last 24 hours, or the family the reviewer must avoid is unproven. Only a ZZ DEMO deliberation is exempt.
  -- The seat's LATEST successful call on the class that wrote the proposal must be on p_author_model.
  -- A decision taken by code ('deterministic') has no model call to prove (29 Sep 2026, instruction 1009).
  if not (coalesce(p_demo, false) and p_question like 'ZZ DEMO%') and p_author_model is distinct from 'deterministic' then
    if coalesce(btrim(p_author_task_class), '') = '' then
      raise exception 'AUTHOR_MODEL_UNPROVEN: name the task class the proposal was written on (p_author_task_class)';
    end if;
    select l.model_used into v_last from public.ai_cost_log l
     where l.ok and l.task_class = p_author_task_class and l.occurred_at > now() - interval '24 hours'
       and (l.agent_key = p_author_seat or l.seat = p_author_seat)
     order by l.occurred_at desc, l.id desc limit 1;
    if v_last is distinct from p_author_model then
      raise exception 'AUTHOR_MODEL_UNPROVEN: the latest successful % call by % in the last 24 hours was on %, not %',
        p_author_task_class, p_author_seat, coalesce(v_last, 'nothing'), p_author_model;
    end if;
  end if;
  insert into public.seat_deliberation (kind, author_seat, reviewer_seat, question, evidence, proposal, author_model,
                                        author_provider, subject_table, subject_id, demo)
  values (p_kind, p_author_seat, p_reviewer_seat, p_question, p_evidence, p_proposal, p_author_model, '?',
          p_subject_table, p_subject_id, coalesce(p_demo, false))
  returning id into v_id;
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, output)
  values (v_id, 1, 'proposal', p_author_seat, 'recorded', p_author_task_class, p_author_model, p_proposal);

  v_h := public.fn_seat_handoff(p_author_seat, p_reviewer_seat, 'deliberation.review', 'seat_deliberation', v_id::text,
           jsonb_build_object('deliberation_id', v_id, 'kind', p_kind, 'demo', coalesce(p_demo, false),
                              'question', left(p_question, 300)));
  update public.seat_deliberation set handoff_id = v_h where id = v_id;
  return v_id;
end $fn$;


-- 3. THE RULE, THE ONE DELIBERATION PER DECISION, AND ITS CLEARANCE.
create or replace function public.fn_high_stakes_reviewer(p_kind text, p_author_seat text)
returns text language sql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when p_kind in ('pricing_change', 'campaign_launch', 'supplier_choice', 'refund')
              then case when p_author_seat = 'ceo' then 'accountant' else 'ceo' end end
$fn$;
revoke execute on function public.fn_high_stakes_reviewer(text, text) from public, anon, authenticated;

create or replace function public.fn_high_stakes_challenge(p_kind text, p_author_seat text, p_subject_table text, p_subject_id text,
  p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text, p_author_task_class text default null, p_demo boolean default false)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_reviewer text := public.fn_high_stakes_reviewer(p_kind, p_author_seat); v_id bigint;
begin
  if v_reviewer is null then
    raise exception 'not a high-stakes kind: % (pricing_change, campaign_launch, supplier_choice, refund)', p_kind using errcode = '22023';
  end if;
  if coalesce(btrim(p_subject_table), '') = '' or coalesce(btrim(p_subject_id), '') = '' then
    raise exception 'a high-stakes challenge names the decision it is about (subject table and id)' using errcode = '22023';
  end if;
  select d.id into v_id from public.seat_deliberation d
   where d.kind = 'high_stakes.' || p_kind and d.subject_table = p_subject_table and d.subject_id = p_subject_id and d.status <> 'closed'
   order by d.id desc limit 1;
  if v_id is not null then return v_id; end if;
  return public.fn_seat_deliberation_open('high_stakes.' || p_kind, p_author_seat, v_reviewer, p_question, p_evidence, p_proposal,
    p_author_model, p_author_task_class, p_subject_table, p_subject_id, p_demo);
end $fn$;
revoke execute on function public.fn_high_stakes_challenge(text, text, text, text, text, jsonb, jsonb, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_high_stakes_challenge(text, text, text, text, text, jsonb, jsonb, text, text, boolean) to service_role;

create or replace function public.fn_high_stakes_clearance(p_kind text, p_subject_table text, p_subject_id text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; c public.seat_deliberation_turn; h public.seat_deliberation_turn; v_state text;
begin
  select * into d from public.seat_deliberation x
   where x.kind = 'high_stakes.' || p_kind and x.subject_table = p_subject_table and x.subject_id = p_subject_id
   order by x.id desc limit 1;
  if d.id is null then
    return jsonb_build_object('cleared', false, 'state', 'not_challenged', 'reason', 'no second seat has reviewed this decision');
  end if;
  select * into c from public.seat_deliberation_turn t
   where t.deliberation_id = d.id and t.phase = 'compare' and t.status = 'recorded' order by t.round desc, t.id desc limit 1;
  select * into h from public.seat_deliberation_turn t
   where t.deliberation_id = d.id and t.status = 'held_not_run' and t.round = d.round
     and not exists (select 1 from public.seat_deliberation_turn r where r.deliberation_id = d.id and r.round = t.round
                        and r.phase = t.phase and r.status = 'recorded')
   order by t.id desc limit 1;
  v_state := case when c.id is not null and c.round = d.round then case when c.verdict = 'approve' then 'agreed' else 'disagreed' end
                  when d.status = 'no_independent_reviewer' then 'no_independent_reviewer'
                  when h.id is not null then 'held'
                  else 'pending' end;
  return jsonb_build_object('cleared', v_state = 'agreed', 'state', v_state, 'deliberation_id', d.id,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat, 'author_model', d.author_model,
    'reviewer_model', c.model, 'verdict', c.verdict,
    'reason', case v_state when 'agreed' then c.agreements when 'disagreed' then c.disagreements when 'held' then h.why
                           when 'pending' then 'waiting for the ' || d.reviewer_seat || ' seat''s review'
                           else 'no model of another family was available; escalated' end);
end $fn$;
revoke execute on function public.fn_high_stakes_clearance(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_high_stakes_clearance(text, text, text) to service_role;


-- 4. THE GATE ─────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_high_stakes_model_held()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- The same probe llm_hold.ts asks: the hold is a gate rule, not a row count.
  select coalesce((g->>'allowed')::boolean, false) is not true and g->>'rule' in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state')
    from (select public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') g) x
$fn$;
revoke execute on function public.fn_high_stakes_model_held() from public, anon, authenticated;

create or replace function public.fn_high_stakes_gate(p_kind text, p_author_seat text, p_subject_table text, p_subject_id text,
  p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text default null, p_author_task_class text default null,
  p_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_model text := p_author_model; v_class text := p_author_task_class; v_id bigint; v_err text; v_held boolean; c jsonb; v_go boolean;
begin
  -- THE AUTHOR'S MODEL: the one given, else the seat's latest reasoning call in 24 hours (what open() proves), else code.
  if v_model is null then
    select l.model_used, l.task_class into v_model, v_class from public.ai_cost_log l
     where l.ok and l.task_class = 'agent_reasoning' and l.occurred_at > now() - interval '24 hours'
       and (l.agent_key = p_author_seat or l.seat = p_author_seat)
     order by l.occurred_at desc, l.id desc limit 1;
    v_model := coalesce(v_model, 'deterministic');
    if v_model = 'deterministic' then v_class := null; end if;
  end if;
  begin
    v_id := public.fn_high_stakes_challenge(p_kind, p_author_seat, p_subject_table, p_subject_id, p_question, p_evidence, p_proposal,
                                           v_model, v_class, p_demo);
  exception when others then
    v_err := sqlerrm;
    -- Recorded for the deciding seat, never raised: the decision path decides what a failed gate means.
    perform public.fn_it_engineer_finding_upsert('high_stakes_open:' || p_kind || ':' || p_subject_table || ':' || p_subject_id,
      'The second-seat review of a ' || p_kind || ' decision could not be opened', p_author_seat || ' ' || p_kind || ' on ' || p_subject_table,
      'agent_facing', 1, jsonb_build_object('owner_seat', p_author_seat, 'error', left(v_err, 500), 'subject_id', p_subject_id), '{}', '{}', 'it_engineer');
  end;
  v_held := public.fn_high_stakes_model_held();
  c := public.fn_high_stakes_clearance(p_kind, p_subject_table, p_subject_id);
  v_go := coalesce((c->>'cleared')::boolean, false) or (v_held and coalesce(c->>'state', '') <> 'disagreed');
  if v_go and not coalesce((c->>'cleared')::boolean, false) and v_id is not null then
    update public.seat_deliberation set proceeded_at = coalesce(proceeded_at, now()) where id = v_id;
  end if;
  return c || jsonb_build_object('proceed', v_go, 'owed', v_go and not coalesce((c->>'cleared')::boolean, false),
                                 'model_held', v_held, 'author_model', v_model, 'open_error', v_err);
end $fn$;
revoke execute on function public.fn_high_stakes_gate(text, text, text, text, text, jsonb, jsonb, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_high_stakes_gate(text, text, text, text, text, jsonb, jsonb, text, text, boolean) to service_role;

-- The read-only form for a STABLE check: agreed, or the decision already went ahead with its review owed.
create or replace function public.fn_high_stakes_may_proceed(p_kind text, p_subject_table text, p_subject_id text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((public.fn_high_stakes_clearance(p_kind, p_subject_table, p_subject_id)->>'cleared')::boolean, false)
      or exists (select 1 from public.seat_deliberation d where d.kind = 'high_stakes.' || p_kind and d.subject_table = p_subject_table
                    and d.subject_id = p_subject_id and d.proceeded_at is not null)
$fn$;
revoke execute on function public.fn_high_stakes_may_proceed(text, text, text) from public, anon, authenticated;

-- 5. AFTER THE REVIEW ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.trg_high_stakes_review()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation;
begin
  if new.phase <> 'compare' or new.status <> 'recorded' then return null; end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id and kind like 'high_stakes.%';
  if d.id is null then return null; end if;
  if new.verdict <> 'approve' and d.proceeded_at is not null then
    -- The decision already went ahead: the deciding seat gets a finding, and its judgement learns the disagreement.
    perform public.fn_it_engineer_finding_upsert('high_stakes_disagreement:' || d.id,
      'The ' || d.reviewer_seat || ' seat disagrees with a ' || substr(d.kind, 13) || ' decision that already went ahead',
      d.author_seat || ' ' || substr(d.kind, 13) || ' on ' || d.subject_table || ' ' || d.subject_id, 'agent_facing', 1,
      jsonb_build_object('owner_seat', d.author_seat, 'deliberation_id', d.id, 'verdict', new.verdict,
                         'disagreements', left(new.disagreements, 2000), 'reviewer_model', new.model, 'proceeded_at', d.proceeded_at),
      '{}', '{}', d.reviewer_seat);
    perform public.fn_outcome_record(d.subject_table, d.subject_id, 'challenge_disagreed', false,
      d.reviewer_seat || ' (' || new.model || '): ' || left(new.disagreements, 800), d.author_seat, substr(d.kind, 13), null);
  elsif new.verdict = 'approve' and d.proceeded_at is null and d.kind = 'high_stakes.pricing_change' and d.subject_table = 'ceo_review' then
    -- A pricing proposal that waited for the accountant reaches the founder now.
    perform public.fn_ceo_review_tells_founder(split_part(d.subject_id, ':', 1), split_part(d.subject_id, ':', 2)::date,
      'CEO pricing proposal (evidence-based) for the week of ' || split_part(d.subject_id, ':', 2),
      coalesce(d.proposal->>'founder_detail', '') || E'\n\nThe accountant agreed on a model of another family (seat_deliberation ' || d.id || ').',
      'founder_brief');
  end if;
  return null;
end $fn$;
revoke execute on function public.trg_high_stakes_review() from public, anon, authenticated;
drop trigger if exists z93_high_stakes_review on public.seat_deliberation_turn;
create trigger z93_high_stakes_review after insert on public.seat_deliberation_turn for each row execute function public.trg_high_stakes_review();

-- 6. CAMPAIGN LAUNCH: the founder's approval opens the CEO's review (the publish refusal below waits for it).
create or replace function public.trg_high_stakes_campaign_approved()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.approved_at is not null and old.approved_at is null and not new.is_demo then
    perform public.fn_high_stakes_gate('campaign_launch', 'marketing', 'marketing_campaign', new.id::text,
      'Should this month''s organic campaign be launched as approved?',
      jsonb_build_object('campaign', jsonb_build_object('month', new.month, 'spend_policy', new.spend_policy),
        'posts', (select count(*) from public.marketing_post p where p.campaign_id = new.id)),
      jsonb_build_object('campaign_key', new.campaign_key, 'theme', new.theme, 'title', new.title,
        'posts', (select jsonb_agg(jsonb_build_object('channels', p.channels, 'scheduled_at', p.scheduled_at, 'text', left(p.text_en, 300)) order by p.scheduled_at)
                    from (select * from public.marketing_post p where p.campaign_id = new.id order by p.scheduled_at limit 40) p)));
  end if;
  return null;
end $fn$;
revoke execute on function public.trg_high_stakes_campaign_approved() from public, anon, authenticated;
drop trigger if exists z93_high_stakes_campaign_approved on public.marketing_campaign;
create trigger z93_high_stakes_campaign_approved after update of approved_at on public.marketing_campaign
  for each row execute function public.trg_high_stakes_campaign_approved();

-- 6. THE THREE SQL PATHS, gated (canonical bodies, the gate added).

create or replace function public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.refunds; v_app public.ceo_approval; v_new text; v_gate jsonb;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status); end if;
  if coalesce(btrim(p_decided_by), '') = '' then return jsonb_build_object('ok', false, 'error', 'decider_required'); end if;
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. Approvals are the CEO''s.');
  end if;

  if p_approve then
    select * into v_app from public.ceo_approval a
     where a.subject_kind = 'refund' and a.subject_id = p_refund_id::text and a.decision = 'approved' and a.superseded_by is null
     order by a.decision_id desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_ceo_approval',
        'hint', 'A refund is approved only by a CEO approval that passed the process checklist (fn_ceo_refund_review, or ceo_agent decide). This routine records that decision; it cannot make one.');
    end if;
    -- A REFUND IS HIGH STAKES (29 Sep 2026, instruction 1009): a second seat on another family must agree first. While
    -- the model hold is on the refund proceeds and the review is owed; a later disagreement opens a finding.
    v_gate := public.fn_high_stakes_gate('refund', 'ceo', 'refunds', p_refund_id::text,
      'Should this refund be approved as the CEO decided?',
      jsonb_build_object('refund', jsonb_build_object('amount_fils', r.amount_fils, 'currency', r.currency, 'reason_code', r.reason_code,
        'reason_note', left(r.reason_note, 1000), 'requested_by', r.requested_by, 'within_auto_window', r.within_auto_window)),
      jsonb_build_object('decision', 'approve', 'ceo_rationale', left(v_app.rationale, 3000), 'amount_aed', v_app.amount_aed));
    if not coalesce((v_gate->>'proceed')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', 'awaiting_second_seat', 'clearance', v_gate);
    end if;
    update public.refunds set status = 'approved', decided_by = v_app.decided_by, decided_at = now(),
           decision_note = coalesce(p_note, v_app.rationale), refund_decision_id = v_app.decision_id
     where id = p_refund_id;
    v_new := 'approved';
  else
    update public.refunds set status = 'rejected', decided_by = p_decided_by, decided_at = now(), decision_note = p_note where id = p_refund_id;
    v_new := 'rejected';
  end if;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(), refund_note = coalesce(p_note, refund_note)
     where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', coalesce(v_app.decided_by, p_decided_by));
end $fn$;

create or replace function public.fn_ceo_review_applies(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_kind text; v_period date;
  rv public.ceo_review; v_review jsonb; v_notice jsonb; v_fields jsonb; v_gate jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_kind := r.subject->>'kind'; v_period := (r.subject->>'period')::date;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  select * into rv from public.ceo_review where kind = v_kind and period = v_period for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no review row'); end if;
  if rv.decided_at is not null then return jsonb_build_object('applied', true, 'already', v_kind || ' ' || v_period); end if;
  select coalesce(jsonb_object_agg(k, v->>'value'), '{}'::jsonb) into v_fields from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v);

  -- THE CHALLENGE (narrowed 24 Sep 2026, it_engineer): only a call that goes to the founder - a pricing proposal or
  -- "tell the founder" - is challenged by the accountant on a model of another family. An internal verdict is one call.
  -- A PRICING CHANGE IS HIGH STAKES (29 Sep 2026, instruction 1009): it goes to the founder only once the accountant agreed on
  -- another family, or, while the model hold is on, at once with the review owed.
  if v_kind = 'pricing_monitor' and v_choice = 'propose_change' then
    v_gate := public.fn_high_stakes_gate('pricing_change', 'ceo', 'ceo_review', v_kind || ':' || v_period,
      'Challenge the chief executive''s pricing call before it reaches the founder.',
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000),
                         'founder_detail', left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)),
      nullif(p_result->>'model', ''), 'agent_reasoning');
    v_review := v_gate;
  elsif v_choice in ('propose_change', 'tell_founder') then
    v_review := public.fn_seat_duty_cross_review('ceo.' || v_kind, 'ceo', 'accountant',
      case v_kind when 'management_review' then 'Challenge the chief executive''s reading of the company''s week.'
                  when 'pricing_monitor' then 'Challenge the chief executive''s pricing call before it reaches the founder.'
                  else 'Challenge the chief executive''s response to the revenue forecast.' end,
      -- seat_deliberation.evidence is capped at 60,000 characters; a week that outgrows it is passed as text, cut.
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
      p_result, 'ceo_review', v_kind || ':' || v_period);
  end if;
  update public.ceo_review set decision = v_choice, fields = v_fields, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', review = v_review, decided_at = now()
   where kind = v_kind and period = v_period;

  -- A pricing proposal still waiting for the accountant reaches the founder when the accountant agrees (trg_high_stakes_review).
  if (v_kind = 'pricing_monitor' and v_choice = 'propose_change' and coalesce((v_gate->>'proceed')::boolean, false))
     or (v_kind = 'target_forecast' and v_choice = 'tell_founder') then
    v_notice := public.fn_ceo_review_tells_founder(v_kind, v_period,
      case when v_kind = 'pricing_monitor' then 'CEO pricing proposal (evidence-based) for the week of ' || v_period
           else 'CEO: the AED 1M revenue forecast needs your decision (week of ' || v_period || ')' end,
      left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)
        || E'\n\nThe accountant is challenging this on a model of another family (seat_deliberation '
        || coalesce(v_review->>'deliberation_id', 'not opened: ' || coalesce(v_review->>'error', v_review->>'reason', '?')) || ').',
      case when v_kind = 'pricing_monitor' then 'founder_brief' else 'business_health_at_risk' end);
  end if;
  return jsonb_build_object('applied', true, 'kind', v_kind, 'period', v_period, 'choice', v_choice, 'review', v_review, 'founder', v_notice);
end $fn$;

create or replace function public.fn_marketing_post_publish_refusal(p public.marketing_post)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.marketing_campaign; v record; v_probs text[];
begin
  -- ZZ DEMO both ways: the flag OR the words anywhere that is published
  if p.is_demo or (p.text_en || ' ' || coalesce(p.text_ar, '') || ' ' || coalesce(p.title, '') || ' ' || coalesce(p.cta_url, '')) ~* 'zz[ _-]?demo'
     or exists (select 1 from public.marketing_post_variant x where x.post_id = p.id
                 and (x.body || ' ' || coalesce(x.title, '') || ' ' || coalesce(x.alt_text, '') || ' ' || coalesce(x.first_comment, '')) ~* 'zz[ _-]?demo') then
    return 'demo: a ZZ DEMO post is never published';
  end if;
  if p.campaign_id is null then return 'no_campaign: only a post of an approved campaign is published'; end if;
  select * into c from public.marketing_campaign where id = p.campaign_id;
  if c.is_demo then return 'demo: a ZZ DEMO campaign is never published'; end if;
  if c.spend_policy <> 'organic_only' then return 'spend: only organic campaigns are published'; end if;
  if c.approved_hash is null then return 'not_approved: the founder has not approved campaign ' || c.campaign_key; end if;
  if c.approved_hash <> public.fn_marketing_campaign_hash(c.id) then
    return 'approval_void: campaign ' || c.campaign_key || ' was edited after the founder approved it';
  end if;
  -- A CAMPAIGN LAUNCH IS HIGH STAKES (29 Sep 2026, instruction 1009): the CEO agreed on another family, or the review is owed.
  if not public.fn_high_stakes_may_proceed('campaign_launch', 'marketing_campaign', c.id::text) then
    return 'awaiting_second_seat: the CEO has not agreed to launch campaign ' || c.campaign_key || ' (fn_high_stakes_clearance)';
  end if;
  -- A slot missed by more than 30 minutes is not posted late (review of #874).
  if p.scheduled_at < now() - interval '30 minutes' then
    return 'missed_slot: due ' || to_char(p.scheduled_at at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai; reschedule and re-approve';
  end if;
  -- Founder, 24 Sep 2026: never on the UAE weekend or a UAE public holiday (the trigger moves such posts; this
  -- is the backstop for a row that reached the day some other way).
  if not public.fn_is_working_day((p.scheduled_at at time zone 'Asia/Dubai')::date) then
    return 'blocked_day: ' || to_char(p.scheduled_at at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' is a UAE weekend day or public holiday';
  end if;
  if not public.fn_marketing_publishing_on() then
    return 'kill_switch: app_secrets.marketing_publishing_enabled is false (emergency stop)';
  end if;
  if not exists (select 1 from public.marketing_post_variant x where x.post_id = p.id) then return 'no_variants'; end if;
  for v in select x from public.marketing_post_variant x where x.post_id = p.id loop
    v_probs := public.fn_marketing_variant_problems(v.x);
    if v_probs is null then return 'platform_specs_not_loaded: fn_marketing_platform_spec_problems does not exist'; end if;
    if cardinality(v_probs) > 0 then return 'platform_spec: ' || (v.x).platform || ' ' || array_to_string(v_probs, '; '); end if;
  end loop;
  return null;
end $fn$;
