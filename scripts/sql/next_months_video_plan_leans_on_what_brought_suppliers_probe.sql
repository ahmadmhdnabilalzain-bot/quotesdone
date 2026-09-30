-- PROBE (aborted transaction, commits nothing, emails nobody): next_months_video_plan_leans_on_what_brought_suppliers.sql
-- Seeds a ZZ DEMO video idea, a ZZ DEMO published post and a first touch for an existing ZZ DEMO supplier
-- (@example.invalid), in June 2030 so no real row can fall in the window; the final raise rolls every row back,
-- including the plan mails in notifications (send_outbox never sees a rolled-back row). Real rows it must not
-- disturb: marketing_month_plan and marketing_first_touch, counted before and after.
--
--   node scripts/apply_sql.mjs scripts/sql/next_months_video_plan_leans_on_what_brought_suppliers_probe.sql --apply
do $probe$
declare
  v_bad text := ''; v_lead bigint; v_post bigint; v_l jsonb; v_t jsonb; v_body text; v_plan jsonb; v_n int;
  v_before text; v_after text;
begin
  select count(*) || '/' || coalesce(max(month)::text, '-') into v_before from public.marketing_month_plan where month < '2030-01-01';
  select min(id) into v_lead from public.leads where is_demo and email like '%@example.invalid';
  if v_lead is null then raise exception 'CHK<<PROBE FAILED: no ZZ DEMO supplier to attribute>>'; end if;

  -- 1. no data: the mix is kept and the email says so
  -- since 29 Sep 2026 the plan goes to the CEO first (the_ceo_reviews_the_months_video_plan_before_the_founder_sees_it.sql):
  -- the first tick files it, the CEO approves with reasons, the next tick mails the founder
  perform public.fn_marketing_month_plan_tick('2030-04-10', true);
  perform public.fn_reason_apply_ceo__marketing_month_plan((select ceo_held_id from public.marketing_month_plan where month = '2030-05-01'),
    jsonb_build_object('decision', jsonb_build_object('choice', 'approve'), 'answer', 'Approved: the ideas follow what brought registrations and the filing load fits the founder''s month, so it goes to him as drafted.'));
  v_t := public.fn_marketing_month_plan_tick('2030-04-10', true);
  select plan, (select body from public.notifications where id = mp.plan_notification_id) into v_plan, v_body
    from public.marketing_month_plan mp where month = '2030-05-01';
  if not coalesce((v_t->>'sent')::boolean, false) then v_bad := v_bad || ' nodata_not_sent:' || v_t; end if;
  if jsonb_array_length(v_plan->'shifted_to') <> 0 then v_bad := v_bad || ' nodata_shifted'; end if;
  if v_body not like '%The mix is kept as it is%' then v_bad := v_bad || ' nodata_not_said'; end if;

  -- 2. seed: one ZZ DEMO idea, one published post carrying its title, one registration it brought
  insert into public.marketing_video_idea (idea_key, title, hook, film_plan, cta, audience, last_planned_month)
  values ('zz-demo-probe-idea', 'ZZ DEMO probe idea', 'probe', 'probe', 'probe', 'supplier', '2030-01-01');
  insert into public.marketing_post (ingest_key, ingested_by, title, text_en, channels, status, is_demo, scheduled_at, published_at, video_path)
  values ('zz-demo-probe-learning', 'marketing', 'ZZ DEMO probe idea', 'ZZ DEMO probe post', array['linkedin'], 'scheduled', true,
          '2030-06-12 11:30+04', null, 'probe.mp4') returning id into v_post;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, utm_content, post_id, recorded_at)
  values (v_lead, 'linkedin', 'social', 'zz_demo', 'zz-demo-probe-learning', v_post, '2030-06-14 10:00+04');

  -- 3. the learning names topic, channel, format and time, split by category; demo is excluded by default
  v_l := public.fn_marketing_learning('2030-06-01', true);
  if (v_l->>'registrations')::int <> 1 or (v_l->>'traced_to_a_post')::int <> 1 then v_bad := v_bad || ' regs:' || v_l; end if;
  if (v_l->'dimensions'->'topic'->0->>'value') <> 'zz-demo-probe-idea' then v_bad := v_bad || ' topic'; end if;
  if (v_l->'dimensions'->'channel'->0->>'value') <> 'linkedin' then v_bad := v_bad || ' channel'; end if;
  if (v_l->'dimensions'->'format'->0->>'value') <> 'video' then v_bad := v_bad || ' format'; end if;
  if (v_l->'dimensions'->'time'->0->>'value') <> 'Wed midday' then v_bad := v_bad || ' time:' || (v_l->'dimensions'->'time'->0->>'value'); end if;
  if (v_l->'dimensions'->'topic'->0->'by_category') = '{}'::jsonb then v_bad := v_bad || ' no_category'; end if;
  if not (v_l->>'organic_only')::boolean then v_bad := v_bad || ' organic_rule_off'; end if;
  if (public.fn_marketing_learning('2030-06-01')->>'has_data')::boolean then v_bad := v_bad || ' demo_counted_as_real'; end if;

  -- 4. the plan shifts to it: first idea, marked, and the email shows the evidence; dates stay working days
  perform public.fn_marketing_month_plan_tick('2030-06-20', true);
  perform public.fn_reason_apply_ceo__marketing_month_plan((select ceo_held_id from public.marketing_month_plan where month = '2030-07-01'),
    jsonb_build_object('decision', jsonb_build_object('choice', 'approve'), 'answer', 'Approved: the ideas follow what brought registrations and the filing load fits the founder''s month, so it goes to him as drafted.'));
  v_t := public.fn_marketing_month_plan_tick('2030-06-20', true);
  select plan, (select body from public.notifications where id = mp.plan_notification_id) into v_plan, v_body
    from public.marketing_month_plan mp where month = '2030-07-01';
  if v_plan->'shifted_to' <> '["zz-demo-probe-idea"]'::jsonb then v_bad := v_bad || ' shift:' || coalesce(v_plan->>'shifted_to', 'null'); end if;
  if v_plan->'ideas'->0->>'idea_key' <> 'zz-demo-probe-idea' then v_bad := v_bad || ' not_first'; end if;
  if v_body not like '%zz-demo-probe-idea 1 reg / 1 post(s)%' or v_body not like '%The shift:%' or v_body not like '%Organic only:%' then
    v_bad := v_bad || ' evidence_missing'; end if;
  select count(*) into v_n from jsonb_array_elements(v_plan->'ideas') e where not public.fn_is_working_day((e->>'date')::date);
  if v_n > 0 then v_bad := v_bad || ' weekend_or_holiday:' || v_n; end if;
  if (v_plan->'learned'->>'has_data')::boolean is not true then v_bad := v_bad || ' learned_not_stored'; end if;

  select count(*) || '/' || coalesce(max(month)::text, '-') into v_after from public.marketing_month_plan where month < '2030-01-01';
  if v_after is distinct from v_before then v_bad := v_bad || ' real_plans_disturbed'; end if;

  raise exception 'CHK<<%>>', case when v_bad = '' then 'PROBE OK: no data keeps the mix and says so; a ZZ DEMO registration is learned by topic, channel, format, time and category; the next plan leads with it and shows the evidence on working days'
                                   else 'PROBE FAILED:' || v_bad end;
end
$probe$;
