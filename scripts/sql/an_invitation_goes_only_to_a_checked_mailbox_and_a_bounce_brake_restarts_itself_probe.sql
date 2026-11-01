-- PROBE of an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself.sql. Always raises CHK<<...>>, so
-- every row rolls back and nothing reaches the sender. The invented addresses use a domain created inside this transaction.
do $probe$
declare
  v_id bigint; l public.leads; v_problems text[] := '{}'; v_before int; v_after int; v_r jsonb; v_day date := (now() at time zone 'UTC')::date;
  v_dom text := 'qd-probe-' || md5(random()::text) || '.ae'; v_nid bigint; v_refused boolean := false;
  v_body text := (select replace(value, '{{link}}', 'x') from public.app_secrets where key = 'invite_body');
begin
  insert into public.email_domain_mx(domain, has_mx, kind, hosts) values (v_dom, true, 'mx', array['mx.' || v_dom]);
  insert into public.leads(company_name, email) values ('Probe Trading ' || v_dom, 'sales@' || v_dom) returning id into v_id;
  select * into l from public.leads where id = v_id;

  -- known-bad control: a lead with every old qualification and no verdict is not eligible, and the outbox refuses it
  if public.fn_supplier_invite_eligible(l) then v_problems := v_problems || 'an unchecked lead is eligible'; end if;
  begin
    insert into public.notifications(type, to_email, to_role, lead_id, subject, body, lang, status)
    values ('supplier_invite', 'sales@' || v_dom, 'supplier', v_id, 's', replace(v_body, '{{company}}', 'Probe'), 'en', 'queued');
  exception when check_violation then v_refused := true; end;
  if not v_refused then v_problems := v_problems || 'the outbox took an unverified lead'; end if;

  perform public.fn_sales_engineer_records_email_checks(
    jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', 'sales@' || v_dom, 'verdict', 'verified', 'reason', 'probe', 'mailbox', 'role', 'mx_kind', 'mx')), '[]'::jsonb);
  if not public.fn_supplier_invite_eligible(l) then v_problems := v_problems || 'a verified lead is not eligible'; end if;
  if not exists (select 1 from public.fn_supplier_invite_eligible_ids() e(id) where e.id = v_id) then v_problems := v_problems || 'a verified lead is not in the eligible set'; end if;

  -- a changed address loses its verdict
  l.email := 'other@' || v_dom;
  if public.fn_supplier_invite_eligible(l) then v_problems := v_problems || 'a verdict survived a changed address'; end if;
  select * into l from public.leads where id = v_id;

  -- the batch reads a due lead and not a checked one
  if exists (select 1 from jsonb_array_elements(public.fn_sales_engineer_email_check_batch(100000)) x where (x->>'lead_id')::bigint = v_id) then
    v_problems := v_problems || 'a freshly checked lead is still due'; end if;

  -- queueing changes neither count; only the send does
  select coalesce((select sent from public.invite_schedule where day = v_day), 0) into v_before;
  select h.sent into v_after from public.fn_invite_send_health('-infinity') h;
  insert into public.notifications(type, to_email, to_role, lead_id, subject, body, lang, status)
  values ('supplier_invite', 'sales@' || v_dom, 'supplier', v_id, 's', replace(v_body, '{{company}}', 'Probe'), 'en', 'queued') returning id into v_nid;
  update public.leads set invite_status = 'queued', invited_at = now() where id = v_id;
  if (select h.sent from public.fn_invite_send_health('-infinity') h) <> v_after then v_problems := v_problems || 'a queued invitation counted as sent'; end if;
  update public.notifications set status = 'sent', sent_at = now() where id = v_nid;
  if (select h.sent from public.fn_invite_send_health('-infinity') h) <> v_after + 1 then v_problems := v_problems || 'a real send was not counted'; end if;
  if (select sent from public.invite_schedule where day = v_day) <> v_before + 1 then v_problems := v_problems || 'invite_schedule did not count the send'; end if;
  if (select sum(sent) from public.v_invite_deliverability_daily) <> v_after + 1 then v_problems := v_problems || 'the deliverability view does not count real sends'; end if;

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
  if v_r->>'held' is distinct from 'the next batch is not verified yet' then v_problems := v_problems || ('an empty batch did not hold the restart: ' || v_r::text); end if;
  if not exists (select 1 from public.email_suppressions where email = 'sales@' || v_dom) then v_problems := v_problems || 'the bounced address was not suppressed'; end if;
  insert into public.leads(company_name, email) values ('Second Probe ' || v_dom, 'sales@b' || v_dom) returning id into v_id;
  perform public.fn_sales_engineer_records_email_checks(
    jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', 'sales@b' || v_dom, 'verdict', 'verified', 'reason', 'probe', 'mailbox', 'role', 'mx_kind', 'mx')), '[]'::jsonb);
  v_r := public.fn_sales_engineer_restarts_invites_after_a_brake();
  if coalesce((v_r->>'resumed')::boolean, false) is not true then v_problems := v_problems || ('the restart did not resume: ' || v_r::text); end if;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'true' then v_problems := v_problems || 'invite_enabled stayed off'; end if;
  -- the restart re-scopes the brake: the bounce it just dealt with is not counted again
  if (select h.bounced from public.fn_invite_send_health(public.fn_invite_brake_since(now() - interval '3 days')) h) <> 0 then
    v_problems := v_problems || 'the brake still counts a bounce from before the restart'; end if;
  if exists (select 1 from public.invite_brake where resumed_at is null) then v_problems := v_problems || 'the brake stayed open'; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_problems) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_problems));
end $probe$;
