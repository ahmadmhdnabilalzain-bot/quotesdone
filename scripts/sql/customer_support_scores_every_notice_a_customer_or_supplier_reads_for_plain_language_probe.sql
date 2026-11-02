-- PROBE for customer_support_scores_every_notice_a_customer_or_supplier_reads_for_plain_language.sql (customer_support,
-- 27 Oct 2026). A pure probe: it always raises CHK<<...>>, so every row it writes is rolled back. It writes only ZZ DEMO
-- notices to @example.invalid addresses and runs the duty in fixture mode, which opens causes from demo rows only.
--   a. three failing ZZ DEMO notices of one type, written by sales_engineer, open ONE cause handed to sales_engineer
--      (support.root_cause) whose note names the decision and the ask;
--   b. three plain ZZ DEMO notices of that type written after it close the cause; customer_support closes the handoff
--      and the close cites the note (fn_seat_handoff_complete);
--   c. no cause or handoff was opened for a real (non-demo) notice type.
do $probe$
declare
  v_r1 jsonb; v_r2 jsonb; c public.notice_plain_language_cause; h public.agent_actions; v_fail text := ''; i int;
  v_real_causes int; v_bad text := 'ZZ DEMO Pursuant to the RFQ terms herein, the backend workflow routed your request to the endpoint and the SLA now applies to every supplier who answers it.';
  v_good text := 'ZZ DEMO Your request is ready. Open it to compare the quotes. Reply here if you need help.';
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  for i in 1..3 loop
    insert into public.notifications (type, to_email, to_role, subject, body, channel, requested_by)
    values ('zz_demo_plain_probe', 'zz-plain-' || i || '@example.invalid', 'customer', 'ZZ DEMO probe', v_bad, 'email', 'sales_engineer');
  end loop;
  v_r1 := public.fn_customer_support_notice_plain_language();
  select * into c from public.notice_plain_language_cause where type = 'zz_demo_plain_probe' and fixture;
  if c.id is null then v_fail := v_fail || ' a(no cause)';
  else
    if c.owner_seat <> 'sales_engineer' or c.status <> 'handed_off' or c.handoff_id is null then v_fail := v_fail || ' a(' || c.owner_seat || '/' || c.status || ')'; end if;
    select * into h from public.agent_actions where id = c.handoff_id;
    if h.agent <> 'sales_engineer' or h.detail->>'type' <> 'support.root_cause'
       or nullif(h.detail->'summary'->>'decision', '') is null or jsonb_array_length(h.detail->'summary'->'open_asks') = 0 then
      v_fail := v_fail || ' a(handoff note)';
    end if;
  end if;

  for i in 1..3 loop
    insert into public.notifications (type, to_email, to_role, subject, body, channel, requested_by)
    values ('zz_demo_plain_probe', 'zz-plain-ok-' || i || '@example.invalid', 'customer', 'ZZ DEMO probe', v_good, 'email', 'sales_engineer');
  end loop;
  v_r2 := public.fn_customer_support_notice_plain_language();
  select * into c from public.notice_plain_language_cause where id = c.id;
  if c.status <> 'closed' then v_fail := v_fail || ' b(cause ' || coalesce(c.status, 'null') || ')'; end if;
  select * into h from public.agent_actions where id = c.handoff_id;
  if h.status <> 'done' or (h.evidence->'cites_note'->>'handoff_id') is distinct from h.id::text then v_fail := v_fail || ' b(handoff not closed citing)'; end if;

  select count(*) into v_real_causes from public.notice_plain_language_cause where not fixture;
  if v_real_causes <> 0 then v_fail := v_fail || ' c(' || v_real_causes || ' real causes in fixture mode)'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK run1=' || v_r1::text || ' run2=' || v_r2::text
                                    else 'PROBE FAILED:' || v_fail || ' run1=' || coalesce(v_r1::text, 'null') end;
end $probe$;
