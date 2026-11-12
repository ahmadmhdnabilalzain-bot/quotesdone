-- PROBE (rolled back, never applied) for a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql
-- (it_engineer, 12 Nov 2026). A pure probe: it always raises, so every row it writes, every claim, the finding and the
-- pg_net request the kick queues roll back. pg_net and send_outbox read only committed rows, so nothing is ever sent.
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql \
--        scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why_probe.sql
-- A ZZ DEMO recipient cannot stand in: zzzz_notifications_demo_capture turns a demo row to suppressed on insert (measured
-- 12 Nov 2026). So the queued rows are addressed to the company's own domain (it-route-probe@quotesdone.com), never a
-- person, and exist only inside this transaction.
-- Proves: (1) a queued seed batch alone does not kick; (2) a registration mail beside it does, naming only the allow-list;
-- (3) the kinds claim takes the registration mail and none of the seed batch; (4) a WhatsApp row held 25 h and an e-mail
-- queued 73 h each become the IT engineer's finding with their recipient, and no notification changes status.
do $probe$
declare v_to text := 'it-route-probe@quotesdone.com'; v_s1 bigint; v_s2 bigint; v_reg bigint; v_held bigint; v_old bigint;
        v_k0 jsonb; v_k1 jsonb; v_real int; v_claimed bigint[]; v_body text; v_sw jsonb; v_st text;
begin
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, sender)
  values ('invite_m365_seed', 'invite_m365_seed', v_to, 'supplier', 'probe seed 1', 'probe', 'queued', 'email', 'customer_support') returning id into v_s1;
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, sender)
  values ('invite_m365_seed', 'invite_m365_seed', v_to, 'supplier', 'probe seed 2', 'probe', 'queued', 'email', 'customer_support') returning id into v_s2;
  if (select count(*) from public.notifications where id in (v_s1, v_s2) and status = 'queued') <> 2 then
    raise exception 'PROBE FAILED: the seed fixture rows did not stay queued (%)', (select jsonb_agg(status) from public.notifications where id in (v_s1, v_s2));
  end if;
  select count(*) into v_real from public.notifications where status = 'queued' and (channel is null or channel not in ('sms', 'whatsapp'))
     and coalesce(kind, type) = any (public.fn_outbox_person_kinds()) and not_before is null and created_at > now() - interval '15 minutes';
  v_k0 := public.fn_outbox_person_mail_kick();
  if coalesce((v_k0->>'kicked')::boolean, false) <> (v_real > 0) then raise exception 'PROBE FAILED: (1) a seed batch kicked: %', v_k0; end if;

  insert into public.notifications (type, to_email, to_role, subject, body, status, channel, sender)
  values ('registration_received', v_to, 'supplier', 'probe registration', 'probe', 'queued', 'email', 'customer_support') returning id into v_reg;
  v_k1 := public.fn_outbox_person_mail_kick();
  select convert_from(body, 'utf8') into v_body from net.http_request_queue where id = (v_k1->>'request')::bigint;
  if not coalesce((v_k1->>'kicked')::boolean, false) or v_body not like '%registration_received%' or v_body like '%invite%' then
    raise exception 'PROBE FAILED: (2) the registration mail did not kick with the allow-list only: % / %', v_k1, left(v_body, 300);
  end if;

  select array_agg(id) into v_claimed from public.fn_notifications_claim_kinds(public.fn_outbox_person_kinds(), 50);
  if not (v_reg = any (coalesce(v_claimed, '{}'))) or v_s1 = any (coalesce(v_claimed, '{}')) or v_s2 = any (coalesce(v_claimed, '{}'))
     or (select count(*) from public.notifications where id in (v_s1, v_s2) and status = 'queued') <> 2 then
    raise exception 'PROBE FAILED: (3) the kinds claim took % (registration %, seeds %, %)', v_claimed, v_reg, v_s1, v_s2;
  end if;

  insert into public.notifications (type, to_phone, to_role, lead_id, subject, body, status, channel, created_at, sender)
  values ('zz_probe_route_kind', '+971500000093', 'supplier', null, 'probe', 'probe', 'held', 'whatsapp', now() - interval '25 hours', 'customer_support')
  returning id into v_held;
  update public.notifications set status = 'held', last_error = 'held: template supplier_account_notice is missing (Twilio 404)' where id = v_held;
  insert into public.notifications (type, to_email, to_role, subject, body, status, channel, created_at, sender)
  values ('zz_probe_route_kind', v_to, 'customer', 'probe old', 'probe', 'queued', 'email', now() - interval '73 hours', 'customer_support')
  returning id into v_old;
  select status into v_st from public.notifications where id = v_old;
  v_sw := public.fn_notice_without_a_route_sweep();
  if not exists (select 1 from public.it_engineer_finding where closed_at is null
                   and issue_key = 'duty:notice_without_a_route:whatsapp:zz_probe_route_kind:held'
                   and evidence->'rows' @> jsonb_build_array(jsonb_build_object('id', v_held, 'to_role', 'supplier'))) then
    raise exception 'PROBE FAILED: (4) the held WhatsApp row is not the IT engineer''s finding with its recipient: %', v_sw;
  end if;
  if v_st = 'queued' and not exists (select 1 from public.it_engineer_finding where closed_at is null
                   and issue_key = 'duty:notice_without_a_route:email:zz_probe_route_kind:queued'
                   and evidence->'rows' @> jsonb_build_array(jsonb_build_object('id', v_old, 'to_role', 'customer'))) then
    raise exception 'PROBE FAILED: (4) the e-mail queued 73 h is not the IT engineer''s finding: %', v_sw;
  end if;
  if (select status from public.notifications where id = v_held) <> 'held' or (select status from public.notifications where id = v_old) <> v_st then
    raise exception 'PROBE FAILED: (4) the sweep changed a notification';
  end if;
  raise exception 'PROBE OK: seeds alone kick %, registration kick %, claim took %, sweep % (73 h row stayed %)',
    v_k0->>'kicked', v_k1->>'kicked', v_claimed, v_sw->'items', v_st;
end
$probe$;
