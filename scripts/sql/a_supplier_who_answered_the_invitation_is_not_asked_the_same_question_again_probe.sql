-- PROBE (pure, no DDL, aborted transaction) for
-- a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again.sql.
-- Run AFTER the definition, in the same transaction (or after it is applied). It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. Its subjects are ZZ DEMO leads at @example.invalid,
-- created here, and it reads them only through the nudge list's fixture mode, which sees nothing else. No real lead is
-- read or written; the count of real leads on the list is taken before and after and must not move.
--
-- Five leads, each invited 4 days ago (a sent supplier_invite row, as the outbox records it), so each is due a day-3 nudge
-- unless it answered:
--   a  no reply                                   -> nudged (the control: the list still works)
--   b  replied "Yes" a day after the invitation    -> NOT nudged (the fix)
--   c  an out-of-office auto reply                 -> nudged (an automatic reply is not an answer)
--   d  a message from before the invitation        -> nudged (only an answer to THIS invitation counts)
--   e  replied as "Name <address>", lead_id unset  -> NOT nudged (matched on the From address, as the filer matches it)
do $$
declare
  v_now timestamptz := now();
  a bigint; b bigint; c bigint; d bigint; e bigint; ids bigint[];
  v_due bigint[]; v_real_before int; v_real_after int; fail text := '';
  v_body text := 'Hi ZZ DEMO team,' || chr(10) || chr(10) || 'Would your company like to receive requests when they come in?'
                 || chr(10) || chr(10) || 'If this isn''t relevant, reply "stop" and we won''t contact you again.';
begin
  select count(*) into v_real_before from public.fn_supplier_invite_nudges_due(v_now, false);

  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - answered probe a (no reply)',   'zz-demo-answered-a@example.invalid', v_now - interval '4 days', 'sent') returning id into a;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - answered probe b (said yes)',   'zz-demo-answered-b@example.invalid', v_now - interval '4 days', 'sent') returning id into b;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - answered probe c (auto reply)', 'zz-demo-answered-c@example.invalid', v_now - interval '4 days', 'sent') returning id into c;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - answered probe d (old mail)',   'zz-demo-answered-d@example.invalid', v_now - interval '4 days', 'sent') returning id into d;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - answered probe e (named From)', 'zz-demo-answered-e@example.invalid', v_now - interval '4 days', 'sent') returning id into e;
  ids := array[a, b, c, d, e];

  -- the invitation as the outbox delivered it, four days ago
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  select 'supplier_invite', l.email, 'supplier', l.id, 'A question about your work in the UAE', v_body, 'sent',
         v_now - interval '4 days', v_now - interval '4 days', 'email', 'en'
    from public.leads l where l.id = any(ids);

  -- b: the supplier answered a day later
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, needs_review, matched_existing, raw, created_at)
  values (b, 'zz-demo-answered-b@example.invalid', 'supplier@quotesdone.com', 'Re: A question about your work in the UAE',
          'Yes', true, true, '{}'::jsonb, v_now - interval '3 days');
  -- c: an out-of-office reply (fn_inbound_is_auto_reply: the subject and the auto_submitted header)
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, needs_review, matched_existing, raw, created_at)
  values (c, 'zz-demo-answered-c@example.invalid', 'supplier@quotesdone.com', 'Automatic reply: A question about your work in the UAE',
          'I am currently out of the office.', true, true, '{"auto_submitted": "auto-replied"}'::jsonb, v_now - interval '4 days' + interval '1 minute');
  -- d: a message from before this invitation was sent
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, needs_review, matched_existing, raw, created_at)
  values (d, 'zz-demo-answered-d@example.invalid', 'info@quotesdone.com', 'An older question', 'Do you sell tiles?',
          true, true, '{}'::jsonb, v_now - interval '10 days');
  -- e: answered with a display name, and the reader did not match it to the lead
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, needs_review, matched_existing, raw, created_at)
  values (null, 'ZZ DEMO Sales <ZZ-DEMO-Answered-E@example.invalid>', 'supplier@quotesdone.com', 'Re: A question about your work in the UAE',
          'How much does it cost?', true, false, '{}'::jsonb, v_now - interval '2 days');

  select coalesce(array_agg(x.lead_id order by x.lead_id), '{}') into v_due
    from public.fn_supplier_invite_nudges_due(v_now, true) x where x.lead_id = any(ids);

  if not (a = any(v_due)) then fail := fail || 'a (no reply) is not nudged: the list itself broke; '; end if;
  if b = any(v_due) then fail := fail || 'b (answered "Yes") is still asked again; '; end if;
  if not (c = any(v_due)) then fail := fail || 'c (out-of-office only) is not nudged: an automatic reply counted as an answer; '; end if;
  if not (d = any(v_due)) then fail := fail || 'd (a message older than the invitation) is not nudged; '; end if;
  if e = any(v_due) then fail := fail || 'e (answered as "Name <address>") is still asked again; '; end if;
  if exists (select 1 from public.fn_supplier_invite_nudges_due(v_now, true) x where x.lead_id = any(ids) and x.step <> 1) then
    fail := fail || 'a fixture is on a step other than day 3; '; end if;

  select count(*) into v_real_after from public.fn_supplier_invite_nudges_due(v_now, false);
  if v_real_after <> v_real_before then fail := fail || 'the real list moved (' || v_real_before || ' -> ' || v_real_after || '); '; end if;

  -- clean up and prove it (the rollback below is the second guarantee)
  delete from public.inbound_messages where lead_id = any(ids) or lower(from_email) like '%zz-demo-answered-%@example.invalid%';
  delete from public.notifications where lead_id = any(ids);
  delete from public.leads where id = any(ids);
  if exists (select 1 from public.leads where id = any(ids)) then fail := fail || 'cleanup left leads; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'due_fixtures', v_due, 'a', a, 'b', b, 'c', c, 'd', d, 'e', e,
    'real_due_before', v_real_before, 'real_due_after', v_real_after);
end $$;
