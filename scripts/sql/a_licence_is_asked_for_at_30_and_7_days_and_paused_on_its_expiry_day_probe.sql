-- PROBE: licence asks at 30 and 7 days, the pause on the expiry day, the restore only on a later date.
-- Pure probe, no DDL: run AFTER a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day.sql; it always ends
-- in raise exception CHK<<...>>, so nothing it writes survives, and every message it queues is to a ZZ DEMO
-- @example.invalid supplier (suppressed by the demo capture, then rolled back). It inserts three ZZ DEMO suppliers of its own and borrows one
-- APPROVED demo supplier on an @example.invalid address (the only kind it may pause), moving its licence date inside the
-- rolled-back transaction.
-- PROBE OK only if:
--   1. 20 days out -> one t_minus_30 email ask; 12 days out -> t_minus_30 (no 14-day ask any more); 5 days -> t_minus_7;
--      expiry day -> no ask from the sweep;
--   2. a second sweep the same day adds nothing (one message per threshold);
--   3. the approved supplier whose licence expires TODAY is paused (licence_expired) and told, the one at 5 days is not;
--   4. its date moved to next year (a renewed licence approved) -> restored; moved only to today -> still paused.
do $probe$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
        a bigint; b bigint; c bigint; d bigint; v_fail text := ''; n1 int; n2 int; v_bands text; l public.leads; v_told int;
begin
  select id into c from public.leads where is_demo and approval_status = 'approved' and not coalesce(banned, false)
     and public.fn_is_demo_email(email) and public.fn_is_demo_email(coalesce(claimed_by, email)) order by id limit 1;
  if c is null then raise exception 'CHK<<PROBE FAILED: no approved ZZ DEMO supplier on an @example.invalid address to pause>>'; end if;
  -- the other three are the probe's own ZZ DEMO suppliers, inserted here and rolled back with everything else
  insert into public.leads (company_name, email, emirate, tags, source) values
    ('ZZ DEMO licence probe A', 'qd-licprobe-a@example.invalid', 'Dubai', array['qd_demo'], 'qd_demo_fixture') returning id into a;
  insert into public.leads (company_name, email, emirate, tags, source) values
    ('ZZ DEMO licence probe B', 'qd-licprobe-b@example.invalid', 'Dubai', array['qd_demo'], 'qd_demo_fixture') returning id into b;
  insert into public.leads (company_name, email, emirate, tags, source) values
    ('ZZ DEMO licence probe D', 'qd-licprobe-d@example.invalid', 'Dubai', array['qd_demo'], 'qd_demo_fixture') returning id into d;

  update public.leads set license_expiry = v_today + 20 where id = a;
  update public.leads set license_expiry = v_today + 12 where id = d;
  update public.leads set license_expiry = v_today + 5, matching_blocked = false, matching_block_reason = null where id = b;
  update public.leads set license_expiry = v_today,     matching_blocked = false, matching_block_reason = null where id = c;
  delete from public.licence_renewal_ask where lead_id in (a, b, c, d);

  perform public.fn_licence_expiry_sweep(false);
  select count(*) into n1 from public.licence_renewal_ask where lead_id in (a, b, c, d) and channel = 'email';
  select string_agg(lead_id || ':' || band, ',' order by lead_id) into v_bands
    from public.licence_renewal_ask where lead_id in (a, b, c, d) and channel = 'email';
  perform public.fn_licence_expiry_sweep(false);
  select count(*) into n2 from public.licence_renewal_ask where lead_id in (a, b, c, d) and channel = 'email';

  if not exists (select 1 from public.licence_renewal_ask where lead_id = a and band = 't_minus_30' and channel = 'email') then v_fail := v_fail || ' 20 days: no 30-day ask;'; end if;
  if not exists (select 1 from public.licence_renewal_ask where lead_id = d and band = 't_minus_30' and channel = 'email') then v_fail := v_fail || ' 12 days: no 30-day ask;'; end if;
  if exists (select 1 from public.licence_renewal_ask where lead_id in (a, b, c, d) and band in ('t_minus_14', 'expired')) then v_fail := v_fail || ' a 14-day or expired ask was sent;'; end if;
  if not exists (select 1 from public.licence_renewal_ask where lead_id = b and band = 't_minus_7' and channel = 'email') then v_fail := v_fail || ' 5 days: no 7-day ask;'; end if;
  if exists (select 1 from public.licence_renewal_ask where lead_id = c) then v_fail := v_fail || ' the expiry day got a sweep ask;'; end if;
  if n1 <> 3 or n2 <> 3 then v_fail := v_fail || ' asks ' || n1 || ' then ' || n2 || ' (want 3 then 3);'; end if;

  perform public.fn_reconcile_doc_blocks(0);
  select * into l from public.leads where id = c;
  if not (l.matching_blocked and l.matching_block_reason = 'licence_expired') then v_fail := v_fail || ' the expiry day did not pause;'; end if;
  select count(*) into v_told from public.notifications where lead_id = c and type = 'doc_suspended' and channel = 'email' and created_at >= now();
  if v_told <> 1 then v_fail := v_fail || ' paused supplier told ' || v_told || ' times;'; end if;
  if (select matching_blocked from public.leads where id = b) then v_fail := v_fail || ' 5 days out was paused;'; end if;

  perform public.fn_reconcile_doc_blocks(0);
  if (select count(*) from public.notifications where lead_id = c and type = 'doc_suspended' and channel = 'email' and created_at >= now()) <> 1 then
    v_fail := v_fail || ' a second run told the paused supplier again;'; end if;
  if not (select matching_blocked from public.leads where id = c) then v_fail := v_fail || ' unpaused while the date is still today;'; end if;
  update public.leads set license_expiry = v_today + 365 where id = c;
  perform public.fn_reconcile_doc_blocks(0);
  if (select matching_blocked from public.leads where id = c) then v_fail := v_fail || ' not restored after a renewed date;'; end if;

  if exists (select 1 from public.notifications where created_at >= now() and lead_id in (a, b, c, d)
              and not public.fn_is_demo_email(to_email) and to_email is not null) then
    v_fail := v_fail || ' a message to a non-demo address;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK asks ' || v_bands || ' (once each on a re-run); expiry day '
      || c || ' paused + told once, restored on a renewed date; 5 days out not paused'
    else 'PROBE FAILED:' || v_fail || ' bands=' || coalesce(v_bands, 'none') end;
end $probe$;
