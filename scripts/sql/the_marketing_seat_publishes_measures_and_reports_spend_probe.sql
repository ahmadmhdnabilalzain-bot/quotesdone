-- PROBE: THE MARKETING SEAT PUBLISHES, MEASURES AND REPORTS SPEND (22 Sep 2026; seat: marketing).
--
-- A pure probe (no DDL): it always ends in raise exception 'CHK<<...>>', so every row it writes -- the
-- ZZ DEMO posts, the spend rows, the handoffs and the accountant's month -- rolls back with it. Run it
-- AFTER the_marketing_seat_publishes_measures_and_reports_spend.sql and the seat build
-- (ceo/the-marketing-seat-exists, which registers adspend.recorded / adspend.booked and the seat) are
-- applied. The verdict is the first key of the CHK payload: PROBE OK or PROBE FAILED with what failed.
--
-- WHAT IT PROVES: ingest stores a bilingual scheduled post and refuses question-mark Arabic, a past
-- schedule and Instagram without media; spend from an account outside the Quotes Done business is
-- refused; a ZZ DEMO day is never handed off; a closed day is handed to the accountant ONCE, the
-- accountant keeps only closed days (today's moving figure excluded) as the reported side and answers
-- adspend.booked, which the seat acknowledges; the same figure is not handed twice and a revision is.
--
-- THE LOOP (review of #834 against #836's contract): adspend.booked carries recorded_handoff and marketing's
-- answer carries evidence.verified; #836's fn_marketing_closes_ad_spend_loops must then close every
-- adspend.recorded, the first figure and its revision alike, and the revision must be one row, revisions 2.
--
-- MEASURED 22 Sep 2026 against production in ONE rolled-back request: #836's seat file, then this build's
-- file, then this probe -> PROBE OK (closer: closed 1, waiting 0, mismatch 0); nothing persisted (re-read
-- afterwards: no marketing_post, no ad_spend_reported).
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketing_seat_publishes_measures_and_reports_spend_probe.sql --apply

do $probe$
declare
  r jsonb := '{}'::jsonb; x jsonb; v_acct text; v_day date := (now() at time zone 'Asia/Dubai')::date - 2;
  v_before_month int; v_bad text[] := '{}';
begin
  select 'act_' || regexp_replace(value, '^act_', '') into v_acct from public.app_secrets where key = 'meta_ad_account_id';
  select count(*) into v_before_month from public.accountant_ad_spend_month;

  -- ingest
  x := public.fn_marketing_post_ingest(jsonb_build_object('ingest_key', 'zz-demo-probe-1', 'ingested_by', 'claude',
        'text_en', 'ZZ DEMO — three quotes', 'text_ar', 'احصل على ثلاثة عروض', 'channels', jsonb_build_array('facebook', 'linkedin'),
        'scheduled_at', now() + interval '1 day', 'is_demo', true));
  r := r || jsonb_build_object('ingest', x);
  if not (x->>'ok')::boolean or x->>'status' <> 'scheduled' then v_bad := array_append(v_bad, 'ingest'::text); end if;
  x := public.fn_marketing_post_ingest(jsonb_build_object('ingest_key', 'zz-demo-probe-2', 'text_en', 'ZZ DEMO x', 'text_ar', '?? ????? ?????',
        'channels', jsonb_build_array('facebook'), 'is_demo', true));
  r := r || jsonb_build_object('ingest_question_marks', x->>'error');
  if coalesce(x->>'error', '') <> 'text_lost_its_script' then v_bad := array_append(v_bad, 'question_marks_accepted'::text); end if;
  x := public.fn_marketing_post_ingest(jsonb_build_object('ingest_key', 'zz-demo-probe-3', 'text_en', 'ZZ DEMO x', 'text_ar', 'مرحبا',
        'channels', jsonb_build_array('facebook'), 'scheduled_at', now() - interval '3 hours', 'is_demo', true));
  if coalesce(x->>'error', '') <> 'scheduled_in_the_past' then v_bad := array_append(v_bad, 'past_accepted'::text); end if;
  begin
    insert into public.marketing_post (ingest_key, ingested_by, text_en, text_ar, channels) values ('zz-demo-probe-4', 'claude', 'ZZ DEMO', 'مرحبا', array['instagram']);
    v_bad := array_append(v_bad, 'instagram_without_media_accepted'::text);
  exception when check_violation then null; end;

  -- ad spend: wrong business refused, demo never handed off, real closed day handed to the accountant and back
  x := public.fn_marketing_ad_spend_record(v_acct, '999', '[{"campaign_id":"c1","campaign_name":"x","day":"2026-09-01","spend":"5","currency":"AED"}]'::jsonb, false);
  r := r || jsonb_build_object('wrong_business', x->>'error');
  if coalesce(x->>'error', '') <> 'account_not_the_company' then v_bad := array_append(v_bad, 'wrong_business_recorded'::text); end if;
  x := public.fn_marketing_ad_spend_record(v_acct, '2335064440232533', jsonb_build_array(jsonb_build_object('campaign_id', 'zz1', 'campaign_name', 'ZZ DEMO camp', 'day', v_day, 'spend', '9', 'currency', 'AED')), true);
  r := r || jsonb_build_object('demo_record', x);
  if (x->>'handoffs')::int <> 0 then v_bad := array_append(v_bad, 'demo_handed_off'::text); end if;
  x := public.fn_marketing_ad_spend_record(v_acct, '2335064440232533', jsonb_build_array(
         jsonb_build_object('campaign_id', 'c1', 'campaign_name', 'QuotesDone probe', 'day', v_day, 'spend', '12.50', 'currency', 'AED', 'impressions', '900', 'clicks', '14'),
         jsonb_build_object('campaign_id', 'c1', 'campaign_name', 'QuotesDone probe', 'day', (now() at time zone 'Asia/Dubai')::date, 'spend', '3', 'currency', 'AED')), false);
  r := r || jsonb_build_object('real_record', x);
  if (x->>'handoffs')::int <> 1 then v_bad := array_append(v_bad, 'closed_day_not_handed_off_once'::text); end if;
  r := r || jsonb_build_object('handoffs', (select jsonb_agg(jsonb_build_object('agent', agent, 'status', status, 'type', detail->>'type', 'evidence', evidence) order by id)
                                              from public.agent_actions where kind = 'handoff' and detail->>'type' in ('adspend.recorded', 'adspend.booked') and created_at >= now()));
  if not exists (select 1 from public.accountant_ad_spend_month where month = date_trunc('month', v_day)::date and reported_spend_aed = 12.50) then v_bad := array_append(v_bad, 'reported_not_kept'::text); end if;
  if not exists (select 1 from public.marketing_ad_spend_day where account_id = v_acct and day = v_day and booked_ack_at is not null) then v_bad := array_append(v_bad, 'not_acknowledged'::text); end if;
  if not exists (select 1 from public.ad_spend_reported where source_ref = v_acct || ':c1:' || v_day and amount = 12.50) then v_bad := array_append(v_bad, 'not_on_the_accountants_record'::text); end if;
  -- THE LOOP CLOSES: #836's closer reads adspend.booked's evidence.verified and recorded_handoff
  if not exists (select 1 from public.agent_actions b join public.agent_actions h on h.id = (b.detail->>'recorded_handoff')::bigint
                  where b.kind = 'handoff' and b.agent = 'marketing' and b.detail->>'type' = 'adspend.booked'
                    and (b.evidence->>'verified')::boolean and h.detail->>'type' = 'adspend.recorded') then
    v_bad := array_append(v_bad, 'booked_reply_not_verified_or_not_linked'::text);
  end if;
  x := public.fn_marketing_closes_ad_spend_loops();
  r := r || jsonb_build_object('closer', x);
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'adspend.recorded'
                and detail->>'source_ref' like v_acct || ':c1:%' and status <> 'done') then
    v_bad := array_append(v_bad, 'adspend_recorded_left_open'::text);
  end if;
  -- re-reading the same figure hands nothing off again; a revision does, and closes too
  x := public.fn_marketing_ad_spend_record(v_acct, '2335064440232533', jsonb_build_array(jsonb_build_object('campaign_id', 'c1', 'campaign_name', 'QuotesDone probe', 'day', v_day, 'spend', '12.50', 'currency', 'AED')), false);
  if (x->>'handoffs')::int <> 0 then v_bad := array_append(v_bad, 'same_figure_handed_twice'::text); end if;
  x := public.fn_marketing_ad_spend_record(v_acct, '2335064440232533', jsonb_build_array(jsonb_build_object('campaign_id', 'c1', 'campaign_name', 'QuotesDone probe', 'day', v_day, 'spend', '13.00', 'currency', 'AED')), false);
  if (x->>'handoffs')::int <> 1 then v_bad := array_append(v_bad, 'revision_not_handed'::text); end if;
  perform public.fn_marketing_closes_ad_spend_loops();
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'adspend.recorded'
                and detail->>'source_ref' like v_acct || ':c1:%' and status <> 'done') then
    v_bad := array_append(v_bad, 'revision_left_open'::text);
  end if;
  if not exists (select 1 from public.ad_spend_reported where source_ref = v_acct || ':c1:' || v_day and amount = 13.00 and revisions = 2) then
    v_bad := array_append(v_bad, 'revision_not_a_revision'::text);
  end if;
  if not exists (select 1 from public.accountant_ad_spend_month where month = date_trunc('month', v_day)::date and reported_spend_aed = 13.00) then
    v_bad := array_append(v_bad, 'invoice_match_not_revised'::text);
  end if;

  x := public.fn_marketing_report_figures(now() - interval '1 day', now());
  if not (x ? 'headline' and x ? 'not_measured' and x ? 'basis' and x->'measured' ?& array['posts_published', 'ad_spend_reported_aed',
          'conversations_handed_to_founder', 'customer_requests_posted', 'insights', 'connections_all_ok']) then
    v_bad := array_append(v_bad, 'report_figures_lost_the_seat_build_shape'::text);
  end if;
  if (select count(*) from public.fn_table_export_list() where table_name like 'marketing\_%') <> 5 then
    v_bad := array_append(v_bad, 'marketing_tables_not_in_the_daily_export'::text);
  end if;
  r := r || jsonb_build_object('duties_due', public.fn_marketing_duties_due(), 'report', public.fn_marketing_report_figures(now() - interval '1 day', now()),
                               'registry', (select count(*) from public.fn_backup_source_registry() where source in ('marketing-media', 'marketing_post.media_paths')),
                               'credential', (select count(*) from public.internal_credential where context = 'fn.marketing_channels'));
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'bad', v_bad, 'r', r);
end $probe$;
