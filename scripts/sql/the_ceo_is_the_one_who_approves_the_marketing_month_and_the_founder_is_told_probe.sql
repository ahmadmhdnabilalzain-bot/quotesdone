-- PROBE: THE CEO IS THE ONE WHO APPROVES THE MARKETING MONTH. Seat: marketing + ceo. Agent: simplify_build_D, 16 Nov 2026.
-- Pure probe: no DDL, never applied; run after the_ceo_is_the_one_who_approves_the_marketing_month_and_the_founder_is_told.sql
-- on a LOCAL Postgres 16 (never on production). It always raises, so every row is rolled back. The calendar is a ZZ DEMO one.
-- PROBE OK only if the founder's authenticated "approve" reply to a calendar he was sent, unedited and with posts still to go:
--   1. leaves the calendar unapproved (approved_hash, approved_by, approved_at all null);
--   2. is answered with outcome 'ceo_approves' and 'approved' false, in a mail that asks him for nothing;
--   3. a change request from him still reaches the marketing seat (marketing_founder_request).
do $probe$
declare fails text := ''; c bigint; v_tok text := md5('zz-demo-wave-d-calendar'); v_hash text; j jsonb; n int;
begin
  insert into public.marketing_campaign (campaign_key, theme, title, month, calendar_token, is_demo, spend_policy)
  values ('zz-demo-wave-d-calendar', 'ZZ DEMO wave D', 'ZZ DEMO calendar', date_trunc('month', now() + interval '40 days')::date, v_tok, true, 'organic_only')
  returning id into c;
  insert into public.marketing_post (campaign_id, ingest_key, ingested_by, text_en, channels, scheduled_at, is_demo)
  values (c, 'zz-demo-wave-d-post-1', 'marketing', 'ZZ DEMO post', array['linkedin'], now() + interval '20 days', true);
  v_hash := public.fn_marketing_campaign_hash(c);
  update public.marketing_campaign set calendar_hash = v_hash where id = c;

  j := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', public.fn_marketing_founder_email(),
         'authenticated', true, 'intent', 'approve', 'text', 'approve', 'message_id', 'zz-demo-wave-d-1'));
  if exists (select 1 from public.marketing_campaign where id = c and (approved_hash is not null or approved_by is not null or approved_at is not null)) then
    fails := fails || ' 1:the_founder_reply_approved_it';
  end if;
  if coalesce(j->>'outcome', '') <> 'ceo_approves' or coalesce((j->>'approved')::boolean, true) then fails := fails || ' 2:outcome=' || coalesce(j::text, 'null'); end if;
  if exists (select 1 from public.notifications where id = (j->>'reply_notification_id')::bigint and body ~* 'reply .{0,10}approve') then fails := fails || ' 2:asks_him_to_approve'; end if;

  j := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', public.fn_marketing_founder_email(),
         'authenticated', true, 'intent', 'change', 'text', 'ZZ DEMO move post 1 a day later', 'message_id', 'zz-demo-wave-d-2'));
  select count(*) into n from public.marketing_founder_request where campaign_id = c and kind = 'calendar_change';
  if n <> 1 or coalesce(j->>'outcome', '') <> 'change_requested' then fails := fails || ' 3:change=' || n || '/' || coalesce(j->>'outcome', 'null'); end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: the founder''s "approve" leaves the calendar unapproved and is answered ceo_approves, asking him for nothing; his change request still reaches the marketing seat>>';
end $probe$;
