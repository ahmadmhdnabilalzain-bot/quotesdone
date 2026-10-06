-- PROBE for the_ceo_reviews_the_months_video_plan_before_the_founder_sees_it.sql (it_engineer, 29 Sep 2026).
-- Pure probe: no DDL, ends in raise exception, so nothing it does survives - the founder mail it queues in step 8 is
-- rolled back with everything else and never reaches the outbox worker. Months November and December 2099 (the loop
-- starts with November); the probe asserts neither has a row before it starts, so it never disturbs a real plan.
-- 6 Oct 2026: the probe used November and December 2026 and refused on every run once real plans for those months
-- existed. It now runs in 2099 (same weekday calendar as 2026, so every tick date falls on the same weekday) and passes
-- each watch an explicit time in that year instead of now() + an offset, so the months it drafts can never be real.
do $p$
declare o jsonb := '{}'::jsonb; v jsonb; h1 bigint; h2 bigint; rh bigint; rq bigint; n_mail0 int; n_mail int; v_ok boolean;
  c_reasons constant text := 'Twelve videos is more than the founder can film in a month; cut to eight and move the two rotation '
                          || 'ideas on pricing to December, because registrations came from supplier stories, not from price talk.';
  c_approve constant text := 'Approved: eight videos on supplier stories match what brought registrations in September, and the '
                          || 'filming load now fits the founder''s month. The pricing ideas wait for December as marketing proposed.';
begin
  if exists (select 1 from public.marketing_month_plan where month in (date '2099-11-01', date '2099-12-01')) then
    raise exception 'CHK<<PROBE REFUSED: a real plan exists for November or December 2099; the probe will not touch it>>';
  end if;
  select count(*) into n_mail0 from public.notifications where to_role = 'founder' and kind = 'marketing_month_plan';

  -- 1. the tick drafts November and files it to the CEO, not the founder
  v := public.fn_marketing_month_plan_tick(date '2099-10-20');
  h1 := (v->'filed'->>'held_id')::bigint;
  select count(*) into n_mail from public.notifications where to_role = 'founder' and kind = 'marketing_month_plan';
  o := o || jsonb_build_object('t1_sent', v->'sent', 't1_status', (select status from public.marketing_month_plan where month = '2099-11-01'),
                               't1_held', (select status || ':' || surface from public.reasoning_held_question where id = h1),
                               't1_mail', n_mail - n_mail0);
  -- 2. under the hold the question is not replayed; the watch fires after two days and names the hold
  v := public.fn_ceo_marketing_plan_watch(timestamptz '2099-10-09 12:00+04');
  o := o || jsonb_build_object('w1_stalled', v->'review_stalled', 'w1_hold', v->'model_hold');
  -- 3. the CEO rejects with reasons: the ledger records it and marketing is asked to revise
  v := public.fn_reason_apply_ceo__marketing_month_plan(h1, jsonb_build_object('decision', jsonb_build_object('choice', 'reject'), 'answer', c_reasons));
  select a.id into rh from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.revise'
     and a.detail->>'item_key' = 'marketing_month_plan:2099-11-01';
  o := o || jsonb_build_object('r1', (select decision || ':' || round from public.ceo_decision_round where item_key = 'marketing_month_plan:2099-11-01' order by id desc limit 1),
                               'revise_to', (select agent from public.agent_actions where id = rh));
  -- 4. the tick waits for the revision, and never mails the founder
  v := public.fn_marketing_month_plan_tick(date '2099-10-21');
  o := o || jsonb_build_object('t2_why', v->'filed'->>'why');
  -- 5. marketing revises; the revision rides on the plan and goes to the CEO as round 2
  rq := (public.fn_seat_revises_for_the_ceo(rh)->>'held_id')::bigint;
  v := public.fn_ceo_revision_applies(rq, jsonb_build_object('decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
         'revision', 'Eight videos, all supplier stories; the two pricing ideas move to December.',
         'answers', 'Cut from twelve to eight as asked, and the pricing ideas moved to December because they brought no registrations.')),
         'answer', 'Revised to eight supplier-story videos; pricing moves to December.'));
  select ceo_held_id into h2 from public.marketing_month_plan where month = '2099-11-01';
  o := o || jsonb_build_object('rev_filed', v->'resubmission'->'filed', 'h2_round', (select subject->>'round' from public.reasoning_held_question where id = h2),
                               'revisions', (select jsonb_array_length(plan->'revisions') from public.marketing_month_plan where month = '2099-11-01'));
  -- 6. a stale answer on round 1 changes nothing
  v := public.fn_reason_apply_ceo__marketing_month_plan(h1, jsonb_build_object('decision', jsonb_build_object('choice', 'approve'), 'answer', c_approve));
  o := o || jsonb_build_object('stale', v ? 'already');
  -- 7. the CEO approves round 2 with reasons
  v := public.fn_reason_apply_ceo__marketing_month_plan(h2, jsonb_build_object('decision', jsonb_build_object('choice', 'approve'), 'answer', c_approve));
  o := o || jsonb_build_object('r2', (select decision || ':' || round from public.ceo_decision_round where item_key = 'marketing_month_plan:2099-11-01' order by id desc limit 1),
                               'status_after', (select status from public.marketing_month_plan where month = '2099-11-01'));
  -- 8. now, and only now, the founder gets it once - with the CEO's reasons and the round it took
  v := public.fn_marketing_month_plan_tick(date '2099-10-22');
  select count(*) into n_mail from public.notifications where to_role = 'founder' and kind = 'marketing_month_plan';
  o := o || jsonb_build_object('t3_sent', v->'sent', 't3_mail', n_mail - n_mail0,
                               't3_body_has_ceo', (select body like '%The CEO reviewed it and approved it in round 2%' and body like '%Round 1, the CEO asked%'
                                                     from public.notifications where id = (v->>'notification_id')::bigint));
  v := public.fn_marketing_month_plan_tick(date '2099-10-23');
  o := o || jsonb_build_object('t4_again', v->'sent');
  -- 9. the argued path owns a month it put to the CEO: the tick leaves it alone, and the watch fires on it
  insert into public.marketing_month_plan (month, status, plan) values ('2099-12-01', 'with_ceo', '{"topics":["ZZ DEMO"]}'::jsonb);
  insert into public.marketing_plan_review_turn (month, round, seat, move, reasoning, evidence, created_at)
  values ('2099-12-01', 1, 'marketing', 'propose', 'ZZ DEMO probe proposal: forty characters of reasoning at the least here.',
          '[{"kind":"probe","ref":"zz"}]'::jsonb, now());
  v := public.fn_marketing_month_plan_tick(date '2099-11-20');
  o := o || jsonb_build_object('argued_left_alone', v->>'reason', 'argued_status', (select status from public.marketing_month_plan where month = '2099-12-01'));
  v := public.fn_ceo_marketing_plan_watch(timestamptz '2099-11-25 12:00+04');
  o := o || jsonb_build_object('w2_month', v->'plan_month', 'w2_stalled', v->'review_stalled');

  v_ok := o->>'t1_sent' = 'false' and o->>'t1_status' = 'ceo_reviewing' and o->>'t1_held' = 'held:ceo.marketing_month_plan' and (o->>'t1_mail')::int = 0
      and o->>'w1_stalled' = 'true' and o->>'r1' = 'rejected:1' and o->>'revise_to' = 'marketing'
      and o->>'t2_why' = 'marketing owes the CEO a revision' and o->>'rev_filed' = 'true' and o->>'h2_round' = '2' and o->>'revisions' = '1'
      and o->>'stale' = 'true' and o->>'r2' = 'approved:2' and o->>'status_after' = 'ceo_approved'
      and o->>'t3_sent' = 'true' and (o->>'t3_mail')::int = 1 and o->>'t3_body_has_ceo' = 'true' and o->>'t4_again' = 'false'
      and o->>'argued_left_alone' = 'already planned' and o->>'argued_status' = 'with_ceo'
      and o->>'w2_month' = '2099-12-01' and o->>'w2_stalled' = 'true';
  raise exception 'CHK<<% %>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, o;
end $p$;
