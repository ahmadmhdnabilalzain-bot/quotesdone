-- THE CEO REVIEWS THE MONTH'S VIDEO PLAN BEFORE THE FOUNDER SEES IT (it_engineer, 29 Sep 2026).
--
-- WHAT WAS WRONG (read from the definitions live on 29 Sep 2026):
--   1. fn_marketing_month_plan_tick picked next month's 12 video ideas by code and mailed them straight to the founder
--      (fn_marketing_mail_founder, status 'sent_to_founder'). No CEO round. Worse, it went ahead when the month was
--      already 'with_ceo' on the argued-plan path, overwriting that status and mailing the founder mid-review.
--   2. fn_ceo_marketing_plan_watch raised "the CEO has not reviewed the plan" only when plan_sent_at was more than two
--      days old. On the argued path (status 'with_ceo', set by fn_marketing_step_accept) plan_sent_at is never set -
--      only the tick sets it, when it mails the founder - so the comparison was NULL and the watch could never fire.
--
-- THE FOUNDER'S RULE: the CEO reviews first, gives reasons, and a rejection goes back to the seat to revise and resubmit
-- until approved (ruling 1059, the ceo_decision_round machinery of #1128); the founder then approves the month once.
--
-- WHAT THIS DOES:
--   * ceo_decision_round takes a fifth path, 'marketing_month_plan' (item 'marketing_month_plan:<YYYY-MM-01>').
--   * The tick builds the plan exactly as before (fn_marketing_month_plan_ideas, split out unchanged) and files it
--     to the CEO (status 'ceo_reviewing', surface ceo.marketing_month_plan). It never mails the founder before the CEO
--     has approved, and it leaves a month the argued path owns ('with_ceo' and after) alone.
--   * fn_reason_apply_ceo__marketing_month_plan records the CEO's approve/reject WITH REASONS through fn_ceo_decide.
--     A reject opens ceo.revise to marketing; marketing's revision (fn_ceo_revision_applies, new route) is kept on the
--     plan and filed to the CEO as the next round. Four rejections owe the CEO replace/withdraw (the #1128 guard):
--     'replaced' re-drafts the month, 'withdrawn' leaves it unplanned ('rejected').
--   * Approved ('ceo_approved'): the next tick mails the founder the plan the CEO approved, with the CEO's reasons and
--     the rounds it took. The founder's one approval follows as before (videos, then the calendar "approve").
--   * The stall watch reads the time the plan reached the CEO on either path, so it fires; under the model hold the
--     finding says the wait is the hold.
-- The model hold stays on: the CEO question is held (fn_reason_held_due returns nothing under founder_hold) and is
-- reasoned when the hold lifts. Nothing reaches the founder while it waits.

-- ── 1. THE LEDGER TAKES THE PATH, THE PLAN TAKES TWO STATES ───────────────────────────────────────────────────
alter table public.ceo_decision_round drop constraint if exists ceo_decision_round_path_check;
alter table public.ceo_decision_round add constraint ceo_decision_round_path_check
  check (path in ('seat_deliberation', 'refund', 'ceo_experiment', 'ceo_improvement', 'marketing_month_plan'));

alter table public.marketing_month_plan drop constraint if exists marketing_month_plan_status_check;
alter table public.marketing_month_plan add constraint marketing_month_plan_status_check
  check (status in ('draft', 'with_ceo', 'agreed', 'brief_requested', 'sent_to_founder', 'accepted', 'rejected',
                    'ceo_reviewing', 'ceo_approved'));
alter table public.marketing_month_plan add column if not exists ceo_held_id bigint;
comment on column public.marketing_month_plan.ceo_held_id is
  'The CEO''s current held question on the coded video plan (surface ceo.marketing_month_plan); one per round.';

-- ── 2. THE IDEAS, BUILT AS BEFORE ───────────────────────────────────────────────────────────────────────────
-- Unchanged from fn_marketing_month_plan_tick (founder 24 Sep: routine, coded; 28 Sep, 1009: leans on what brought
-- registrations), split out so a 'replaced' round re-drafts the same way.
create or replace function public.fn_marketing_month_plan_ideas(p_today date, p_month date, p_include_demo boolean DEFAULT false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ideas jsonb; v_learned jsonb; v_shifted jsonb;
begin
  v_learned := public.fn_marketing_learning(date_trunc('month', p_today)::date, p_include_demo);
  -- topics that brought registrations, best per post first; only enabled ideas can be planned; at most 6 of 12
  with won as (select r->>'value' as topic, (r->>'per_post')::numeric as pp, (r->>'registrations')::int as n
                 from jsonb_array_elements(coalesce(v_learned->'dimensions'->'topic', '[]'::jsonb)) r
                where (r->>'registrations')::int > 0),
       ranked as (select i.id, i.idea_key, row_number() over (order by w.pp desc nulls last, w.n desc, i.id) as won_rank
                    from public.marketing_video_idea i join won w on w.topic in (i.idea_key, lower(i.title)) where i.enabled)
  select coalesce(jsonb_agg(idea_key order by won_rank), '[]'::jsonb) into v_shifted from ranked where won_rank <= 6;

  with days as (select d, row_number() over (order by d) n from public.fn_marketing_video_days(p_month, 12) d),
       picks as (select i.*, row_number() over (order by coalesce(array_position(array(select jsonb_array_elements_text(v_shifted)), i.idea_key), 1000),
                                                         i.last_planned_month nulls first, i.id) n
                   from public.marketing_video_idea i where i.enabled)
  select jsonb_agg(jsonb_build_object('n', d.n, 'date', d.d, 'idea_key', p.idea_key, 'title', p.title, 'hook', p.hook,
                                      'film_plan', p.film_plan, 'cta', p.cta, 'audience', p.audience,
                                      'why', case when v_shifted ? p.idea_key then 'brought registrations' else 'rotation' end) order by d.n)
    into v_ideas
    from days d join picks p on p.n = d.n;
  if v_ideas is null then raise exception 'marketing_month_plan: no enabled ideas or no working days in %', p_month; end if;
  return jsonb_build_object('by', 'code', 'ideas', v_ideas, 'learned', v_learned, 'shifted_to', v_shifted);
end $fn$;
revoke execute on function public.fn_marketing_month_plan_ideas(date, date, boolean) from public, anon, authenticated;

-- ── 3. THE PLAN GOES TO THE CEO ─────────────────────────────────────────────────────────────────────────────
-- Files the CEO's question for the item's current round. Idempotent (the dedupe key names the round). While marketing
-- owes a revision (a pending ceo.revise not yet resubmitted) it waits, unless the revision itself is the caller.
create or replace function public.fn_marketing_month_plan_to_ceo(p_month date, p_resubmitted boolean DEFAULT false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.marketing_month_plan; n jsonb; v_key text := 'marketing_month_plan:' || p_month; v_held bigint;
begin
  select * into p from public.marketing_month_plan where month = p_month;
  if p.month is null or p.status <> 'ceo_reviewing' or p.plan is null then
    return jsonb_build_object('filed', false, 'why', 'the plan is not with the CEO', 'status', p.status);
  end if;
  n := public.fn_ceo_decision_next(v_key);
  if not (n->>'open')::boolean then
    return jsonb_build_object('filed', false, 'why', 'the CEO closed the item: ' || (n->>'last_decision'));
  end if;
  if not p_resubmitted and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                                     and a.detail->>'type' = 'ceo.revise' and a.detail->>'item_key' = v_key
                                     and not coalesce(a.evidence, '{}'::jsonb) ? 'resubmitted_at') then
    return jsonb_build_object('filed', false, 'why', 'marketing owes the CEO a revision');
  end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.marketing_month_plan',
    'Marketing''s video plan for ' || to_char(p_month, 'FMMonth YYYY') || ': ' || jsonb_array_length(p.plan->'ideas')
      || ' short organic videos on UAE working days, chosen by code from what brought supplier registrations. '
      || 'As the chief executive, review it before it goes to the founder. Approve it, or reject it and say exactly what '
      || 'marketing must change. Either way give your reasons: they go to marketing and, on approval, to the founder.',
    '[{"id":"approve","meaning":"the plan goes to the founder for his one approval of the month"},{"id":"reject","meaning":"the plan goes back to marketing with your reasons, to revise and resubmit"}]'::jsonb,
    jsonb_build_object('month', p_month, 'ideas', p.plan->'ideas', 'shifted_to', p.plan->'shifted_to',
                       'learned', p.plan->'learned', 'revisions', coalesce(p.plan->'revisions', '[]'::jsonb),
                       'round', n->'round', 'generation', n->'generation',
                       'earlier_rounds', (select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'decision', r.decision,
                                                                                         'reasons', left(r.reasons, 800)) order by r.round), '[]'::jsonb)
                                            from public.ceo_decision_round r where r.item_key = v_key and r.generation = (n->>'generation')::int)),
    jsonb_build_object('month', p_month, 'generation', n->'generation', 'round', n->'round'),
    v_key || ':g' || (n->>'generation') || ':r' || (n->>'round'));
  update public.marketing_month_plan set ceo_held_id = v_held, updated_at = now() where month = p_month;
  return jsonb_build_object('filed', true, 'held_id', v_held, 'generation', n->'generation', 'round', n->'round');
end $fn$;
revoke execute on function public.fn_marketing_month_plan_to_ceo(date, boolean) from public, anon, authenticated;

-- ── 4. THE CEO DECIDES, WITH REASONS ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_reason_apply_ceo__marketing_month_plan(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; p public.marketing_month_plan; v_choice text; v_month date; v_cyc jsonb; v_reasons text;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_month := (r.subject->>'month')::date;
  select * into p from public.marketing_month_plan where month = v_month for update;
  if p.month is null or p.status <> 'ceo_reviewing' or p.ceo_held_id is distinct from p_id then
    return jsonb_build_object('applied', true, 'already', 'the plan moved on (' || coalesce(p.status, 'gone') || ')');
  end if;
  v_reasons := btrim(coalesce(p_result->>'answer', ''));
  -- fn_ceo_decide refuses a decision without reasons (REASONLESS_DECISION): the row stays held and is reasoned again.
  v_cyc := public.fn_ceo_decide('marketing_month_plan', 'marketing_month_plan:' || v_month, 'marketing',
             case when v_choice = 'approve' then 'approved' else 'rejected' end, v_reasons,
             jsonb_build_object('month', v_month, 'ideas', p.plan->'ideas', 'revisions', coalesce(p.plan->'revisions', '[]'::jsonb)),
             'reasoning_held_question', p_id::text);
  -- 'approved' whether recorded now or already on the ledger (a replayed answer); a closed item keeps its own state
  if v_choice = 'approve' and coalesce(v_cyc->>'decision', '') = 'approved' then
    update public.marketing_month_plan
       set status = 'ceo_approved', updated_at = now(),
           verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('ceo', jsonb_build_object('decision', 'approved',
             'reasons', left(v_reasons, 4000), 'round', v_cyc->'round', 'generation', v_cyc->'generation', 'model', p_result->>'model'))
     where month = v_month;
  end if;
  return jsonb_build_object('applied', true, 'month', v_month, 'choice', v_choice, 'cycle', v_cyc);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__marketing_month_plan(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__marketing_month_plan(bigint, jsonb) to service_role;

-- ── 5. MARKETING'S REVISION IS RESUBMITTED (a route added to #1128's fn_ceo_revision_applies) ──────────────────
create or replace function public.fn_ceo_revision_applies(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; a public.agent_actions; v_choice text; v_f jsonb; v_problem text; v jsonb;
  d public.seat_deliberation; e public.ceo_experiment; v_model text; v_target numeric; v_days int; v_revised jsonb;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_f := public.fn_ambition_fields(p_result);
  -- a round the CEO has already left takes no revision (checked first, so a stale answer is never re-reasoned)
  select * into a from public.agent_actions where id = (r.subject->>'handoff_id')::bigint and kind = 'handoff';
  if a.id is null or a.status <> 'pending' then
    return jsonb_build_object('applied', true, 'already', 'the CEO has moved on from this round');
  end if;
  -- A revision answers the CEO's reasons; an empty one is not a resubmission and is reasoned again.
  v_problem := public.fn_ceo_reasons_problem(coalesce(v_f->>'answers', '') || ' ' || coalesce(p_result->>'answer', ''));
  if v_problem is not null then
    raise exception using errcode = 'check_violation', message = 'UNANSWERED_REVISION: a revision answers the CEO''s reasons: ' || v_problem;
  end if;
  v_model := coalesce((select m.model_id from public.model_registry m where m.model_id = p_result->>'model'), 'deterministic');

  if a.detail->>'path' = 'seat_deliberation' then
    select * into d from public.seat_deliberation where id = (a.detail->'version'->>'deliberation_id')::bigint;
    -- a deliberation that has no round left (opened before the five-round rule, or at its cap) cannot take the
    -- revision: the CEO is owed the choice instead of the seat's answer failing on every retry
    if d.round >= d.max_rounds then
      v := jsonb_build_object('decision_owed', public.fn_ceo_decision_owe('seat_deliberation', a.detail->>'item_key', a.agent,
             coalesce((a.detail->>'generation')::int, 1), 'revised with no round left in its deliberation (' || d.round || ' of ' || d.max_rounds || ')',
             a.detail->>'reasons', a.detail->'version'));
      update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id,
               'answers', left(coalesce(v_f->>'answers', ''), 3000), 'no_round_left', v) where id = a.id;
      return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'resubmission', v);
    end if;
    v_revised := d.proposal || jsonb_build_object('revision', coalesce(v_f->>'revision', p_result->>'answer'), 'answers_to_the_ceo', v_f->>'answers',
                                                  'revision_choice', v_choice, 'revises_round', a.detail->'round');
    if length(v_revised::text) > 28000 then   -- seat_deliberation.proposal holds 30,000 characters
      v_revised := jsonb_build_object('previous_proposal_cut', left(d.proposal::text, 6000),
        'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 12000), 'answers_to_the_ceo', left(v_f->>'answers', 4000),
        'revision_choice', v_choice, 'revises_round', a.detail->'round');
    end if;
    v := public.fn_seat_deliberation_revise(d.id, v_revised, v_model);
  elsif a.detail->>'path' = 'ceo_experiment' then
    select * into e from public.ceo_experiment where id = (a.detail->'version'->>'experiment_id')::bigint;
    v_target := case when coalesce(v_f->>'target', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_f->>'target')::numeric else e.target end;
    v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;
    v := jsonb_build_object('experiment_id', public.fn_ceo_experiment_propose(e.proposed_by, e.key,
           coalesce(nullif(btrim(v_f->>'hypothesis'), ''), e.hypothesis), e.metric_key, e.metric_definition, e.baseline, e.baseline_note,
           v_target, e.direction, coalesce(nullif(btrim(v_f->>'approach'), ''), e.approach), e.starts_on, v_days));
  elsif a.detail->>'path' = 'marketing_month_plan' then
    -- the revision rides on the plan (the founder sees it with the ideas) and goes to the CEO as the next round
    update public.marketing_month_plan
       set plan = jsonb_set(plan, '{revisions}', coalesce(plan->'revisions', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                    'round', a.detail->'round', 'ceo_reasons', left(a.detail->>'reasons', 3000),
                    'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 6000), 'answers', left(v_f->>'answers', 3000),
                    'choice', v_choice, 'model', v_model))),
           updated_at = now()
     where month = (a.detail->'version'->>'month')::date and status = 'ceo_reviewing';
    if not found then   -- the plan left the CEO (withdrawn, replaced by a new draft, sent): nothing to resubmit
      return jsonb_build_object('applied', true, 'already', 'the plan is no longer with the CEO');
    end if;
    v := public.fn_marketing_month_plan_to_ceo((a.detail->'version'->>'month')::date, true);
  else
    raise exception 'no revision route for a % item (%)', coalesce(a.detail->>'path', '?'), a.detail->>'item_key';
  end if;
  update public.agent_actions
     set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id, 'choice', v_choice,
                      'answers', left(coalesce(v_f->>'answers', ''), 3000), 'model', v_model, 'resubmission', v),
         detail = detail || jsonb_build_object('awaiting', 'the CEO decides the resubmitted round')
   where id = a.id;
  return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'choice', v_choice, 'resubmission', v);
end $fn$;

-- ── 6. THE TICK: CEO FIRST, THE FOUNDER ONCE ────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_month_plan_tick(p_today date DEFAULT NULL::date, p_include_demo boolean DEFAULT false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_key text; p public.marketing_month_plan; n jsonb; v_built jsonb; v_ideas jsonb; v_token text; v_body text; v_nid bigint; v_mname text;
begin
  if v_month < date '2026-11-01' then return jsonb_build_object('sent', false, 'reason', 'the monthly loop starts with November 2026'); end if;
  v_key := 'marketing_month_plan:' || v_month;
  select * into p from public.marketing_month_plan where month = v_month;
  -- the argued plan owns a month once marketing has put it to the CEO; a sent or decided month is done
  if p.plan_sent_at is not null or p.status in ('with_ceo', 'agreed', 'brief_requested', 'sent_to_founder', 'accepted', 'rejected') then
    return jsonb_build_object('sent', false, 'reason', 'already planned', 'month', v_month, 'status', p.status);
  end if;
  v_mname := to_char(v_month, 'FMMonth YYYY');
  n := public.fn_ceo_decision_next(v_key);

  if p.status = 'ceo_reviewing' then
    if n->>'last_decision' = 'withdrawn' then
      update public.marketing_month_plan set status = 'rejected', updated_at = now(),
             verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('ceo', jsonb_build_object('decision', 'withdrawn'))
       where month = v_month;
      return jsonb_build_object('sent', false, 'month', v_month, 'reason', 'the CEO withdrew the plan after four rejections');
    end if;
    if n->>'last_decision' = 'replaced' and (n->>'round')::int = 1 and p.ceo_held_id is not null
       and exists (select 1 from public.reasoning_held_question h where h.id = p.ceo_held_id
                    and (h.subject->>'generation')::int < (n->>'generation')::int) then
      -- replaced: a fresh draft, a fresh count
      v_built := public.fn_marketing_month_plan_ideas(v_today, v_month, p_include_demo);
      update public.marketing_month_plan set plan = v_built, content_brief = jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_built->'ideas')), 'ideas', v_built->'ideas'),
             updated_at = now() where month = v_month;
      update public.marketing_video_idea set last_planned_month = v_month
       where idea_key in (select e->>'idea_key' from jsonb_array_elements(v_built->'ideas') e);
    end if;
    return jsonb_build_object('sent', false, 'month', v_month, 'with_ceo', true, 'filed', public.fn_marketing_month_plan_to_ceo(v_month));
  end if;

  if p.status is distinct from 'ceo_approved' then
    -- first draft (no row, or the argued path's evaluation draft with no plan put to the CEO yet): to the CEO, not the founder
    v_built := public.fn_marketing_month_plan_ideas(v_today, v_month, p_include_demo);
    insert into public.marketing_month_plan as t (month, status, verdict, plan, content_brief)
    values (v_month, 'ceo_reviewing',
            jsonb_build_object('by', 'code', 'rule', 'founder 24 Sep 2026: the monthly idea plan is routine work, coded; 28 Sep (1009): it leans on what brought registrations; 29 Sep: the CEO reviews it first (1059)'),
            v_built, jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_built->'ideas')), 'ideas', v_built->'ideas'))
    on conflict (month) do update set status = excluded.status, verdict = coalesce(t.verdict, excluded.verdict), plan = excluded.plan,
           content_brief = excluded.content_brief, updated_at = now();
    update public.marketing_video_idea set last_planned_month = v_month
     where idea_key in (select e->>'idea_key' from jsonb_array_elements(v_built->'ideas') e);
    return jsonb_build_object('sent', false, 'month', v_month, 'with_ceo', true, 'ideas', jsonb_array_length(v_built->'ideas'),
                              'filed', public.fn_marketing_month_plan_to_ceo(v_month));
  end if;

  -- ceo_approved: the founder gets the plan the CEO approved, once
  v_ideas := p.plan->'ideas';
  v_token := encode(extensions.gen_random_bytes(16), 'hex');
  v_body := 'Here is the video plan for ' || v_mname || ': ' || jsonb_array_length(v_ideas)
         || ' short videos on UAE working days (Monday, Wednesday, Thursday first; no weekends or public holidays).' || E'\n\n'
         || 'The CEO reviewed it and approved it' || coalesce(' in round ' || (p.verdict->'ceo'->>'round'), '') || ': '
         || coalesce(p.verdict->'ceo'->>'reasons', '') || E'\n\n'
         || coalesce((select string_agg(format('Round %s, the CEO asked: %s' || E'\n' || 'Marketing changed: %s', x->>'round', x->>'ceo_reasons', coalesce(x->>'revision', x->>'answers')), E'\n\n')
                        from jsonb_array_elements(coalesce(p.plan->'revisions', '[]'::jsonb)) x) || E'\n\n', '')
         || public.fn_marketing_learning_text(p.plan->'learned', coalesce(p.plan->'shifted_to', '[]'::jsonb)) || E'\n\n'
         || (select string_agg(format(E'%s. %s — %s%s\n   Hook: %s\n   Film: %s\n   Call to action: %s',
                                      e->>'n', to_char((e->>'date')::date, 'Dy DD Mon'), e->>'title',
                                      case when e->>'why' = 'brought registrations' then ' (brought registrations)' else '' end,
                                      e->>'hook', e->>'film_plan', e->>'cta'),
                               E'\n\n' order by (e->>'n')::int)
               from jsonb_array_elements(v_ideas) e)
         || E'\n\nWhen the videos are ready, reply to this email with them (attachments or links). Change any idea by saying so in the same reply. '
         || 'The marketing seat then builds the calendar (dates, times per platform, captions, hashtags, links) and sends it to you; '
         || 'replying "approve" to that calendar schedules and publishes it.';
  v_nid := public.fn_marketing_mail_founder('marketing_month_plan', 'Video plan for ' || v_mname || ' [plan ' || v_token || ']',
                                            v_body, null, 'plan+' || v_token || '@mail.quotesdone.com');
  update public.marketing_month_plan set status = 'sent_to_founder', plan_token = v_token, plan_notification_id = v_nid,
         plan_sent_at = now(), updated_at = now()
   where month = v_month;
  return jsonb_build_object('sent', true, 'month', v_month, 'ideas', jsonb_array_length(v_ideas), 'notification_id', v_nid,
                            'ceo_round', p.verdict->'ceo'->'round', 'has_data', p.plan->'learned'->'has_data', 'shifted_to', p.plan->'shifted_to');
end $fn$;

-- ── 7. THE STALL WATCH FIRES ON BOTH PATHS ──────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_marketing_plan_watch(p_at timestamp with time zone DEFAULT now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare cal jsonb := public.fn_marketing_plan_calendar(p_at); v_month date; v_deadline date; v_today date;
  p public.marketing_month_plan; v_late boolean; v_stalled boolean := false; v_id bigint; r record; n_closed int := 0;
  v_covered boolean; v_reached timestamptz; v_hold boolean; v_gate jsonb;
begin
  v_month := (cal->>'plan_month')::date; v_deadline := (cal->>'deadline')::date; v_today := (cal->>'today')::date;
  select * into p from public.marketing_month_plan where month = v_month;
  v_covered := public.fn_marketing_month_covered_by_approved_calendar(v_month);
  v_late := v_today > v_deadline and (p.month is null or p.status = 'draft') and not v_covered;

  if v_late then
    v_id := public.fn_ceo_improvement_open('marketing_plan_late', v_month::text, 'marketing',
      format('The marketing plan for %s was due to the CEO by %s (a week before month end, instruction 866) and has not arrived (%s). '
             || 'Send it today with its evidence; the CEO reviews it on the review machine and the month does not start unplanned.',
             to_char(v_month, 'FMMonth YYYY'), to_char(v_deadline, 'DD Mon'), coalesce('status ' || p.status, 'no plan row')),
      jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', p.status, 'due_on', v_today + 1));
  end if;

  -- closed the day the plan reaches the CEO, or when an approved calendar already covers the month
  for r in select i.id, (i.evidence->>'plan_month')::date as m from public.ceo_improvement i
            where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    if exists (select 1 from public.marketing_month_plan mp where mp.month = r.m and mp.status <> 'draft') then
      perform public.fn_ceo_improvement_close(r.id, format('The %s plan reached the CEO (%s).', to_char(r.m, 'FMMonth YYYY'),
        (select status from public.marketing_month_plan where month = r.m)));
      n_closed := n_closed + 1;
    elsif public.fn_marketing_month_covered_by_approved_calendar(r.m) then
      perform public.fn_ceo_improvement_close(r.id, format('%s is already planned: the founder approved campaign %s, which schedules posts in that month; no second plan is drafted.',
        to_char(r.m, 'FMMonth YYYY'),
        (select string_agg(distinct c.campaign_key, ', ') from public.marketing_campaign c join public.marketing_post mp2 on mp2.campaign_id = c.id
          where not c.is_demo and c.approved_hash is not null and mp2.status <> 'cancelled'
            and date_trunc('month', mp2.scheduled_at at time zone 'Asia/Dubai')::date = date_trunc('month', r.m)::date)));
      n_closed := n_closed + 1;
    end if;
  end loop;

  -- THE CEO'S OWN SIDE: a plan waiting on the CEO for more than 2 days with no CEO answer since it reached the CEO.
  -- WHEN it reached the CEO is read per path (plan_sent_at is set only when the founder is mailed, so it is never the
  -- time a plan reached the CEO - the old comparison was NULL on the argued path and this never fired):
  --   argued path 'with_ceo'       marketing's latest turn; answered by a CEO turn after it
  --   coded path 'ceo_reviewing'   the CEO's current held question; answered when it leaves 'held'
  if p.status = 'with_ceo' then
    v_reached := (select max(t.created_at) from public.marketing_plan_review_turn t where t.month = p.month and t.seat = 'marketing');
    v_stalled := v_reached < p_at - interval '2 days'
      and not exists (select 1 from public.marketing_plan_review_turn t where t.month = p.month and t.seat = 'ceo' and t.created_at >= v_reached);
  elsif p.status = 'ceo_reviewing' then
    select h.created_at into v_reached from public.reasoning_held_question h where h.id = p.ceo_held_id and h.status = 'held';
    v_stalled := v_reached < p_at - interval '2 days';
  end if;
  v_stalled := coalesce(v_stalled, false);
  if v_stalled then
    v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
    v_hold := coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state');
    perform public.fn_it_engineer_finding_upsert('ceo:marketing_plan_review_stalled:' || v_month,
      'The CEO has not reviewed the marketing plan for ' || to_char(v_month, 'FMMonth YYYY') || ' sent ' || to_char(v_reached at time zone 'Asia/Dubai', 'DD Mon')
        || case when v_hold then ' (the model hold is on: the review is reasoned when it lifts)' else '' end,
      'public.marketing_month_plan (' || p.status || ') / ' || case when p.status = 'with_ceo' then 'seat_deliberation ' || coalesce(p.deliberation_id::text, 'none')
                                                                 else 'reasoning_held_question ' || coalesce(p.ceo_held_id::text, 'none') end,
      'agent_facing', 1,
      jsonb_build_object('month', v_month, 'status', p.status, 'reached_ceo_at', v_reached, 'deliberation_id', p.deliberation_id,
                         'held_id', p.ceo_held_id, 'model_hold', v_hold, 'owner_seat', 'ceo'),
      '{}'::text[], array[case when v_hold then 'nothing: the wait is the founder''s model hold' else 'where the review machine stopped advancing the CEO''s turn' end], 'ceo');
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO''s turn on the marketing plan is recorded, or the plan left the CEO'
   where issue_key like 'ceo:marketing\_plan\_review\_stalled:%' and closed_at is null
     and not (v_stalled and issue_key = 'ceo:marketing_plan_review_stalled:' || v_month);

  return jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', coalesce(p.status, 'none'),
    'late', v_late, 'covered_by_approved_calendar', v_covered, 'improvement', v_id, 'review_stalled', v_stalled,
    'reached_ceo_at', v_reached, 'model_hold', v_hold, 'closed', n_closed);
end $fn$;

-- VERDICT (read by apply_sql.mjs)
select case
  when not exists (select 1 from pg_constraint where conname = 'ceo_decision_round_path_check'
                    and pg_get_constraintdef(oid) like '%marketing_month_plan%') then 'PROBE FAILED: the ledger does not take the path'
  when position('fn_marketing_mail_founder' in pg_get_functiondef('public.fn_marketing_month_plan_tick(date,boolean)'::regprocedure))
       < position('ceo_approved: the founder' in pg_get_functiondef('public.fn_marketing_month_plan_tick(date,boolean)'::regprocedure))
    then 'PROBE FAILED: the tick mails the founder before the CEO approval branch'
  when to_regprocedure('public.fn_reason_apply_ceo__marketing_month_plan(bigint,jsonb)') is null then 'PROBE FAILED: no apply for the CEO''s answer'
  else 'PROBE OK' end as verdict;
