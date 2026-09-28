-- A HIGH-STAKES DECISION WAITS FOR A SECOND SEAT ON ANOTHER MODEL FAMILY. Seat: it_engineer (shared platform,
-- every seat). 29 Sep 2026, founder_instruction 1009 upgrade 10 ("cross-seat challenge"); the family rule is
-- founder_instruction 841/844/873 (23 Sep).
--
-- WHAT ALREADY EXISTS AND IS REUSED, NOT COPIED: seat_deliberation (a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql).
-- It opens a review from one seat to another, runs the reviewer blind first, routes it through fn_ai_route_review
-- to another family than the author's, refuses a same-family turn in its trigger (SAME_FAMILY_REVIEW), and
-- refuses a comparison that does not state its agreements AND its disagreements. What it did not have is the
-- RULE: nothing said which decisions must pass through it, and nothing a decision path could ask before acting.
--
-- WHAT THIS ADDS
--   1. fn_high_stakes_reviewer(kind, author_seat): the four high-stakes kinds and who challenges each. The CEO
--      holds every approval (refunds included, 8 Sep ruling), so the CEO challenges; when the CEO is the author,
--      the accountant does. Every pair it names is already registered in seat_handoff_kind (measured 29 Sep 2026:
--      sales_engineer, marketing, accountant, customer_support, it_engineer -> ceo; ceo -> accountant).
--        pricing_change | campaign_launch | supplier_choice | refund
--   2. fn_high_stakes_challenge(kind, author_seat, subject_table, subject_id, question, evidence, proposal,
--      author_model, author_task_class, demo): opens ONE deliberation per decision (kind 'high_stakes.<kind>',
--      the subject is the decision); a second call returns the one already open.
--   3. fn_high_stakes_clearance(kind, subject_table, subject_id): what the decision path asks before it acts.
--        agreed                   the reviewer's comparison approved             cleared
--        disagreed                reject or revise; `reason` is its disagreements not cleared
--        held                     the model hold or the pair's ceiling held it   not cleared
--        pending                  opened, not yet reviewed                       not cleared
--        no_independent_reviewer  no model of another family was available       not cleared
--        not_challenged           no deliberation for this decision              not cleared
--      A disagreement is never without its reason: the turn trigger already refuses a comparison with an
--      empty disagreements field.
--
-- WHY IT IS NOT LIVE YET. Every reviewer turn needs a paid model, and the model hold is on; the pairs other than
-- marketing -> ceo also have no seat_deliberation_ceiling row, so fn_seat_deliberation_step holds them as
-- "pair_ceiling" before any routing. The clearance reports both as `held` and the decision waits. Lifting the
-- hold and setting those ceilings are the founder's numbers, not this file's.
--
-- Pending: scripts/sql/pending/a_high_stakes_decision_waits_for_a_second_seat_on_another_family.txt.
-- Proved by: scripts/eval/outcomes_and_cross_seat_challenge_proof.mjs (aborted transaction; the reviewer model is
-- stubbed by recording its turn directly, as advanceDeliberation would) and
-- supabase/functions/_shared/high_stakes_challenge.test.ts (stubbed model and database).

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
