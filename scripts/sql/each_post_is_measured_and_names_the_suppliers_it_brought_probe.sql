-- PROBE (pure: no DDL, always raises, so nothing survives). Read it with node scripts/qsql.mjs AFTER
-- each_post_is_measured_and_names_the_suppliers_it_brought.sql is applied; it must say PROBE OK.
-- marketing (scorecard) + sales_engineer (the registration side), 23 Sep 2026, instruction 865.
--
-- Fixtures: ZZ DEMO posts (is_demo) in month 2031-01, which no real post can reach; a ZZ DEMO registration
-- with NO email and NO phone, so nothing in it can reach a person; a 2031-01 goal. All rolled back by the raise.
-- Proves: (1) a registration arriving through a UTM link records its source and names the post, first touch
-- wins, junk is refused; (2) the scorecard over a month of ZZ DEMO metrics ranks, compares to target and to
-- the account's median, and says so in words; (3) the scorecard is stored once per period.
do $probe$
declare
  p1 bigint; p2 bigint; p3 bigint; v_lead bigint; r jsonb; v_fail text := '';
  v_top bigint; v_verdict text; v_er numeric; v_med numeric; v_rows int; v_real_before int; v_real_after int;
begin
  select count(*) into v_real_before from public.marketing_first_touch;
  insert into public.marketing_post (ingest_key, ingested_by, text_en, text_ar, channels, scheduled_at, status, attempts, is_demo, published_at, media_paths)
  values ('zz-demo-probe-865-a', 'claude', 'ZZ DEMO probe a', 'تجربة', array['instagram','facebook'], '2031-01-05T08:00:00Z', 'scheduled', 1, true, '2031-01-05T08:00:00Z', array['posts/zz/a.png'])
  returning id into p1;
  insert into public.marketing_post (ingest_key, ingested_by, text_en, text_ar, channels, scheduled_at, status, attempts, is_demo, published_at, media_paths)
  values ('zz-demo-probe-865-b', 'claude', 'ZZ DEMO probe b', 'تجربة', array['instagram'], '2031-01-12T08:00:00Z', 'scheduled', 1, true, '2031-01-12T08:00:00Z', array['posts/zz/b.png'])
  returning id into p2;
  insert into public.marketing_post (ingest_key, ingested_by, text_en, text_ar, channels, scheduled_at, status, attempts, is_demo, published_at, media_paths)
  values ('zz-demo-probe-865-c', 'claude', 'ZZ DEMO probe c', 'تجربة', array['instagram'], '2031-01-19T08:00:00Z', 'scheduled', 1, true, '2031-01-19T08:00:00Z', array['posts/zz/c.png'])
  returning id into p3;
  -- #874's publish guard refuses a ZZ DEMO post going INTO flight. These three are seeded the way a reconcile
  -- records a post Postiz already has (attempts > 0, then status published), which the guard does not re-gate.
  update public.marketing_post set status = 'published' where id in (p1, p2, p3);
  insert into public.marketing_post_platform (post_id, platform, postiz_post_id, platform_post_id) values
    (p1, 'instagram', 'zz-pz-a', 'zz-ig-a'), (p1, 'facebook', 'zz-pz-a2', 'zz-fb-a'), (p2, 'instagram', 'zz-pz-b', 'zz-ig-b'), (p3, 'instagram', 'zz-pz-c', 'zz-ig-c');
  insert into public.marketing_post_metric (post_id, platform, checkpoint, metric, value, unavailable_reason, captured_at) values
    (p1, 'instagram', '1d', 'total_interactions', 20, null, '2031-01-06T09:00:00Z'),
    (p1, 'instagram', '7d', 'total_interactions', 50, null, '2031-01-12T09:00:00Z'),
    (p1, 'instagram', '7d', 'reach', 900, null, '2031-01-12T09:00:00Z'),
    (p1, 'instagram', '7d', 'completion_rate', null, 'Instagram has no completion metric', '2031-01-12T09:00:00Z'),
    (p2, 'instagram', '7d', 'total_interactions', 10, null, '2031-01-19T09:00:00Z'),
    (p2, 'instagram', '7d', 'reach', 1500, null, '2031-01-19T09:00:00Z'),
    (p3, 'instagram', '7d', 'total_interactions', 30, null, '2031-01-26T09:00:00Z'),
    (p3, 'instagram', '7d', 'reach', 400, null, '2031-01-26T09:00:00Z'),
    (p1, 'facebook', '7d', 'fb_reels_total_plays', 700, null, '2031-01-12T09:00:00Z');
  insert into public.marketing_insight_day (platform, object_type, object_id, metric, day, value)
  values ('instagram', 'account', 'zz-demo-ig', 'followers', '2031-01-01', 1000);
  insert into public.marketing_goal (month, platform, metric, target, benchmark_source)
  values ('2031-01', 'instagram', 'engagement_rate_by_followers', 0.02, 'ZZ DEMO probe target, not a benchmark: rolled back');

  -- (1) the registration side: a supplier arriving through post a's Instagram link
  insert into public.leads (company_name, business_role, claimed, source)
  values ('ZZ DEMO probe 865 supplier', 'supplier', false, 'self_registered') returning id into v_lead;
  if not (select is_demo from public.leads where id = v_lead) then raise exception 'CHK<<PROBE FAILED: the fixture lead is not marked demo>>'; end if;
  r := public.fn_marketing_first_touch_record(v_lead, jsonb_build_object('utm_source', 'Instagram', 'utm_medium', 'social',
         'utm_campaign', '2031-01', 'utm_content', 'zz-demo-probe-865-a', 'landing_path', '/supplier', 'first_seen_at', now()));
  if not (r->>'recorded')::boolean or (r->>'post_id')::bigint <> p1 then v_fail := v_fail || ' first touch not recorded against post a: ' || r::text; end if;
  r := public.fn_marketing_first_touch_record(v_lead, '{"utm_source":"x","utm_medium":"social","utm_content":"zz-demo-probe-865-b"}');
  if (r->>'recorded')::boolean then v_fail := v_fail || ' a second touch overwrote the first'; end if;
  if (select utm_source from public.marketing_first_touch where lead_id = v_lead) <> 'instagram' then v_fail := v_fail || ' utm_source not normalised'; end if;
  r := public.fn_marketing_first_touch_record(v_lead, '{"utm_source":"<script>"}');
  if (r->>'reason') <> 'no valid utm_source' then v_fail := v_fail || ' junk touch accepted: ' || r::text; end if;

  -- (2) the scorecard over the ZZ DEMO month
  select post_id into v_top from public.fn_marketing_scorecard('2031-01', true) where platform = 'instagram' and rank = 1 limit 1;
  if v_top <> p1 then v_fail := v_fail || ' rank 1 on instagram is not post a (it brought the registration)'; end if;
  select value, verdict into v_er, v_verdict from public.fn_marketing_scorecard('2031-01', true)
   where post_id = p2 and platform = 'instagram' and metric = 'engagement_rate_by_followers';
  if v_er <> 0.01 or v_verdict <> 'below target' then v_fail := v_fail || ' post b ER ' || coalesce(v_er::text, 'null') || ' / ' || coalesce(v_verdict, 'null'); end if;
  select value, verdict into v_er, v_verdict from public.fn_marketing_scorecard('2031-01', true)
   where post_id = p1 and platform = 'instagram' and metric = 'engagement_rate_by_followers';
  if v_er <> 0.05 or v_verdict <> 'met target' then v_fail := v_fail || ' post a ER ' || coalesce(v_er::text, 'null') || ' / ' || coalesce(v_verdict, 'null'); end if;
  select account_median, verdict into v_med, v_verdict from public.fn_marketing_scorecard('2031-01', true)
   where post_id = p3 and platform = 'instagram' and metric = 'reach';
  if v_med <> 900 or v_verdict <> 'below own median (no sourced target)' then v_fail := v_fail || ' post c reach vs median ' || coalesce(v_med::text, 'null') || ' / ' || coalesce(v_verdict, 'null'); end if;
  if exists (select 1 from public.fn_marketing_scorecard('2031-01', true) where post_id = p1 and metric = 'total_interactions' and checkpoint <> '7d') then
    v_fail := v_fail || ' the latest checkpoint was not preferred'; end if;
  if exists (select 1 from public.fn_marketing_scorecard('2031-01', false)) then v_fail := v_fail || ' demo posts leaked into the real scorecard'; end if;
  if exists (select 1 from public.fn_marketing_scorecard('2031-01', true) where metric = 'completion_rate') then v_fail := v_fail || ' an unavailable metric was scored'; end if;

  -- (3) stored once per period (real scorecard of the demo month is empty, and that is stored too)
  r := public.fn_marketing_scorecard_publish('month_end', '2031-01-end', '2031-01');
  if not (r->>'stored')::boolean then v_fail := v_fail || ' scorecard not stored'; end if;
  r := public.fn_marketing_scorecard_publish('month_end', '2031-01-end', '2031-01');
  if (r->>'stored')::boolean then v_fail := v_fail || ' scorecard stored twice'; end if;
  perform * from public.fn_marketing_post_checkpoints_due(5);

  select count(*) into v_real_after from public.marketing_first_touch where lead_id <> v_lead;
  if v_real_after <> v_real_before then v_fail := v_fail || ' real first-touch rows changed'; end if;
  select count(*) into v_rows from public.fn_marketing_scorecard('2031-01', true);
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: ' || v_rows || ' scorecard rows over 3 ZZ DEMO posts' else 'PROBE FAILED:' || v_fail end;
end
$probe$;
