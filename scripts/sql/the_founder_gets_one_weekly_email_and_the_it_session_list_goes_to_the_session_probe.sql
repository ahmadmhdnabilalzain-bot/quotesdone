-- PROBE for the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.sql. Seat: it_engineer with ceo.
-- Never applied: it always raises CHK<<...>> and rolls back everything, the one e-mail it queues included (the outbox
-- reads committed rows only, so nothing it writes can leave).
do $probe$
declare v_rep bigint; v_rev bigint; d jsonb; r jsonb; v jsonb; v_bad text := ''; v_before bigint; v_new int; v_att int; v_it int;
begin
  select coalesce(max(id), 0) into v_before from public.notifications;
  -- P5: the evening digest of a day with no decision of his writes the session list and mails nothing
  d := public.fn_customer_support_sends_the_it_digest(timestamptz '2026-11-11 19:30+04');
  if not exists (select 1 from public.it_session_fix_day where day = date '2026-11-11') then v_bad := v_bad || ' no-session-row'; end if;
  select count(*) into v_it from public.notifications where id > v_before and kind = 'it_daily_digest';
  if coalesce((d->>'decisions')::int, 0) = 0 and v_it > 0 then v_bad := v_bad || ' digest-mailed-without-a-decision'; end if;

  -- P6: the company report of W45 is handed over without an e-mail; the Monday review carries both PDFs in one e-mail
  select id into v_rep from public.ceo_weekly_report where report_key = 'quotesdone:2026-W45' and pdf_path is not null order by revision desc limit 1;
  select id into v_rev from public.ceo_weekly_review where week = date '2026-11-09' and pdf_path is not null;
  if v_rep is null or v_rev is null then raise exception 'CHK<<PROBE FAILED: the W45 report or the 9 Nov review is missing>>'; end if;
  select coalesce(max(id), 0) into v_before from public.notifications;
  update public.ceo_weekly_report set founder_submitted_at = null, status = 'generated' where id = v_rep;
  r := public.fn_ceo_weekly_report_deliver(v_rep);
  if (select count(*) from public.notifications where id > v_before) <> 0 then v_bad := v_bad || ' board-report-mailed'; end if;
  if (select status from public.ceo_weekly_report where id = v_rep) <> 'delivered' then v_bad := v_bad || ' report-not-handed-over'; end if;
  update public.ceo_weekly_review set delivered_at = null where id = v_rev;
  v := public.fn_ceo_weekly_review_deliver(v_rev);
  select count(*) into v_new from public.notifications where id > v_before and channel = 'email' and to_role = 'founder';
  select max(jsonb_array_length(coalesce(attachments, '[]'))) into v_att from public.notifications where id > v_before and kind = 'ceo_weekly_review' and channel = 'email';
  if v_new <> 1 then v_bad := v_bad || ' weekly-emails=' || v_new; end if;
  if coalesce(v_att, 0) <> 2 then v_bad := v_bad || ' attachments=' || coalesce(v_att, 0) || ' ' || coalesce(v->>'error', ''); end if;
  if (select body from public.notifications where id > v_before and kind = 'ceo_weekly_review' and channel = 'email' order by id limit 1) !~ 'company report for' then v_bad := v_bad || ' no-report-text'; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK IT digest: % session items kept for the session, % mailed; W45 report handed over unmailed; one weekly e-mail with % attachments>>', d->>'session_items', v_it, v_att;
end $probe$;
