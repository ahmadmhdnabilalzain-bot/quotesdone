-- PROBE: a notice the language trigger re-words carries the job number both portals print (inquiries.rfq_no),
-- never the uuid prefix. Pure probe -- NO DDL in this file. Seat: sales_engineer. 21 Sep 2026.
-- Pairs with one_job_number_on_every_portal_document_and_notice.sql (audit 21 Sep 2026, findings 7 and 37).
--
-- Run it with: node scripts/qsql.mjs scripts/sql/one_job_number_on_every_portal_document_and_notice_probe.sql
--
-- HOW IT STAYS HARMLESS: the notification is inserted inside an inner block that ALWAYS ends in a raised
-- exception, so the row, and anything an AFTER trigger queued for it, is rolled back before this
-- transaction could ever commit. The recipient is the founder-demo customer (ZZ DEMO, @example.invalid),
-- whose inquiry 8b287960 is rfq 151768 (measured 21 Sep 2026). The verdict is ONE row from the final select.
--
-- WHAT IT ASSERTS
--   1. fn_job_no(inquiry) = inquiries.rfq_no::text.
--   2. An English notice to an Arabic recipient is re-worded by a04_notifications_speak_the_recipients_language,
--      and the body carries 'QD-<rfq_no>' and not 'QD-<first 8 of the uuid>'.
--   3. The demo customer's name no longer ends in the stray ' a' (finding 37).
--   4. 0 notification rows carry the probe's marker afterwards.
begin;

do $$
declare
  v_inq uuid; v_rfq bigint; v_job text; v_body text; v_name text; v_left int;
  v_marker text := 'zz-demo-job-number-probe-marker';
begin
  set local statement_timeout = '8s';
  select i.id, i.rfq_no into v_inq, v_rfq
    from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.email = 'qd-founderdemo-cust1@example.invalid'
   order by i.created_at limit 1;
  if v_inq is null then raise exception 'the founder-demo customer has no inquiry, so nothing below measures the job number'; end if;

  v_job := public.fn_job_no(v_inq);
  if v_job is distinct from v_rfq::text then
    raise exception 'fn_job_no(%) = %, expected rfq_no %', v_inq, v_job, v_rfq;
  end if;

  begin
    insert into public.notifications (type, to_role, to_email, inquiry_id, channel, status, lang, subject, body)
    values ('zz_demo_probe_unknown_type', 'customer', 'qd-founderdemo-cust1@example.invalid', v_inq, 'email', 'queued', 'ar',
            'ZZ DEMO probe', 'ZZ DEMO probe English body ' || v_marker)
    returning body into v_body;
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_PROBE' then raise; end if;
  end;

  if v_body is null or position('QD-' || v_rfq::text in v_body) = 0 then
    raise exception 'the re-worded notice does not carry QD-%: %', v_rfq, v_body;
  end if;
  if position('QD-' || upper(left(replace(v_inq::text, '-', ''), 8)) in v_body) > 0 then
    raise exception 'the re-worded notice still carries the uuid prefix: %', v_body;
  end if;

  select full_name into v_name from public.customers where email = 'qd-founderdemo-cust1@example.invalid';
  if v_name ~ '\sa$' then raise exception 'the demo customer name still ends in " a": %', v_name; end if;

  select count(*) into v_left from public.notifications where body like '%zz-demo-job-number-probe-%';
  if v_left <> 0 then raise exception 'probe notifications left behind: %', v_left; end if;

  perform set_config('qd.probe_verdict',
    format('PROBE OK job_no=%s notice_ref=QD-%s name=%s left_behind=0', v_job, v_rfq, v_name), true);
exception when others then
  perform set_config('qd.probe_verdict', 'PROBE FAILED ' || sqlerrm, true);
end $$;

select coalesce(current_setting('qd.probe_verdict', true), 'PROBE FAILED (the block set no verdict)') as verdict;

rollback;
