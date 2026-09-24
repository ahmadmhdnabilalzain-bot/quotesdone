-- REVEAL FOLLOW-UP AND DISPUTE FINDINGS BELONG TO THE SALES ENGINEER (24 Sep 2026; seat: sales_engineer, from customer_support).
--
-- The founder's seat map, 24 Sep 2026 (memory seat-ownership-map-24-sep, "a holy book"): the sales_engineer owns
-- "inquiries, drawings and documents, specs, matching, quotes, the comparison report, **reveals** and enterprise
-- accounts". customer_support "is the COMMUNICATION seat ... It does NOT own reveals." The approved job description
-- (ledger 983) keeps for support: deliver every message, and for a post-reveal dispute "collect evidence on time and
-- pass it to the CEO". GAPS.md, customer support gap 2 (WRONG-OWNED) named four places reveal work sat on support.
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only): post_reveal_dispute 0 rows; reasoning_held_question on a
-- customer_support.dispute_* surface 0 rows; seat_handoff_kind already holds deliberation.review sales_engineer ->
-- ceo; seat_duty customer_support.disputes is enabled and owned by customer_support.
--
-- WHAT THIS MOVES
--   1. The 7-day reveal outcome check (fn_reveal_outcome_check_tick) is REQUESTED by the sales_engineer. Support
--      still delivers it: the message goes through fn_seat_clock_deliver -> fn_customer_support_takes_delivery, and
--      the delivery result returns to the sales_engineer, which asked. Every other line is byte-identical to the
--      live body in complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql.
--   2. The post-reveal dispute's FINDING and its clock move to the sales_engineer: duty sales_engineer.disputes runs
--      fn_sales_engineer_disputes_tick, which reasons the fault on surface sales_engineer.dispute_fault
--      (fn_reason_apply_sales_engineer__dispute_fault), sends it to the CEO with the sales_engineer -> ceo
--      cross-family review, and owns the overdue-decision finding. The CEO still decides
--      (fn_ceo_decides_post_reveal_dispute, unchanged). The two customer_support routines they replace are dropped
--      and the customer_support.disputes duty row is deleted with them (no job without its owner).
--
-- WHAT STAYS WITH customer_support, ON PURPOSE:
--   * Dispute intake, opening the case and telling both parties (fn_customer_support_dispute_consider / _open), and
--     recording each party's evidence (fn_customer_support_dispute_evidence): that is support hearing the channel
--     and collecting evidence on time, which is the approved job description word for word.
--   * supplier_response_watch and the grant support.refund_investigate: the founder's own procedure of 9 Sep 2026
--     (a_refund_is_proved_by_silence_approved_by_the_ceo_and_paid_by_the_accountant.sql) is "the customer support
--     agent ... will be contacting the supplier ... he sends that to the CEO". Support keeps the RECORD of silence;
--     it decides nothing (the CEO decides, the accountant pays). Moving it would contradict his words.
--   * The rating ask 21 days after a reveal: support sends it, which is delivery.
--
-- ON APPLY, IN THE SAME COMMIT AS THE MANIFEST LINE (scripts/sql/pending/<this>.txt says so too):
--   scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs REGISTER key fn_customer_support_disputes_tick
--   becomes fn_sales_engineer_disputes_tick, and both dropped routines get a DROPPED.txt line.
--
-- Prevented by: scripts/checks/reveal_work_is_the_sales_engineers.test.mjs.
--   node scripts/apply_sql.mjs scripts/sql/reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql --apply --ddl

-- ── 1. the 7-day outcome check is the sales engineer's question; support delivers it ────────────────
create or replace function public.fn_reveal_outcome_check_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_days numeric := public.fn_seat_clock_policy('reveal_outcome_check_days', 7);
  v_rating int; d record; v jsonb; v_asked int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int into v_rating
    from public.app_secrets where key = 'rating_request_days_after_reveal';
  v_rating := coalesce(v_rating, 21);

  for d in
    select t.id as tx_id, t.quote_id, t.inquiry_id, t.supplier_id, c.email as cemail, c.locale as clocale,
           c.full_name as cname, public.fn_seat_clock_customer_is_fixture(c) as fixture,
           l.company_name, i.category
      from public.transactions t
      join public.customers c on c.id = t.customer_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where t.revealed_at is not null and t.quote_id is not null
       and t.revealed_at <= now() - make_interval(days => v_days::int)
       -- the rating ask owns day 21 onwards; the outcome check never lands on or after it
       and t.revealed_at >  now() - make_interval(days => v_rating)
       -- the same allowlist as fn_support_request_ratings_due: never a refunded or disputed reveal
       and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
       and coalesce(i.outcome, '') = '' and coalesce(i.status, '') <> 'completed'
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
       and not public.fn_seat_clock_asked('reveal_outcome_check:' || t.quote_id)
     order by t.revealed_at
  loop
    -- 24 Sep 2026: the sales_engineer asks (it owns reveals); customer_support delivers through its door.
    v := public.fn_seat_clock_deliver('sales_engineer', 'reveal_outcome_check', 'customer', d.cemail, d.fixture, d.clocale,
           'reveal_outcome_check',
           jsonb_build_object('name', d.cname, 'supplier', d.company_name, 'category', d.category),
           'reveal_outcome_check:' || d.quote_id, d.inquiry_id, d.quote_id, d.supplier_id);
    if coalesce((v->>'ok')::boolean, false) then v_asked := v_asked + 1;
    else v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('transaction_id', d.tx_id, 'reason', v->>'reason'));
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'asked', v_asked, 'not_written', v_skipped, 'days_after_reveal', v_days,
                            'rating_ask_day', v_rating);
end
$fn$;
revoke execute on function public.fn_reveal_outcome_check_tick(boolean) from public, anon, authenticated;

-- ── 2. the dispute finding and its clock ─────────────────────────────────────────────────────────
-- The clock: evidence closes when both parties answered or the date passed, then fault is reasoned by the
-- sales_engineer; a CEO decision past its date is a finding the CEO owns, recorded by the sales_engineer.
create or replace function public.fn_sales_engineer_disputes_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; d record; v_q bigint;
  v_review int := 0; v_overdue int := 0;
begin
  for d in select p.*, (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) as demo
             from public.post_reveal_dispute p left join public.customers c on c.id = p.customer_id
            where p.stage = 'evidence'
              and ((p.customer_evidence is not null and p.supplier_evidence is not null) or now() > p.evidence_due)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by p.id for update of p skip locked loop
    v_q := public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.dispute_fault',
      case when d.demo then 'ZZ DEMO ' else '' end
      || 'A customer and a supplier disagree about a job after the supplier''s details were revealed. On the statements and evidence of both parties, which finding does the evidence support?',
      jsonb_build_array(
        jsonb_build_object('id', 'customer_upheld', 'meaning', 'the customer''s complaint is supported: the supplier fell short of what was agreed'),
        jsonb_build_object('id', 'supplier_upheld', 'meaning', 'the supplier''s position is supported: the supplier did what was agreed'),
        jsonb_build_object('id', 'shared', 'meaning', 'both parties contributed to the problem'),
        jsonb_build_object('id', 'no_fault', 'meaning', 'the evidence shows no fault by either party, or is too thin to find one')),
      jsonb_build_object('raised_by', d.raised_by, 'opened_at', d.opened_at, 'evidence_due', d.evidence_due,
                         'customer', d.customer_evidence, 'supplier', d.supplier_evidence),
      jsonb_build_object('dispute_id', d.id), 'dispute_fault:' || d.id);
    update public.post_reveal_dispute set stage = 'review', fault_question_id = v_q where id = d.id;
    v_review := v_review + 1;
  end loop;

  for d in select p.id, p.decision_due, p.finding from public.post_reveal_dispute p
             left join public.customers c on c.id = p.customer_id
            where p.stage = 'ceo_decision' and now() > p.decision_due
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx loop
    perform public.fn_it_engineer_finding_upsert('dispute_decision_overdue:' || d.id,
      'Post-reveal dispute QD-D-' || lpad(d.id::text, 5, '0') || ' is past its decision date',
      'public.post_reveal_dispute / fn_ceo_decides_post_reveal_dispute', 'agent_facing', 1,
      jsonb_build_object('dispute_id', d.id, 'decision_due', d.decision_due, 'owner_seat', 'ceo'),
      '{}'::text[], array['the CEO''s decision: select public.fn_ceo_decides_post_reveal_dispute(<id>, <outcome>, <note>)'],
      'sales_engineer');
    v_overdue := v_overdue + 1;
  end loop;
  return jsonb_build_object('to_review', v_review, 'decision_overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_sales_engineer_disputes_tick() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_disputes_tick() to service_role;

-- The sales engineer's reasoned finding goes to the CEO, reviewed by a model of another family.
create or replace function public.fn_reason_apply_sales_engineer__dispute_fault(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; d public.post_reveal_dispute; v_rev jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into d from public.post_reveal_dispute where id = (h.subject->>'dispute_id')::bigint and stage = 'review' for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'the dispute is not awaiting a finding'); end if;
  update public.post_reveal_dispute
     set stage = 'ceo_decision', finding = v_choice, finding_reasoning = left(p_result->>'answer', 8000),
         finding_model = p_result->>'model', decision_due = public.fn_add_working_days(now(), 3)
   where id = d.id;
  -- the question and evidence are abstract and factual; the finding travels only in the proposal
  v_rev := public.fn_seat_duty_cross_review('post_reveal_dispute', 'sales_engineer', 'ceo',
    case when h.question like 'ZZ DEMO%' then 'ZZ DEMO ' else '' end
      || 'Review a finding on a post-reveal dispute between a customer and a supplier.',
    jsonb_build_object('dispute_id', d.id, 'raised_by', d.raised_by, 'customer', d.customer_evidence, 'supplier', d.supplier_evidence),
    jsonb_build_object('finding', v_choice), p_result, 'post_reveal_dispute', d.id::text);
  update public.post_reveal_dispute set review = v_rev where id = d.id;
  return jsonb_build_object('applied', true, 'dispute_id', d.id, 'finding', v_choice, 'review', v_rev);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__dispute_fault(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sales_engineer__dispute_fault(bigint, jsonb) to service_role;

-- A question already held on the old surface (0 measured on 24 Sep) is carried over rather than orphaned: its
-- applier is dropped below, and a held question with no applier would never be applied.
update public.reasoning_held_question
   set seat = 'sales_engineer', surface = 'sales_engineer.dispute_fault'
 where surface = 'customer_support.dispute_fault' and applied_at is null;

delete from public.seat_duty where duty = 'customer_support.disputes';
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.disputes', 'sales_engineer', interval '30 minutes', 'fn_sales_engineer_disputes_tick',
   'post-reveal disputes: once support has collected both sides'' evidence (or the date passed), reason the finding for the CEO, and flag an overdue CEO decision',
   'scripts/sql/reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, owner_file)
values ('deliberation.review', 'sales_engineer', 'ceo',
        'the CEO reviews the sales engineer''s reasoned judgement (including a post-reveal dispute finding) on a model of another family',
        'fn_seat_deliberation_acts_on_handoff', interval '2 days',
        'scripts/sql/reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql')
on conflict do nothing;

drop function if exists public.fn_customer_support_disputes_tick();
drop function if exists public.fn_reason_apply_customer_support__dispute_fault(bigint, jsonb);
