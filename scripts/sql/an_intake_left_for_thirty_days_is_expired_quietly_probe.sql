-- PROBE: AN INTAKE LEFT FOR THIRTY DAYS IS EXPIRED QUIETLY.
-- Seat: sales_engineer. 10 Nov 2026. Pure probe: no DDL, never applied. Run after an_intake_left_for_thirty_days_is_expired_quietly.sql
-- (or concatenated after it). It always raises, so every row is rolled back. The routine is run with qd.duty_fixtures 'on'
-- and at a clock in the year 2000, so only the ZZ DEMO fixtures below, touched in 1999, are old enough for it to see.
-- PROBE OK only if a needs_info and a ready intake untouched for 31 days are expired with updated_at unchanged, one touched
-- 10 days ago and a consumed one are not, no notification is written, and the real intakes (fixtures off) are not seen.
do $probe$
declare
  fails text := ''; v jsonb; c uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); d uuid := gen_random_uuid(); e uuid := gen_random_uuid();
  at2000 timestamptz := '2000-01-01 08:00+00'; n0 bigint;
begin
  select count(*) into n0 from public.notifications;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Intake Customer', 'zz-demo-intake@example.invalid', '+971500000145', true, true, 'demo://terms', 'en', '1999-10-01');
  insert into public.inquiry_intake (id, customer_id, email, status, created_at, updated_at) values
    (a, c, 'zz-demo-intake@example.invalid', 'needs_info', '1999-11-01', at2000 - interval '31 days'),
    (b, c, 'zz-demo-intake@example.invalid', 'ready', '1999-11-01', at2000 - interval '31 days'),
    (d, c, 'zz-demo-intake@example.invalid', 'needs_info', '1999-11-01', at2000 - interval '10 days'),
    (e, c, 'zz-demo-intake@example.invalid', 'consumed', '1999-11-01', at2000 - interval '31 days');
  perform set_config('qd.duty_fixtures', 'on', true);
  v := public.fn_sales_engineer_expires_abandoned_intakes(at2000);
  if (v->>'expired')::int <> 2 or (select count(*) from public.inquiry_intake where id in (a, b) and status = 'expired' and updated_at = at2000 - interval '31 days') <> 2
     then fails := fails || ' expired(' || v::text || ')'; end if;
  if (select status from public.inquiry_intake where id = d) <> 'needs_info' or (select status from public.inquiry_intake where id = e) <> 'consumed' then fails := fails || ' others_touched'; end if;
  if (select count(*) from public.notifications) <> n0 then fails := fails || ' a_message_was_written'; end if;
  perform set_config('qd.duty_fixtures', 'off', true);
  v := public.fn_sales_engineer_expires_abandoned_intakes(at2000);
  if (v->>'expired')::int <> 0 then fails := fails || ' real_seen(' || v::text || ')'; end if;
  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK %>>', v::text;
end $probe$;
