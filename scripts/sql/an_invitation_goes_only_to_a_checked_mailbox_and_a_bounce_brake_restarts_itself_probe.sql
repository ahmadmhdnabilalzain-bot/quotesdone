-- PROBE of an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself.sql. Always raises CHK<<...>>, so
-- every row rolls back and nothing reaches the sender. The invented addresses use a domain created inside this transaction.
do $probe$
declare
  v_id bigint; l public.leads; v_problems text[] := '{}'; v_before int; v_after int; v_r jsonb; v_day date := (now() at time zone 'UTC')::date;
  v_dom text := 'qd-probe-' || md5(random()::text) || '.ae'; v_nid bigint; v_refused boolean := false;
  v_was timestamptz;
  v_body text := (select replace(value, '{{link}}', 'x') from public.app_secrets where key = 'invite_body');
begin
  insert into public.email_domain_mx(domain, has_mx, kind, hosts) values (v_dom, true, 'mx', array['mx.' || v_dom]);
  insert into public.leads(company_name, email) values ('Probe Trading ' || v_dom, 'sales@' || v_dom) returning id into v_id;
  select * into l from public.leads where id = v_id;

  -- known-bad control: a lead with every old qualification and no verdict is not eligible, and the outbox refuses it
  if public.fn_supplier_invite_eligible(l) then v_problems := v_problems || 'an unchecked lead is eligible'::text; end if;
  begin
    insert into public.notifications(type, to_email, to_role, lead_id, subject, body, lang, status)
    values ('supplier_invite', 'sales@' || v_dom, 'supplier', v_id, 's', replace(v_body, '{{company}}', 'Probe'), 'en', 'queued');
  exception when check_violation then v_refused := true; end;
  if not v_refused then v_problems := v_problems || 'the outbox took an unverified lead'::text; end if;

  perform public.fn_sales_engineer_records_email_checks(
    jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', 'sales@' || v_dom, 'verdict', 'verified', 'reason', 'probe', 'mailbox', 'role', 'mx_kind', 'mx')), '[]'::jsonb);
  if not public.fn_supplier_invite_eligible(l) then v_problems := v_problems || 'a verified lead is not eligible'::text; end if;
  if not exists (select 1 from public.fn_supplier_invite_eligible_ids() e(id) where e.id = v_id) then v_problems := v_problems || 'a verified lead is not in the eligible set'::text; end if;

  -- a changed address loses its verdict
  l.email := 'other@' || v_dom;
  if public.fn_supplier_invite_eligible(l) then v_problems := v_problems || 'a verdict survived a changed address'::text; end if;
  select * into l from public.leads where id = v_id;

  -- the batch reads a due lead and not a checked one
  if exists (select 1 from jsonb_array_elements(public.fn_sales_engineer_email_check_batch(100000)) x where (x->>'lead_id')::bigint = v_id) then
    v_problems := v_problems || 'a freshly checked lead is still due'::text; end if;

  -- queueing changes neither count; only the send does
  select coalesce((select sent from public.invite_schedule where day = v_day), 0) into v_before;
  select h.sent into v_after from public.fn_invite_send_health('-infinity') h;
  insert into public.notifications(type, to_email, to_role, lead_id, subject, body, lang, status)
  values ('supplier_invite', 'sales@' || v_dom, 'supplier', v_id, 's', replace(v_body, '{{company}}', 'Probe'), 'en', 'queued') returning id into v_nid;
  update public.leads set invite_status = 'queued', invited_at = now() where id = v_id;
  if (select h.sent from public.fn_invite_send_health('-infinity') h) <> v_after then v_problems := v_problems || 'a queued invitation counted as sent'::text; end if;
  update public.notifications set status = 'sent', sent_at = now() where id = v_nid;
  if (select h.sent from public.fn_invite_send_health('-infinity') h) <> v_after + 1 then v_problems := v_problems || 'a real send was not counted'::text; end if;
  if (select sent from public.invite_schedule where day = v_day) <> v_before + 1 then v_problems := v_problems || 'invite_schedule did not count the send'::text; end if;
  if (select sum(sent) from public.v_invite_deliverability_daily) <> v_after + 1 then v_problems := v_problems || 'the deliverability view does not count real sends'::text; end if;

  -- ISOLATION (10 Nov 2026, it_engineer). This probe was written while invite_brake held no seat restart. On 7 Nov the seat
  -- really restarted brake 5 (invite_same_day_brake), so every fixture brake below read as a SECOND breach inside 30 days and
  -- the probe failed nine ways while the routine was right. The real rows are moved out of the 30-day window and out of the
  -- "restarted_by_seat" set for this transaction only; the closing raise rolls them back with everything else.
  update public.invite_brake set restarted_by_seat = false, fired_at = fired_at - interval '60 days',
         resumed_at = coalesce(resumed_at, now()) - interval '60 days';
  -- the restart: held for an unverified batch and a complaint, then resumes, suppresses, and never lifts the wrong pause
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  insert into public.invite_brake(source, why) values ('probe', 'probe');
  update public.leads set invite_status = 'complained' where id = v_id;
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'held' is distinct from 'a complaint in the last 3 days' then v_problems := v_problems || ('a complaint did not hold the restart: ' || v_r::text); end if;
  update public.leads set invite_status = 'bounced' where id = v_id;
  -- the next batch needs somebody verified: a second, uninvited lead on its own domain
  insert into public.email_domain_mx(domain, has_mx, kind, hosts) values ('b' || v_dom, true, 'mx', array['mx.b' || v_dom]);
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'held' is distinct from 'cooldown' then v_problems := v_problems || ('the cooldown did not hold the restart: ' || v_r::text); end if;
  if not exists (select 1 from public.email_suppressions where email = 'sales@' || v_dom) then v_problems := v_problems || 'the bounced address was not suppressed'::text; end if;
  update public.invite_brake set fired_at = now() - interval '4 days' where resumed_at is null;
  -- known-bad control: a window over the limit holds it (the limit moved, in this transaction only, so real rows stay untouched)
  update public.app_secrets set value = '0.0001' where key = 'invite_max_bounce_rate';
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'held' is distinct from 'the 3-day window is still over the limit' then v_problems := v_problems || ('a window over the limit did not hold: ' || v_r::text); end if;
  update public.app_secrets set value = '1' where key = 'invite_max_bounce_rate';
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'held' is distinct from 'no verified lead to send to yet' then v_problems := v_problems || ('an empty batch did not hold the restart: ' || v_r::text); end if;
  insert into public.leads(company_name, email) values ('Second Probe ' || v_dom, 'sales@b' || v_dom) returning id into v_id;
  perform public.fn_sales_engineer_records_email_checks(
    jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', 'sales@b' || v_dom, 'verdict', 'verified', 'reason', 'probe', 'mailbox', 'role', 'mx_kind', 'mx')), '[]'::jsonb);
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if coalesce((v_r->>'resumed')::boolean, false) is not true then v_problems := v_problems || ('the restart did not resume: ' || v_r::text); end if;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'true' then v_problems := v_problems || 'invite_enabled stayed off'::text; end if;
  -- the restart resets nothing: the bounce still counts, and the first batch is small
  if (select h.bounced from public.fn_invite_send_health(now() - interval '3 days') h) < 1 then v_problems := v_problems || 'a restart reset the bounce window'::text; end if;
  if public.fn_invite_restart_cap(50) <> 10 then v_problems := v_problems || 'the first batch after a restart is not small'::text; end if;
  if exists (select 1 from public.invite_brake where resumed_at is null) then v_problems := v_problems || 'the brake stayed open'::text; end if;
  -- known-bad control: a restart on a closed day. 25 hours on with nothing sent since, the limit still holds (a 24-hour clock lapsed here)
  -- now() is one instant in a transaction, and the window is strict: the first lead's send goes before the restart, as it really
  -- did, so the send below falls inside the window.
  update public.notifications set sent_at = now() - interval '1 hour'
   where type = 'supplier_invite' and to_email = 'sales@' || v_dom;
  update public.invite_brake set resumed_at = greatest(now() - interval '25 hours',
      (select max(n.sent_at) from public.notifications n where n.type = 'supplier_invite' and not public.fn_is_demo_email(n.to_email)))
   where restarted_by_seat;
  if public.fn_invite_restart_cap(50) <> 10 then v_problems := v_problems || 'the limit lapsed before anything was sent'::text; end if;
  -- the first send today keeps it; a send on an earlier day ends it
  insert into public.notifications(type, to_email, to_role, lead_id, subject, body, lang, status)
  values ('supplier_invite', 'sales@b' || v_dom, 'supplier', v_id, 's', replace(v_body, '{{company}}', 'Probe'), 'en', 'queued') returning id into v_nid;
  update public.leads set invite_status = 'sent', invited_at = now() where id = v_id;
  update public.notifications set status = 'sent', sent_at = now() where id = v_nid;
  if public.fn_invite_restart_cap(50) <> 10 then v_problems := v_problems || 'the limit ended on the first sending day'::text; end if;
  select resumed_at into v_was from public.invite_brake where restarted_by_seat;
  update public.notifications set sent_at = now() - interval '2 days' where id = v_nid;
  update public.invite_brake set resumed_at = now() - interval '2 days 1 hour' where restarted_by_seat;
  if public.fn_invite_restart_cap(50) <> 50 then v_problems := v_problems || 'the limit outlived the first sending day'::text; end if;
  update public.notifications set sent_at = now() where id = v_nid;
  update public.invite_brake set resumed_at = v_was where restarted_by_seat;
  -- healthy sends since the restart do not trip probation
  update public.app_secrets set value = '0.03' where key = 'invite_max_bounce_rate';
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'probation' is distinct from 'true' or (select value from public.app_secrets where key = 'invite_enabled') <> 'true' then
    v_problems := v_problems || ('healthy sends tripped probation: ' || v_r::text); end if;
  -- one bounce on the batch since the restart is under the 3-day brake's 15 sends and 5 bounces, and is still the second breach:
  -- it stays paused and opens one task for the CEO seat, however often the duty runs
  update public.leads set invite_status = 'bounced' where id = v_id;
  select count(*) into v_before from public.ceo_task;
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'held' is distinct from 'second breach: the CEO seat decides' then v_problems := v_problems || ('a second breach: ' || v_r::text); end if;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_problems := v_problems || 'a second breach resumed'::text; end if;
  if (select count(*) from public.ceo_task) <> v_before + 1 then v_problems := v_problems || 'a second breach did not open exactly one CEO task'::text; end if;

  -- the CEO resumes after that second breach: a new probation. Known-bad control: the old bounce re-paused here within 5 minutes
  select count(*) into v_before from public.ceo_task;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if v_r->>'probation' is distinct from 'true' or (v_r->>'bounced')::int <> 0 then v_problems := v_problems || ('a deliberate resume was charged old bounces: ' || v_r::text); end if;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'true' then v_problems := v_problems || 'a deliberate resume was paused again'::text; end if;
  if (select count(*) from public.ceo_task) <> v_before then v_problems := v_problems || 'a deliberate resume opened another CEO task'::text; end if;
  -- ... and a bounce on a send after it still counts
  update public.notifications set sent_at = now() + interval '1 second' where id = v_nid;
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_problems := v_problems || 'a bounce after the deliberate resume did not pause'::text; end if;
  if (select count(*) from public.ceo_task) <> v_before + 1 then v_problems := v_problems || 'a breach after the deliberate resume did not reach the CEO'::text; end if;

  -- paused: a supplier who already started still gets his reminder; a stranger's does not; suppression and a complaint still win
  insert into public.leads(company_name, email, claimed, claimed_by) values ('Started Probe ' || v_dom, 'owner@s' || v_dom, true, 'owner@s' || v_dom) returning id into v_id;
  if (select h.complained from public.fn_invite_send_health(now() - interval '30 days') h) = 0 then
    v_r := public.fn_sales_engineer_sends_registration_reminder(v_id, 'started', 1, now());
    if coalesce((v_r->>'ok')::boolean, false) is not true then v_problems := v_problems || ('a started supplier was held by the pause: ' || v_r::text); end if;
    v_r := public.fn_sales_engineer_sends_registration_reminder(v_id, 'clicked', 2, now());
    if coalesce((v_r->>'ok')::boolean, false) then v_problems := v_problems || 'a clicked lead was sent to during the pause'::text; end if;
    insert into public.email_suppressions(email, reason, source) values ('owner@s' || v_dom, 'hard_bounce:permanent', 'probe');
    v_r := public.fn_sales_engineer_sends_registration_reminder(v_id, 'started', 2, now());
    if coalesce((v_r->>'ok')::boolean, false) then v_problems := v_problems || 'a suppressed address got a reminder'::text; end if;
    delete from public.email_suppressions where email = 'owner@s' || v_dom;
    update public.leads set invite_status = 'complained' where id = (select lead_id from public.notifications where id = v_nid);
    if public.fn_supplier_reminder_is_open('started') then v_problems := v_problems || 'a complaint did not stop the reminder'::text; end if;
  end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_problems) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_problems));
end $probe$;
