-- A MONTH-PLAN REVISION CARRIES ITS IDEAS, AND A FAILED ONE IS ASKED AGAIN (it_engineer, 27 Oct 2026).
--
-- Measured 26 Oct 2026 21:00Z: seat duty marketing.month_plan had failed 7 days running (last ok 19 Oct), raising
-- "the plan for 2026-11 is not with the founder on 2026-10-27" with the tick saying "marketing owes the CEO a revision".
-- The November plan has sat at ceo_reviewing since 12 Oct 23:31Z. Two causes, both in the revise cycle:
--
--   1. THE REVISION NEVER REACHED THE PLAN. The CEO rejected round 1 with five concrete changes. fn_ceo_revision_applies
--      (marketing_month_plan branch) appended the seat's revision as PROSE to plan.revisions and resubmitted the same
--      plan.ideas. The CEO rejected round 2 because "the 12 ideas submitted are word for word the round-1 plan". The
--      revise question never asked for the idea list, so no answer could change it.
--   2. A FAILED REVISION QUESTION ENDED THE CYCLE. The round-2 revision (held question 21509) failed three model
--      attempts on 13 Oct (synthesise: client_error) and closed as failed. Its ceo.revise handoff (163352) stays pending,
--      and fn_marketing_month_plan_to_ceo refuses to file while a revision is owed, so nothing could move: the
--      handler is called once, and fn_reason_hold keeps a failed row closed under the same dedupe key.
--
-- The fix:
--   * fn_seat_revises_for_the_ceo asks a marketing_month_plan revision for its complete idea list (one per line,
--     pipe-separated), and when the question under its key failed or expired it files a fresh one under
--     '<key>:retry<n>'. The founder's 3-try limit still holds: fn_reason_hold returns the failed row for 7 days.
--   * fn_ceo_revision_applies replaces plan.ideas with the parsed list on a 'revised' choice; a 'revised' answer that
--     carries no usable idea line is refused (UNANSWERED_REVISION) and reasoned again, like an empty revision.
--   * fn_marketing_month_plan_tick re-asks the owed revision when its question is no longer live, on its daily run.
--
-- Prevented by: scripts/checks/the_latency_and_month_plan_duties_survive_their_failing_inputs.test.mjs (rolled back on
-- production: the stuck November state is re-asked, a revised list replaces the ideas, and a prose-only revision is
-- refused).

-- One idea per line: date | audience | title | hook | call to action | how to film it (the last is optional).
-- Lines that do not parse, fall outside the month, or fall on a Saturday or Sunday are dropped.
create or replace function public.fn_marketing_month_plan_parse_ideas(p_text text, p_month date)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with l as (
    select o, regexp_split_to_array(regexp_replace(btrim(line), '^\s*(?:[-*]|\d+[.)])\s*', ''), '\s*\|\s*') p
      from regexp_split_to_table(coalesce(p_text, ''), E'\r?\n') with ordinality t(line, o)),
  ok as (
    select o, case when pg_input_is_valid(btrim(p[1]), 'date') then btrim(p[1])::date end d, lower(btrim(p[2])) aud, btrim(p[3]) title, btrim(p[4]) hook, btrim(p[5]) cta,
           nullif(btrim(coalesce(p[6], '')), '') film
      from l
     where cardinality(p) >= 5 and p[1] ~ '^\s*\d{4}-\d{2}-\d{2}\s*$'
       and lower(btrim(p[2])) in ('supplier', 'customer', 'both')
       and btrim(p[3]) <> '' and btrim(p[4]) <> '' and btrim(p[5]) <> ''),
  dated as (
    select * from ok
     where d is not null and date_trunc('month', d) = date_trunc('month', p_month) and extract(isodow from d) < 6)
  select coalesce(jsonb_agg(jsonb_build_object('n', n, 'date', d, 'audience', aud, 'title', title, 'hook', hook, 'cta', cta,
                                               'film_plan', film, 'why', 'revised for the CEO',
                                               'idea_key', trim(both '-' from regexp_replace(lower(title), '[^a-z0-9]+', '-', 'g')))
                            order by n), '[]'::jsonb)
    from (select *, row_number() over (order by d, o) n from dated) x
$fn$;
revoke execute on function public.fn_marketing_month_plan_parse_ideas(text, date) from public, anon, authenticated;

create or replace function public.fn_seat_revises_for_the_ceo(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_held bigint; v_fields jsonb; v_key text; v_n int; v_last text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_key := 'ceo_revision:' || (a.detail->>'item_key') || ':g' || coalesce(a.detail->>'generation', '1') || ':r' || coalesce(a.detail->>'round', '1');
  -- a question that failed or expired stays closed under its key (fn_reason_hold, R3): a revision still owed is asked
  -- again under a fresh key, so a model failure never ends the cycle (27 Oct 2026, held question 21509)
  select count(*), (array_agg(h.status order by h.id desc))[1] into v_n, v_last
    from public.reasoning_held_question h where h.dedupe_key = v_key or h.dedupe_key like v_key || ':retry%';
  if v_n > 0 and v_last in ('failed', 'expired') then v_key := v_key || ':retry' || v_n; end if;
  v_held := public.fn_seat_duty_reason(a.agent, a.agent || '.ceo_revision',
    'The CEO sent your submission back (round ' || coalesce(a.detail->>'round', '?') || ', ' || coalesce(a.detail->>'rounds_left', '?')
      || ' more before the CEO must replace or withdraw it). Read each of the CEO''s reasons. Produce a revised version that answers '
      || 'every one of them, or where you are right keep it and answer each reason with evidence. The CEO reviews what you resubmit.',
    '[{"id":"revised","meaning":"the submission is revised so that it answers every reason the CEO gave"},{"id":"defended","meaning":"the submission stands, and each reason is answered with evidence"}]'::jsonb,
    jsonb_build_object('path', a.detail->>'path', 'item_key', a.detail->>'item_key', 'round', a.detail->'round',
                       'ceo_reasons', a.detail->>'reasons', 'submission', a.detail->'version'),
    jsonb_build_object('handoff_id', p_id, 'path', a.detail->>'path', 'item_key', a.detail->>'item_key'),
    v_key);
  v_fields := jsonb_build_array(
    jsonb_build_object('key', 'revision', 'question', 'the revised submission, complete, as the CEO should now review it'),
    jsonb_build_object('key', 'answers', 'question', 'for each of the CEO''s reasons: what changed, or the evidence that answers it'));
  if a.detail->>'path' = 'ceo_experiment' then
    v_fields := v_fields || jsonb_build_array(
      jsonb_build_object('key', 'hypothesis', 'question', 'the revised hypothesis (blank keeps it)'),
      jsonb_build_object('key', 'approach', 'question', 'the revised approach (blank keeps it)'),
      jsonb_build_object('key', 'target', 'question', 'the revised target, a number (blank keeps it)'),
      jsonb_build_object('key', 'days', 'question', 'the revised run length in days, 7 to 365 (blank keeps it)'));
  elsif a.detail->>'path' = 'marketing_month_plan' then
    -- the plan the CEO reviews IS the idea list: a revision that does not restate it changes nothing (rounds 1 and 2)
    v_fields := v_fields || jsonb_build_array(jsonb_build_object('key', 'ideas', 'question',
      'the complete revised video list that replaces the submitted one, one video per line, in this exact form: '
      || 'YYYY-MM-DD | supplier or customer or both | title | hook | call to action | how to film it. '
      || 'Dates fall in the plan''s month on UAE working days (Monday to Friday). Blank if you defend the plan as it stands.'));
  end if;
  perform public.fn_ambition_ask_fields(v_held, v_fields);
  return jsonb_build_object('waiting', a.agent || ' revises and resubmits ' || coalesce(a.detail->>'item_key', '?') || ' (held question ' || v_held || ')',
                            'held_id', v_held);
end $fn$;
revoke execute on function public.fn_seat_revises_for_the_ceo(bigint) from public, anon, authenticated;

-- The seat's reasoned revision is resubmitted along its path.
create or replace function public.fn_ceo_revision_applies(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; a public.agent_actions; v_choice text; v_f jsonb; v_problem text; v jsonb;
  d public.seat_deliberation; e public.ceo_experiment; v_model text; v_target numeric; v_days int; v_revised jsonb; v_ideas jsonb;
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
    -- 'revised' replaces the idea list the CEO reviews; prose alone is not a revision of the plan (27 Oct 2026)
    v_ideas := public.fn_marketing_month_plan_parse_ideas(v_f->>'ideas', (a.detail->'version'->>'month')::date);
    if v_choice = 'revised' and jsonb_array_length(v_ideas) = 0 then
      raise exception using errcode = 'check_violation',
        message = 'UNANSWERED_REVISION: a revised month plan restates its idea list, one video per line (date | audience | title | hook | call to action | film)';
    end if;
    -- the revision rides on the plan (the founder sees it with the ideas) and goes to the CEO as the next round
    update public.marketing_month_plan
       set plan = jsonb_set(plan, '{revisions}', coalesce(plan->'revisions', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                    'round', a.detail->'round', 'ceo_reasons', left(a.detail->>'reasons', 3000),
                    'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 6000), 'answers', left(v_f->>'answers', 3000),
                    'choice', v_choice, 'model', v_model, 'ideas_replaced', v_choice = 'revised')))
                  || case when v_choice = 'revised' then jsonb_build_object('ideas', v_ideas) else '{}'::jsonb end,
           content_brief = case when v_choice = 'revised'
                                then jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_ideas)), 'ideas', v_ideas)
                                else content_brief end,
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
revoke execute on function public.fn_ceo_revision_applies(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_marketing_month_plan_tick(p_today date default null::date, p_include_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_key text; p public.marketing_month_plan; n jsonb; v_built jsonb; v_ideas jsonb; v_token text; v_body text; v_nid bigint; v_mname text;
  v_owed public.agent_actions; v_re jsonb;
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
    -- A REVISION STILL OWED WHOSE QUESTION IS NO LONGER LIVE IS ASKED AGAIN (27 Oct 2026): the handler runs once, so a
    -- failed or expired revision question otherwise leaves the plan with the CEO forever.
    select * into v_owed from public.agent_actions a
     where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.revise' and a.detail->>'item_key' = v_key
       and not coalesce(a.evidence, '{}'::jsonb) ? 'resubmitted_at'
     order by a.id desc limit 1;
    -- only once the handler has asked (evidence.held_id): a handoff not yet dispatched is the dispatcher's
    if v_owed.id is not null and v_owed.evidence ? 'held_id' and not exists (select 1 from public.reasoning_held_question q
                                         where q.id = (v_owed.evidence->>'held_id')::bigint and q.status in ('held', 'reasoned', 'applied')) then
      v_re := public.fn_seat_revises_for_the_ceo(v_owed.id);
      update public.agent_actions
         set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('held_id', v_re->'held_id', 'waiting', v_re->'waiting',
                          'asked_again_at', now(), 'asked_again_after', v_owed.evidence->'held_id')
       where id = v_owed.id;
      return jsonb_build_object('sent', false, 'month', v_month, 'with_ceo', true, 'revision_asked_again', v_re);
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
revoke execute on function public.fn_marketing_month_plan_tick(date, boolean) from public, anon, authenticated;
