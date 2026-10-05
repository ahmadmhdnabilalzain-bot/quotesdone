-- PROBE (pure, no DDL, aborted transaction) for
-- an_unopened_supplier_invitation_is_nudged_on_day_3_7_and_14_under_the_same_switch_cap_and_brakes.sql.
-- Run AFTER the definitions, in the same transaction. It always ends in raise exception 'CHK<<json>>', so every row it
-- writes (and the go switch it turns on) rolls back. Subjects: ZZ DEMO leads at @example.invalid, created here; the
-- nudger's fixture mode can only see leads carrying BOTH marks, and every nudge row is asserted to be at @example.invalid.
do $$
declare
  -- 06:00 UTC = 10:00 Dubai, inside the window, on a weekday (moved forward if today is a UAE weekend day)
  p_now timestamptz := ((now() at time zone 'UTC')::date + time '06:00') at time zone 'UTC';
  a bigint; b bigint; c bigint; d bigint; e bigint; u bigint; r bigint; ids bigint[];
  v_off jsonb; v_wk jsonb; v_night jsonb; v_dawn jsonb; v1 jsonb; v1b jsonb; v7 jsonb; v7b jsonb; v14 jsonb; v14b jsonb; v21 jsonb;
  v_cap1 jsonb; v_real jsonb; fail text := ''; v_steps text; v_real_before int;
  v_en text; v_go text; v_warm text;
  v_ar_name text := 'ZZ DEMO ' || U&'\0645\0648\0631\062F';   -- Arabic script, written as escapes
begin
  if extract(isodow from p_now at time zone 'Asia/Dubai') in (6, 7) then p_now := p_now + interval '2 days'; end if;
  select count(*) into v_real_before from public.notifications where type = 'supplier_invite_nudge' and not public.fn_is_demo_email(to_email);
  v_en := (select value from public.app_secrets where key = 'invite_enabled');
  v_go := (select value from public.app_secrets where key = 'supplier_outreach_golive');
  v_warm := (select value from public.app_secrets where key = 'invite_warmup');

  -- a: invited 4 days ago, never opened, Arabic locale (the nudge must still be English)
  insert into public.leads (company_name, email, invited_at, locale) values
    ('ZZ DEMO - nudge day 4', 'zz-demo-nudge-a@example.invalid', p_now - interval '4 days', 'ar') returning id into a;
  -- b: invited 4 days ago, Arabic-script name (greeting guard)
  insert into public.leads (company_name, email, invited_at) values
    (v_ar_name, 'zz-demo-nudge-b@example.invalid', p_now - interval '4 days') returning id into b;
  -- c: OPENED the invitation (clicked)
  insert into public.leads (company_name, email, invited_at, invite_clicked_at) values
    ('ZZ DEMO - nudge opened', 'zz-demo-nudge-c@example.invalid', p_now - interval '4 days', p_now - interval '3 days') returning id into c;
  -- d: bounced (suppressed address)
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO - nudge bounced', 'zz-demo-nudge-d@example.invalid', p_now - interval '4 days') returning id into d;
  insert into public.email_suppressions (email, reason, source) values ('zz-demo-nudge-d@example.invalid', 'ZZ DEMO probe', 'probe');
  -- e: registered
  insert into public.leads (company_name, email, invited_at, registration_submitted_at) values
    ('ZZ DEMO - nudge registered', 'zz-demo-nudge-e@example.invalid', p_now - interval '4 days', p_now - interval '1 day') returning id into e;
  -- u: unsubscribed
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - nudge unsubscribed', 'zz-demo-nudge-u@example.invalid', p_now - interval '4 days', 'unsubscribed') returning id into u;
  -- r: never had an invitation delivered (only the status column says so): never nudged
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO - nudge no outbox row', 'zz-demo-nudge-r@example.invalid', p_now - interval '4 days') returning id into r;
  ids := array[a, b, c, d, e, u, r];
  -- the anchor: the invitation as the outbox delivered it (all but r)
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  select 'supplier_invite', l.email, 'supplier', l.id, 'ZZ DEMO', 'ZZ DEMO https://quotesdone.com/en/portal?t=' || gen_random_uuid()::text, 'sent', l.invited_at, l.invited_at, 'email', 'en'
    from public.leads l where l.id = any(ids) and l.id <> r;
  update public.notifications set status = 'sent', sent_at = created_at where type = 'supplier_invite' and lead_id = any(ids);

  -- 1. THE GO SWITCH OFF (production's state): 0 queued, in fixture mode too, although two are due
  update public.app_secrets set value = 'false' where key in ('invite_enabled', 'supplier_outreach_golive');
  v_off := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);
  if (v_off->>'queued')::int <> 0 or v_off->>'held' not like 'the supplier campaign is not open%' or (v_off->>'due')::int <> 2 then
    fail := fail || 'switch off did not hold with 2 due: ' || v_off::text || '; '; end if;
  -- ... and in real mode
  if (public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, false)->>'queued')::int <> 0 then
    fail := fail || 'real mode queued with the switch off; '; end if;

  -- the switch ON, inside this rolled-back transaction only
  update public.app_secrets set value = 'true' where key in ('invite_enabled', 'supplier_outreach_golive');

  -- 2. weekend held; 18:00 Dubai held; 04:01 Dubai queued to wait for window_start_hour (9, set here)
  v_wk := public.fn_sales_engineer_nudges_invited_suppliers(p_now + ((6 - extract(isodow from p_now at time zone 'Asia/Dubai'))::int * interval '1 day'), 10, true);
  if v_wk->>'held' is distinct from 'UAE weekend' then fail := fail || 'weekend not held: ' || v_wk::text || '; '; end if;
  v_night := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '8 hours', 10, true);
  if v_night->>'held' is distinct from 'after the Dubai sending window' then fail := fail || '18:00 Dubai not held: ' || v_night::text || '; '; end if;
  update public.app_secrets set value = (coalesce(nullif(v_warm, '')::jsonb, '{}'::jsonb) || '{"window_start_hour": 9}')::text where key = 'invite_warmup';
  v_dawn := public.fn_sales_engineer_nudges_invited_suppliers(p_now - interval '5 hours 59 minutes', 1, true);
  if (v_dawn->>'queued')::int <> 1 or not exists (select 1 from public.notifications n where n.type = 'supplier_invite_nudge' and n.lead_id = any(ids)
       and n.not_before = ((p_now at time zone 'Asia/Dubai')::date + time '09:00') at time zone 'Asia/Dubai') then
    fail := fail || '04:01 Dubai did not queue a nudge waiting for 09:00: ' || v_dawn::text || '; '; end if;
  update public.app_secrets set value = v_warm where key = 'invite_warmup';
  delete from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids);
  delete from public.agent_actions where target_id like 'delivery.request:supplier_invite_nudge:%' and split_part(target_id, ':', 3)::bigint = any(ids);

  -- 3. THE CAP: cap 1 with 2 due queues 1; the next run the same day at cap 1 queues 0 (one cap per day)
  v_cap1 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 1, true);
  update public.notifications set created_at = p_now where type = 'supplier_invite_nudge' and lead_id = any(ids);
  if (v_cap1->>'queued')::int <> 1 or (public.fn_sales_engineer_nudges_invited_suppliers(p_now, 1, true)->>'queued')::int <> 0 then
    fail := fail || 'the daily cap is not shared: ' || v_cap1::text || '; '; end if;

  -- 4. DAY 3: the unopened ones are nudged once, in English; again the same day -> nothing
  v1 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);
  update public.notifications set created_at = p_now where type = 'supplier_invite_nudge' and lead_id = any(ids);
  v1b := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);
  -- 5. DAY 7 (+7 days, same weekday) and DAY 14 (+14): each fires once; DAY 21+ (+21): nothing, ever again
  v7  := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '7 days', 10, true);
  v7b := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '7 days', 10, true);
  v14 := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '14 days', 10, true);
  v14b := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '14 days', 10, true);
  v21 := public.fn_sales_engineer_nudges_invited_suppliers(p_now + interval '21 days', 10, true);
  if (v1->>'queued')::int <> 1 or (v1b->>'queued')::int <> 0 then fail := fail || 'day 3: ' || v1::text || ' then ' || v1b::text || '; '; end if;
  if (v7->>'queued')::int <> 2 or (v7b->>'queued')::int <> 0 then fail := fail || 'day 7: ' || v7::text || ' then ' || v7b::text || '; '; end if;
  if (v14->>'queued')::int <> 2 or (v14b->>'queued')::int <> 0 then fail := fail || 'day 14: ' || v14::text || ' then ' || v14b::text || '; '; end if;
  if (v21->>'queued')::int <> 0 or (v21->>'due')::int <> 0 then fail := fail || 'day 21+ fired: ' || v21::text || '; '; end if;

  select string_agg(split_part(x.target_id, ':', 3) || ':' || split_part(x.target_id, ':', 4), ',' order by x.target_id) into v_steps
    from public.agent_actions x where x.target_id like 'delivery.request:supplier_invite_nudge:%'
     and split_part(x.target_id, ':', 3)::bigint = any(ids);
  -- exactly steps 1, 2, 3 for a and for b; nobody else
  if v_steps is distinct from (a || ':1,' || a || ':2,' || a || ':3,' || b || ':1,' || b || ':2,' || b || ':3') then
    fail := fail || 'steps per lead: ' || coalesce(v_steps, 'none') || '; '; end if;
  if exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id in (c, d, e, u, r)) then
    fail := fail || 'an opened / bounced / registered / unsubscribed / never-delivered lead was nudged; '; end if;
  if exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids)
              and (lang is distinct from 'en' or body !~ '/en/portal' or body ~ '/ar/'
                   or coalesce(subject, '') || coalesce(body, '') ~ '[\u0600-\u06FF]')) then
    fail := fail || 'a nudge is not English; '; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = b and body like 'Dear Sir or Madam,%') then
    fail := fail || 'the Arabic-named lead was not greeted "Dear Sir or Madam"; '; end if;
  if exists (select 1 from public.notifications where type = 'supplier_invite_nudge' and lead_id = any(ids) and to_email not like '%@example.invalid') then
    fail := fail || 'a nudge left the fixture domain; '; end if;
  select count(*) into v_steps from public.notifications where type = 'supplier_invite_nudge' and not public.fn_is_demo_email(to_email);
  if v_steps::int <> v_real_before then fail := fail || 'a real address was queued; '; end if;
  -- real mode with the switch on: the fixtures are invisible to it, so 0
  v_real := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, false);
  if coalesce((v_real->>'queued')::int, 0) <> 0 then fail := fail || 'real mode queued a fixture: ' || v_real::text || '; '; end if;

  -- 6. THE BATCH (read back): one line changed, #1051's pool and #1106's rescue tier still behind it
  if pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure)
       !~ 'into v_used from notifications where type in \(''supplier_invite'', ''supplier_invite_nudge''\)' then
    fail := fail || 'enqueue_supplier_invites does not count nudges; '; end if;
  if pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure) !~ 'fn_supplier_invite_candidates\(v_remaining\)'
     or pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure) !~ 'fn_invite_placement_gate' then
    fail := fail || 'enqueue_supplier_invites lost its candidates call or placement gate; '; end if;
  if pg_get_functiondef('public.fn_supplier_invite_candidates(integer)'::regprocedure) !~ 'fn_supplier_invite_eligible_ids\(\)' then
    fail := fail || '#1051 pool (fn_supplier_invite_eligible_ids) missing from the candidates; '; end if;
  if pg_get_functiondef('public.fn_supplier_invite_candidates(integer)'::regprocedure) !~ 'stalled_inquiry_rescue' then
    fail := fail || '#1106 rescue tier missing from the candidates; '; end if;

  -- clean up and assert it is gone (the rollback is the second guarantee)
  update public.app_secrets set value = v_en where key = 'invite_enabled';
  update public.app_secrets set value = v_go where key = 'supplier_outreach_golive';
  delete from public.notifications where lead_id = any(ids);
  delete from public.agent_actions where target_id like 'delivery.request:supplier_invite_nudge:%' and split_part(target_id, ':', 3)::bigint = any(ids);
  delete from public.email_suppressions where email = 'zz-demo-nudge-d@example.invalid';
  delete from public.leads where id = any(ids);
  if exists (select 1 from public.leads where id = any(ids)) then fail := fail || 'cleanup left rows; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'switch_off', v_off, 'weekend', v_wk, 'evening', v_night, 'dawn', v_dawn, 'cap1', v_cap1,
    'day3', v1, 'day3_again', v1b, 'day7', v7, 'day7_again', v7b, 'day14', v14, 'day14_again', v14b, 'day21', v21,
    'real_mode', v_real)::text;
end $$;
