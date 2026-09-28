-- PROBE (pure, no DDL, aborted transaction) for an_invited_supplier_who_never_opened_the_invitation_is_nudged_on_day_3_7_and_14.sql.
-- Run AFTER the definitions in the same transaction; it always ends in raise exception 'CHK<<json>>', so every row it
-- writes rolls back. Subjects: six ZZ DEMO leads at @example.invalid, created here. Fixture mode of the nudger can only
-- see leads carrying BOTH marks, and every nudge row this probe produced is asserted to be at @example.invalid.
do $$
declare
  p_now timestamptz := ((now() at time zone 'Asia/Dubai')::date + time '10:00') at time zone 'Asia/Dubai';
  a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; ids bigint[];
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; wk jsonb; fail text := ''; o jsonb;
  v_real_before int; v_real_after int;
begin
  if extract(isodow from p_now at time zone 'Asia/Dubai') in (6, 7) then
    p_now := p_now + interval '2 days';   -- the positive case needs a weekday; the used-today count follows p_now's date
  end if;
  select count(*) into v_real_before from public.notifications where type = 'supplier_invite_nudge' and not public.fn_is_demo_email(to_email);

  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge day 4',   'zz-demo-nudge-a@example.invalid', p_now - interval '4 days')  returning id into a;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge day 8',   'zz-demo-nudge-b@example.invalid', p_now - interval '8 days')  returning id into b;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge day 15',  'zz-demo-nudge-c@example.invalid', p_now - interval '15 days') returning id into c;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge suppressed', 'zz-demo-nudge-d@example.invalid', p_now - interval '4 days') returning id into d;
  insert into public.leads (company_name, email, invited_at, invite_clicked_at) values
    ('ZZ DEMO — nudge clicked', 'zz-demo-nudge-e@example.invalid', p_now - interval '4 days', p_now - interval '3 days') returning id into e;
  insert into public.leads (company_name, email, invited_at) values
    ('ZZ DEMO — nudge day 25',  'zz-demo-nudge-f@example.invalid', p_now - interval '25 days') returning id into f;
  ids := array[a, b, c, d, e, f];
  insert into public.email_suppressions (email, reason, source) values ('zz-demo-nudge-d@example.invalid', 'ZZ DEMO probe', 'probe');

  -- the invitation as the outbox records it (the anchor), dated per lead
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel)
  select 'supplier_invite', l.email, 'supplier', l.id, 'ZZ DEMO', 'ZZ DEMO https://quotesdone.com/en/portal?t=' || gen_random_uuid()::text, 'sent', l.invited_at, l.invited_at, 'email'
    from public.leads l where l.id = any(ids);
  update public.notifications set status = 'sent', sent_at = created_at where type = 'supplier_invite' and lead_id = any(ids);

  -- weekend: held, nothing queued
  wk := public.fn_sales_engineer_nudges_invited_suppliers(p_now + ((6 - extract(isodow from p_now at time zone 'Asia/Dubai'))::int * interval '1 day'), 10, true);
  if wk->>'held' is distinct from 'UAE weekend' then fail := fail || 'weekend not held: ' || wk::text || '; '; end if;

  -- cap 2 with 3 due -> 2; again at cap 2 -> 0 (the cap is shared per day); cap 10 -> the 1 left; again -> 0 (idempotent)
  r1 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 2, true);
  r2 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 2, true);
  r3 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);
  r4 := public.fn_sales_engineer_nudges_invited_suppliers(p_now, 10, true);

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
    'weekend', wk, 'run1', r1, 'run2', r2, 'run3', r3, 'run4', r4, 'steps', o)::text;
end $$;
