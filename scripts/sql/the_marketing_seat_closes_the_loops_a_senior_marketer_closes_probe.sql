-- PROBE for the_competitor_watch_reads_real_pages_and_never_briefs_on_nothing.sql and
-- the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql (marketing, ledger 1003 stage 2). Never applied: it
-- always raises CHK<<...>>, so every row it and the duties write is rolled back -- including the pg_net requests, which
-- are queued rows of this transaction and so never leave. Run concatenated after both files in one transaction:
--   node scripts/qsql.mjs <competitor file + duties file + this probe>
-- Its subjects are ZZ DEMO (a ZZ DEMO competitor, watched = false, with synthetic HTML and a synthetic feed); the
-- duties themselves run against production as it stands. It asserts nobody was reached: notifications are counted
-- this transaction wrote, and nothing is posted (no post this transaction wrote changed status).
do $probe$
-- 3 Nov 2026 (independent review of #1551): it counts only what THIS transaction writes. A whole-table count read other
-- sessions' live inserts and status changes as the probe's (the same false failure #1722 measured: two suppressed rows
-- every ~20 s), and this probe also runs after the apply, where a false failure stops every later MANIFEST file.
-- now() is this transaction's start and the column default; xmin catches a writer that sets the column itself.
-- It also proves no approved campaign lost its approval: fn_marketing_social_publish must not edit an approved post.
declare v_xid text := (pg_current_xact_id()::text::bigint % 4294967296)::text;
  p0 jsonb := (select coalesce(jsonb_object_agg(id::text, status), '{}'::jsonb) from public.marketing_post);
  a0 bigint[] := (select coalesce(array_agg(id), '{}') from public.marketing_campaign where approved_hash is not null and approved_hash = public.fn_marketing_campaign_hash(id));
  r jsonb := '{}'::jsonb; v_fail text := ''; v_comp bigint; v_scan bigint; v_feed bigint; v_brief0 jsonb; v_text text; v_handles jsonb;
begin
  -- C06 1: a week with no reading claims no finding
  v_brief0 := public.fn_marketing_competitor_refresh_duty();
  r := r || jsonb_build_object('C06_brief_before', v_brief0 - 'scan' || jsonb_build_object('scan', v_brief0->'scan'));
  if (v_brief0->>'claims_findings')::boolean and (v_brief0#>>'{inputs,pages_read_this_week}')::int = 0 and (v_brief0#>>'{inputs,posts_seen_this_week}')::int = 0 then
    v_fail := v_fail || 'a brief on no input claimed findings; ';
  end if;

  -- C06 2: the greedy strip is gone; a real page keeps its text and yields its public links
  insert into public.competitor (name, url, kind, what_they_do, watched) values
    ('ZZ DEMO competitor probe', 'https://zz-demo.example.invalid/', 'marketplace', 'ZZ DEMO probe subject', false) returning id into v_comp;
  insert into public.competitor_scan (competitor_id, page_kind, url, status) values (v_comp, 'home', 'https://zz-demo.example.invalid/', 'fetching') returning id into v_scan;
  perform public.fn_competitor_scan_ingest(v_scan, 200,
    '<html><head><script>var a=1;</script><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head><body>'
    || '<script src="x.js"></script><h1>ZZ DEMO marketplace KEEP THIS TEXT</h1><p>' || repeat('Suppliers quote buyers in Dubai and Abu Dhabi. ', 8)
    || '</p><a href="https://www.instagram.com/zzdemo_probe/">ig</a><a href="https://www.linkedin.com/company/zz-demo-probe">li</a>'
    || '<script>tail()</script></body></html>', null);
  select page_text into v_text from public.competitor_scan where id = v_scan;
  select social_handles into v_handles from public.competitor where id = v_comp;
  r := r || jsonb_build_object('C06_page_chars', length(v_text), 'C06_page_kept_body', v_text like '%KEEP THIS TEXT%', 'C06_handles', v_handles,
                               'C06_scan_status', (select status from public.competitor_scan where id = v_scan));
  if v_text is null or v_text not like '%KEEP THIS TEXT%' then v_fail := v_fail || 'page text eaten; '; end if;
  if v_handles->>'instagram' is distinct from 'zzdemo_probe' or v_handles->>'rss' is distinct from 'https://zz-demo.example.invalid/feed.xml' then
    v_fail := v_fail || 'public links not read; '; end if;

  -- C06 3: a shell page is a failure, not a collection
  insert into public.competitor_scan (competitor_id, page_kind, url, status) values (v_comp, 'pricing', 'https://zz-demo.example.invalid/p', 'fetching') returning id into v_scan;
  perform public.fn_competitor_scan_ingest(v_scan, 200, '<html><script>' || repeat('x', 5000) || '</script><div id="root"></div></html>', null);
  r := r || jsonb_build_object('C06_shell', (select jsonb_build_object('status', status, 'error', error) from public.competitor_scan where id = v_scan));
  if (select status from public.competitor_scan where id = v_scan) <> 'failed' then v_fail := v_fail || 'a script shell counted as collected; '; end if;

  -- C06 4: the feed's posts land in market_intel
  insert into public.competitor_scan (competitor_id, page_kind, url, status) values (v_comp, 'feed', 'https://zz-demo.example.invalid/feed.xml', 'fetching') returning id into v_feed;
  perform public.fn_competitor_scan_ingest(v_feed, 200,
    '<rss><channel><item><title><![CDATA[ZZ DEMO post one]]></title><link>https://zz-demo.example.invalid/a</link><guid>zz-demo-a</guid>'
    || '<pubDate>Mon, 13 Oct 2026 10:00:00 +0000</pubDate></item><item><title>ZZ DEMO post two</title><link>https://zz-demo.example.invalid/b</link></item></channel></rss>', null);
  r := r || jsonb_build_object('C06_feed_posts', (select count(*) from public.market_intel where competitor_id = v_comp and platform = 'rss'));
  if (r->>'C06_feed_posts')::int <> 2 then v_fail := v_fail || 'feed posts not stored; '; end if;
  r := r || jsonb_build_object('C06_brief_after', (public.fn_marketing_competitor_refresh_duty())->'inputs');

  -- the nine duties, against production as it stands
  r := r || jsonb_build_object('C03', public.fn_marketing_geo_fix());
  r := r || jsonb_build_object('C05', public.fn_marketing_recruitment_funnel() - 'diagnosis');
  r := r || jsonb_build_object('C07', public.fn_marketing_reputation() - 'snapshot');
  r := r || jsonb_build_object('C10', public.fn_marketing_social_publish());
  r := r || jsonb_build_object('C11', public.fn_marketing_social_inbox());
  r := r || jsonb_build_object('C12', public.fn_marketing_trend_decision() - 'silent_feeds');
  r := r || jsonb_build_object('C13', public.fn_marketing_kpi_scorecard()->'month_to_date');
  r := r || jsonb_build_object('C14', public.fn_marketing_fact_register());
  r := r || jsonb_build_object('C15', public.fn_marketing_paid_spend_report());
  r := r || jsonb_build_object(
    'geo_fixes_open', (select count(*) from public.marketing_geo_fix where status = 'open'),
    'trends_unjudged_after', (select count(*) from public.marketing_trend where relevant is null),
    'duty_records', (select count(*) from public.marketing_duty_record),
    'seat_duties_registered', (select count(*) from public.seat_duty where duty in ('marketing.geo_fix', 'marketing.social_publish', 'marketing.social_inbox',
        'marketing.trend_decision', 'marketing.kpi_scorecard', 'marketing.fact_register', 'marketing.paid_spend_report')),
    'paid_allowed_after', public.fn_marketing_paid_allowed(),
    'notifications_added', (select count(*) from public.notifications where created_at = now() or xmin::text = v_xid),
    'posts_by_status_unchanged', not exists (select 1 from public.marketing_post p where (p.xmin::text = v_xid or p.updated_at = now())
                                               and p.status is distinct from p0->>(p.id::text)),
    'approvals_voided', (select count(*) from public.marketing_campaign c where c.id = any(a0)
                           and c.approved_hash is distinct from public.fn_marketing_campaign_hash(c.id)));
  if (r->>'approvals_voided')::int <> 0 then v_fail := v_fail || 'an approved campaign lost its approval (a post of it was edited); '; end if;
  if (r->>'notifications_added')::int <> 0 then v_fail := v_fail || 'a notification was written; '; end if;
  if not (r->>'posts_by_status_unchanged')::boolean then v_fail := v_fail || 'a post changed status; '; end if;
  if (r->>'paid_allowed_after')::boolean then v_fail := v_fail || 'paid was switched on; '; end if;
  if (r->>'seat_duties_registered')::int <> 7 then v_fail := v_fail || 'a duty is not registered; '; end if;
  if (r->>'trends_unjudged_after')::int > 0 and (select count(*) from public.marketing_trend where relevant is null and seen_at < now() - interval '48 hours') > 0 then
    v_fail := v_fail || 'a trend older than 48h is undecided; '; end if;
  if (r#>>'{C05,totals,pool}') is null then v_fail := v_fail || 'funnel totals still null; '; end if;
  if (r#>>'{C05,company_funnel,delivered}') is null then v_fail := v_fail || 'company funnel not measured; '; end if;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' else 'PROBE FAILED: ' || v_fail end || r::text;
end $probe$;
