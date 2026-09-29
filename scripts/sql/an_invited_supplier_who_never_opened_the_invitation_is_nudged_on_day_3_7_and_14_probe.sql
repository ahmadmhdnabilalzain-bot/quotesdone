-- PROBE (pure, no DDL, aborted transaction) for an_invited_supplier_who_never_opened_the_invitation_is_nudged_on_day_3_7_and_14.sql.
-- Run AFTER #1051's the_invitation_pool_is_read_once_as_a_set_so_the_daily_list_fits_its_timeout.sql (fn_supplier_invite_link)
-- and the definitions, all in the same transaction; it always ends in raise exception 'CHK<<json>>', so every row it
-- writes rolls back. Subjects: seven ZZ DEMO leads at @example.invalid, created here. Fixture mode of the nudger can only
-- see leads carrying BOTH marks, and every nudge row this probe produced is asserted to be at @example.invalid.
do $$
declare
  -- 06:00 UTC = 10:00 Dubai on the same date, so the UTC cap day and the Dubai day agree for the positive runs
  p_now timestamptz := ((now() at time zone 'UTC')::date + time '06:00') at time zone 'UTC';
  a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; g bigint; ids bigint[];
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; wk jsonb; early jsonb; dawn2 jsonb; night jsonb; fail text := ''; o jsonb;
  v_warm text; v_start int;
  v_real_before int; v_real_after int;
begin
  if extract(isodow from p_now at time zone 'Asia/Dubai') in (6, 7) then
    p_now := p_now + interval '2 days';   -- the positive case needs a weekday; queued rows are re-dated to p_now below
  end if;
  select count(*) into v_real_before from public.notifications where type = 'supplier_invite_nudge' and not public.fn_is_demo_email(to_email);

  -- lead a has an Arabic locale on purpose: its nudge must still be English (review, 29 Sep 2026)
  insert into public.leads (company_name, email, invited_at, locale) values
    ('ZZ DEMO — nudge day 4',   'zz-demo-nudge-a@example.invalid', p_now - interval '4 days', 'ar')  returning id into a;
  -- lead b carries Arabic script in its company name: #1070's greeting guard must keep it out of the English nudge
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — مورد تجريبي',   'zz-demo-nudge-b@example.invalid', p_now - interval '8 days')  returning id into b;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge day 15',  'zz-demo-nudge-c@example.invalid', p_now - interval '15 days') returning id into c;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge suppressed', 'zz-demo-nudge-d@example.invalid', p_now - interval '4 days') returning id into d;
  insert into public.leads (company_name, email, invited_at, invite_clicked_at) values
    ('ZZ DEMO — nudge clicked', 'zz-demo-nudge-e@example.invalid', p_now - interval '4 days', p_now - interval '3 days') returning id into e;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge day 25',  'zz-demo-nudge-f@example.invalid', p_now - interval '25 days') returning id into f;
  -- lead g only carries a same-UTC-day invitation for the cap-day case (never due: its anchor is 30 days old)
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge cap day', 'zz-demo-nudge-g@example.invalid', p_now - interval '30 days') returning id into g;
  ids := array[a, b, c, d, e, f, g];
  insert into public.email_suppressions (email, reason, source) values ('zz-demo-nudge-d@example.invalid', 'ZZ DEMO probe', 'probe');

  -- the invitation as the outbox records it (the anchor), dated per lead
  -- lang 'en' as the invitation is always English (without it a04 reads lead a's 'ar' locale and swaps the copy)
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  select 'supplier_invite', l.email, 'supplier', l.id, 'ZZ DEMO', 'ZZ DEMO https://quotesdone.com/en/portal?t=' || gen_random_uuid()::text, 'sent', l.invited_at, l.invited_at, 'email', 'en'
    from public.leads l where l.id = any(ids) and l.id <> g;
  update public.notifications set status = 'sent', sent_at = created_at where type = 'supplier_invite' and lead_id = any(ids);

  -- weekend: held, nothing queued
  wk := public.fn_sales_engineer_nudges_invited_suppliers(p_now + ((6 - extract(isodow from p_now at time zone 'Asia/Dubai'))::int * interval '1 day'), 10, true);
  if wk->>'held' is distinct from 'UAE weekend' then fail := fail || 'weekend not held: ' || wk::text || '; '; end if;

  -- THE DUTY'S OWN SLOT (review of #1007): supplier_onboarding runs at 00:01 UTC = 04:01 Dubai. A nudge due then is
  -- QUEUED, not held, and waits for 09:00 Dubai that day (not_before). 18:00 Dubai is past the window: held.
  -- The window start is read from invite_warmup.window_start_hour as the batch reads it (live: 10 on 29 Sep 2026).
  -- First with it set to 9 inside this rolled-back transaction (the default): not_before must be 09:00 Dubai.
  v_warm := (select value from public.app_secrets where key = 'invite_warmup');
  update public.app_secrets set value = (coalesce(nullif(v_warm, '')::jsonb, '{}'::jsonb) || '{"window_start_hour": 9}')::text
   where key = 'invite_warmup';
  early := public.fn_sales_engineer_nudges_invited_suppliers(p_now - interval '5 hours 59 minutes', 1, true);
  update public.app_secrets set value = v_warm where key = 'invite_warmup';
  if early->>'held' is not null or (early->>'queued')::int <> 1 then
    fail := fail || '04:01 Dubai did not queue: ' || early::text || '; ';
  elsif not exists (select 1 from public.notifications n where n.type = 'supplier_invite_nudge' and n.lead_id = any(ids)
                     and n.not_before = ((p_now at time zone 'Asia/Dubai')::date + time '09:00') at time zone 'Asia/Dubai') then
    fail := fail || '04:01 Dubai nudge does not wait for 09:00 Dubai: '
            || coalesce((select string_agg(coalesce(n.not_before::text, 'null'), ',') from public.notifications n
                          where n.type = 'supplier_invite_nudge' and n.lead_id = any(ids)), 'no row') || '; ';
  end if;
  -- Then with the live configuration: the next nudge waits for the configured hour, exactly as the batch would.
  v_start := coalesce((nullif(v_warm, '')::jsonb->>'window_start_hour')::int, 9);
  dawn2 := public.fn_sales_engineer_nudges_invited_suppliers(p_now - interval '5 hours 59 minutes', 2, true);
  if (dawn2->>'queued')::int <> 1 or (select count(*) from public.notifications n where n.type = 'supplier_invite_nudge' and n.lead_id = any(ids)
        and n.not_before = ((p_now at time zone 'Asia/Dubai')::date + make_interval(hours => v_start)) at time zone 'Asia/Dubai') <> 1 then
    fail := fail || '04:01 Dubai with the live window_start_hour ' || v_start || ' did not wait for it: ' || dawn2::text || '; ';
  end if;
  night := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '8 hours', 10, true);
  if night->>'held' is distinct from 'after the Dubai sending window' or (night->>'queued')::int <> 0 then
    fail := fail || '18:00 Dubai not held: ' || night::text || '; '; end if;
  -- reset, so the cap and idempotency runs below start from nothing queued
  delete from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids);
  delete from public.agent_actions where target_id like 'delivery.request:supplier_invite_nudge:%'
     and split_part(target_id, ':', 3)::bigint = any(ids);

  -- cap 2 with 3 due -> 2; again at cap 2 -> 0 (the cap is shared per day); cap 10 -> the 1 left; again -> 0 (idempotent)
  -- (queued rows carry now(); they are re-dated to p_now so a weekend-shifted p_now still counts them the same day)
  r1 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 2, true);
  update public.notifications set created_at = p_now where type = 'supplier_invite_nudge' and lead_id = any(ids);
  r2 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 2, true);
  r3 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);
  update public.notifications set created_at = p_now where type = 'supplier_invite_nudge' and lead_id = any(ids);
  r4 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);

  -- THE CAP DAY IS THE BATCH'S UTC DAY: an invitation queued at 21:00 UTC on p_now's UTC date is 01:00 Dubai the
  -- NEXT day. enqueue_supplier_invites counts it on p_now's day, so the nudger must too (a Dubai-date count would not).
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, channel, lang)
  values ('supplier_invite', 'zz-demo-nudge-g@example.invalid', 'supplier', g, 'ZZ DEMO',
          'ZZ DEMO https://quotesdone.com/en/portal?t=' || gen_random_uuid()::text, 'queued',
          ((p_now at time zone 'UTC')::date + time '21:00') at time zone 'UTC', 'email', 'en');
  r5 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);
  if (r5->>'used_before')::int <> (r4->>'used_before')::int + 1 then
    fail := fail || 'the cap day is not the batch''s UTC day: ' || r4::text || ' -> ' || r5::text || '; '; end if;

  select jsonb_object_agg(k, v) into o from (
    select 'a' k, (select string_agg(split_part(a2.target_id, ':', 4), ',') from public.agent_actions a2 where a2.target_id like 'delivery.request:supplier_invite_nudge:' || a || ':%') v
    union all select 'b', (select string_agg(split_part(a2.target_id, ':', 4), ',') from public.agent_actions a2 where a2.target_id like 'delivery.request:supplier_invite_nudge:' || b || ':%')
    union all select 'c', (select string_agg(split_part(a2.target_id, ':', 4), ',') from public.agent_actions a2 where a2.target_id like 'delivery.request:supplier_invite_nudge:' || c || ':%')) x;

  if (r1->>'due')::int <> 3 or (r1->>'queued')::int <> 2 then fail := fail || 'run1 ' || r1::text || '; '; end if;
  if (r2->>'queued')::int <> 0 then fail := fail || 'cap not shared across runs: ' || r2::text || '; '; end if;
  if (r3->>'queued')::int <> 1 then fail := fail || 'run3 ' || r3::text || '; '; end if;
  if (r4->>'queued')::int <> 0 or (r4->>'due')::int <> 0 then fail := fail || 'not idempotent: ' || r4::text || '; '; end if;
  if o->>'a' is distinct from '1' or o->>'b' is distinct from '2' or o->>'c' is distinct from '3' then fail := fail || 'wrong stage ' || o::text || '; '; end if;
  if exists (select 1 from public.agent_actions a2 where a2.target_id like any (array['delivery.request:supplier_invite_nudge:' || d || ':%',
             'delivery.request:supplier_invite_nudge:' || e || ':%', 'delivery.request:supplier_invite_nudge:' || f || ':%'])) then
    fail := fail || 'suppressed / clicked / past day 21 was nudged; '; end if;
  -- through the OUTBOX, not a status column
  if (select count(*) from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids)) <> 3 then
    fail := fail || 'outbox rows=' || (select count(*) from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids)) || '; '; end if;
  if exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids) and to_email not like '%@example.invalid') then
    fail := fail || 'a nudge left the fixture domain; '; end if;
  -- always English, the Arabic-locale lead included: lang 'en', the /en/ portal, no Arabic script anywhere
  if exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids)
              and (lang is distinct from 'en' or body !~ '/en/portal[?]t=' or body ~ '/ar/'
                   or coalesce(subject, '') || coalesce(body, '') ~ '[؀-ۿ]')) then
    fail := fail || 'a nudge is not English; '; end if;
  -- the link is the invitation's own (fn_supplier_invite_link, #1051): /en/portal with the token and the lead's ref
  if exists (select 1 from public.notifications n where n.type = 'supplier_invite_nudge' and n.lead_id = any(ids)
              and n.body !~ ('/en/portal[?]t=[0-9a-f-]{36}&utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-'
                              || n.lead_id || '(\s|$)')) then
    fail := fail || 'a nudge link is not fn_supplier_invite_link''s /en/ link with its ref; '; end if;
  -- no Arabic path left in either nudge's applied definition (read back): no /ar/ link, no 'ar' language
  if exists (select 1 from (values ('public.fn_sales_engineer_nudges_invited_suppliers(timestamptz,integer,boolean)'::regprocedure),
                                   ('public.fn_supplier_invite_nudges_due(timestamptz,boolean)'::regprocedure),
                                   ('public.fn_sales_engineer_supplier_onboarding()'::regprocedure)) f(p)
              where position('/ar/' in pg_get_functiondef(f.p)) > 0 or pg_get_functiondef(f.p) ~ '''ar''|v_ar') then
    fail := fail || 'a nudge definition still has an Arabic branch or /ar/ link; '; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = a) then
    fail := fail || 'the Arabic-locale lead was not nudged (in English); '; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = b and body like 'Dear Sir or Madam,%') then
    fail := fail || 'the Arabic-named lead was not greeted "Dear Sir or Madam"; '; end if;
  -- the invitation batch spends the same cap on the day's nudges (the applied definition, read back)
  if pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure)
       !~ 'into v_used from notifications where type in \(''supplier_invite'', ''supplier_invite_nudge''\)' then
    fail := fail || 'enqueue_supplier_invites does not count nudges against invite_daily_cap; '; end if;
  select count(*) into v_real_after from public.notifications where type = 'supplier_invite_nudge' and not public.fn_is_demo_email(to_email);
  if v_real_after <> v_real_before then fail := fail || 'a real address was queued; '; end if;
  -- real mode with the campaign closed is held and queues nothing
  if coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_enabled'), 'false') <> 'true'
     and (public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, false)->>'queued')::int <> 0 then
    fail := fail || 'real mode queued while the campaign is closed; '; end if;

  -- clean up and assert it is gone (the rollback below is the second guarantee)
  delete from public.notifications where lead_id = any(ids);
  delete from public.agent_actions where target_id like 'delivery.request:supplier_invite_nudge:%'
     and split_part(target_id, ':', 3)::bigint = any(ids);
  delete from public.email_suppressions where email = 'zz-demo-nudge-d@example.invalid';
  delete from public.leads where id = any(ids);
  if exists (select 1 from public.leads where id = any(ids)) or exists (select 1 from public.notifications where lead_id = any(ids)) then
    fail := fail || 'cleanup left rows; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'weekend', wk, 'run1', r1, 'run2', r2, 'run3', r3, 'run4', r4, 'run5_cap_day', r5, 'dawn_0401_and_evening_1800', jsonb_build_array(early, dawn2, night), 'steps', o)::text;
end $$;
