-- a_notice_is_a_duplicate_only_of_the_same_event_probe.sql — a PURE probe: it always raises CHK<<...>>, so every row it
-- writes rolls back. Assigned: sales_engineer, 12 Nov 2026 (final audit M8, integration finding 4; ruling 1631).
-- It writes only to a reserved RFC 2606 address (never deliverable: send_outbox refuses .invalid before any provider) and
-- counts real rows before and after, so it cannot reach a person. Run after the DDL file, or with it in one rolled-back
-- transaction (node scripts/ci/rehearse_sql.mjs <file> <probe>). Run alone against the trigger of 12 Nov 2026 it answers
-- PROBE FAILED (the second supplier's quote is cancelled). Expect: CHK<<PROBE OK ...>>.
--   1. the audit's case: two suppliers' quotes on one request, the same text, 85 s apart: both stay queued;
--   2. the first quote's notice queued again (a retry after a 502): cancelled, naming the first;
--   3. the same text with no event named, twice (the seed list, the holding line): the second is cancelled, as before;
--   4. a supplier with three options told the requirements changed (fn_edit_inquiry writes one row per quote): told once.
do $probe$
declare
  v_to text := 'zz-demo-event-probe-' || txid_current() || '@example.invalid';
  v_real_before bigint := (select count(*) from public.notifications where to_email not ilike '%example.invalid');
  v_inq uuid := gen_random_uuid(); v_q1 uuid := gen_random_uuid(); v_q2 uuid := gen_random_uuid();
  a public.notifications; b public.notifications; c public.notifications; d public.notifications; e public.notifications;
  s1 public.notifications; s2 public.notifications; s3 public.notifications; v_q3 uuid := gen_random_uuid();
  v_sup text := 'zz-demo-event-probe-sup-' || txid_current() || '@example.invalid';
  v_subject text := 'You have a new quote on QuotesDone';
  v_body text := 'A supplier submitted a quote for your request: ZZ DEMO wall panels. Log in to view the full quotation and compare.';
begin
  -- the first supplier's notice as already SENT (the demo-capture triggers leave a non-queued row alone)
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, sent_at, inquiry_id, quote_id)
    values ('new_quote', v_to, 'customer', 'email', v_subject, v_body, 'sent', now(), v_inq, v_q1) returning * into a;
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, inquiry_id, quote_id)
    values ('new_quote', v_to, 'customer', 'email', v_subject, v_body, 'queued', v_inq, v_q2) returning * into b;
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, inquiry_id, quote_id)
    values ('new_quote', v_to, 'customer', 'email', v_subject, v_body, 'queued', v_inq, v_q1) returning * into c;
  insert into public.notifications (type, to_email, channel, subject, body, status, sent_at)
    values ('zz_demo_probe', v_to, 'email', 'ZZ DEMO the same message', 'ZZ DEMO body', 'sent', now()) returning * into d;
  insert into public.notifications (type, to_email, channel, subject, body, status)
    values ('zz_demo_probe', v_to, 'email', 'ZZ DEMO the same message', 'ZZ DEMO body', 'queued') returning * into e;
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, sent_at, inquiry_id, quote_id)
    values ('quote_requirements_changed', v_sup, 'supplier', 'email', 'ZZ DEMO requirements changed', 'ZZ DEMO please review', 'sent', now(), v_inq, v_q1) returning * into s1;
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, inquiry_id, quote_id)
    values ('quote_requirements_changed', v_sup, 'supplier', 'email', 'ZZ DEMO requirements changed', 'ZZ DEMO please review', 'queued', v_inq, v_q2) returning * into s2;
  insert into public.notifications (type, to_email, to_role, channel, subject, body, status, inquiry_id, quote_id)
    values ('quote_requirements_changed', v_sup, 'supplier', 'email', 'ZZ DEMO requirements changed', 'ZZ DEMO please review', 'queued', v_inq, v_q3) returning * into s3;
  if s2.status <> 'cancelled' or s3.status <> 'cancelled' then
    raise exception 'CHK<<PROBE FAILED: a supplier with three options was told % / % times more>>', s2.status, s3.status;
  end if;
  if (select count(*) from public.notifications where to_email not ilike '%example.invalid') <> v_real_before then
    raise exception 'CHK<<PROBE FAILED: a real row changed>>';
  end if;
  if b.status = 'cancelled' then
    raise exception 'CHK<<PROBE FAILED: the second supplier''s quote was cancelled as a duplicate (%)>>', b.last_error;
  end if;
  if c.status <> 'cancelled' or position(('#' || a.id) in coalesce(c.last_error, '')) = 0 then
    raise exception 'CHK<<PROBE FAILED: the same quote told again was % (%), expected cancelled naming #%>>', c.status, c.last_error, a.id;
  end if;
  if e.status <> 'cancelled' or position(('#' || d.id) in coalesce(e.last_error, '')) = 0 then
    raise exception 'CHK<<PROBE FAILED: the event-less repeat was % (%), expected cancelled naming #%>>', e.status, e.last_error, d.id;
  end if;
  raise exception 'CHK<<PROBE OK: two quotes are two notices (%), the same quote twice is cancelled, an event-less repeat is cancelled>>', b.status;
end
$probe$;
