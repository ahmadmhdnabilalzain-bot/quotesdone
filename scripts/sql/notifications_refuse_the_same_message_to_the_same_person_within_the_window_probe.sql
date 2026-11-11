-- notifications_refuse_the_same_message_to_the_same_person_within_the_window_probe.sql — a PURE probe: it always raises
-- CHK<<...>>, so every row it writes rolls back. Assigned: it_engineer (ruling 1631).
-- It writes only to a reserved RFC 2606 address (never deliverable: send_outbox refuses .invalid before any provider) and
-- counts real rows before and after, so it cannot reach a person. Run after the DDL file, or with it in one rolled-back
-- transaction. Expect: CHK<<PROBE OK ...>>.
do $probe$
declare
  v_to text := 'zz-demo-dup-probe-' || txid_current() || '@example.invalid';
  v_real_before bigint := (select count(*) from public.notifications where to_email not ilike '%example.invalid');
  v_a public.notifications; v_b public.notifications; v_c public.notifications;
begin
  -- the first copy as already SENT: the demo-capture triggers leave a non-queued row alone, so it stays what it is
  insert into public.notifications (type, to_email, channel, subject, body, status, sent_at)
    values ('zz_demo_probe', v_to, 'email', 'ZZ DEMO the same message', 'ZZ DEMO body', 'sent', now()) returning * into v_a;
  insert into public.notifications (type, to_email, channel, subject, body, status)
    values ('zz_demo_probe', upper(v_to), 'email', 'ZZ DEMO the same  message', E'ZZ DEMO\nbody', 'queued') returning * into v_b;
  insert into public.notifications (type, to_email, channel, subject, body, status)
    values ('zz_demo_probe', v_to, 'email', 'ZZ DEMO the same message', 'ZZ DEMO a different body (a new code)', 'queued') returning * into v_c;
  if (select count(*) from public.notifications where to_email not ilike '%example.invalid') <> v_real_before then
    raise exception 'CHK<<PROBE FAILED: a real row changed>>';
  end if;
  if v_b.status <> 'cancelled' or position(('#' || v_a.id) in coalesce(v_b.last_error, '')) = 0 then
    raise exception 'CHK<<PROBE FAILED: the repeat was % (%), expected cancelled naming #%>>', v_b.status, v_b.last_error, v_a.id;
  end if;
  if v_c.status = 'cancelled' and coalesce(v_c.last_error, '') like 'duplicate:%' then
    raise exception 'CHK<<PROBE FAILED: a different body was refused as a duplicate>>';
  end if;
  raise exception 'CHK<<PROBE OK: first %, repeat cancelled naming it, a different text untouched (%)>>', v_a.status, v_c.status;
end
$probe$;
