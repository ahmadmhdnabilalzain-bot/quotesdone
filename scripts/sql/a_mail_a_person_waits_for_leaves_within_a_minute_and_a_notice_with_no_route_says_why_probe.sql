-- PROBE (rolled back, never applied) for a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql
-- (it_engineer, 12 Nov 2026). A pure probe: it always raises, so every change it makes, and any pg_net request the kick
-- queues, roll back; nothing is sent and nothing stays cancelled.
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql \
--        scripts/sql/a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why_probe.sql
-- A ZZ DEMO notice cannot stand in for the case: zzzz_notifications_demo_capture turns every demo row to suppressed or
-- held on insert and update (measured 12 Nov 2026), and the sweep only reads queued rows. So the probe works on what
-- production holds, inside the rollback: every queued WhatsApp row over 24 h whose e-mail twin was delivered (on 12 Nov:
-- 139628 and 139631) must come out cancelled with the twin named, nothing else may change, and the IT engineer must hold
-- a finding for its type. The kick must count exactly the mails a person is waiting for.
do $probe$
declare v_cand bigint[]; v_other_before text; v_other_after text; v_s jsonb; v_k jsonb; v_wait int; v_bad int;
begin
  select coalesce(array_agg(w.id order by w.id), '{}') into v_cand from public.notifications w
   where w.status = 'queued' and w.channel = 'whatsapp' and w.created_at < now() - interval '24 hours'
     and (w.not_before is null or w.not_before < now())
     and exists (select 1 from public.notifications e where e.channel = 'email' and e.type = w.type and e.provider_status in ('delivered', 'read')
                   and e.created_at between w.created_at - interval '10 seconds' and w.created_at + interval '10 seconds'
                   and e.lead_id is not distinct from w.lead_id and e.inquiry_id is not distinct from w.inquiry_id and e.quote_id is not distinct from w.quote_id);
  select md5(string_agg(id || ':' || status, ',' order by id)) into v_other_before from public.notifications
   where created_at > now() - interval '72 hours' and not (id = any (v_cand));
  v_s := public.fn_notice_without_a_route_sweep();
  select count(*) into v_bad from public.notifications where id = any (v_cand)
     and (status <> 'cancelled' or last_error not like '%the e-mail twin % was delivered, so this copy is cancelled');
  select md5(string_agg(id || ':' || status, ',' order by id)) into v_other_after from public.notifications
   where created_at > now() - interval '72 hours' and not (id = any (v_cand));
  if v_bad > 0 then raise exception 'PROBE FAILED: % of % WhatsApp copies of delivered e-mails were not cancelled with the reason: %', v_bad, cardinality(v_cand), v_s; end if;
  if v_other_before is distinct from v_other_after then raise exception 'PROBE FAILED: the sweep changed a recent notice that was not a candidate: %', v_s; end if;
  if cardinality(v_cand) > 0 and not exists (select 1 from public.it_engineer_finding f
       where f.issue_key like 'duty:notice_without_a_route:whatsapp:%' and f.closed_at is null) then
    raise exception 'PROBE FAILED: the IT engineer was not told: %', v_s;
  end if;
  select count(*) into v_wait from public.notifications where status = 'queued' and channel = 'email'
     and to_role in ('supplier', 'customer') and not_before is null and created_at > now() - interval '15 minutes';
  v_k := public.fn_outbox_person_mail_kick();
  if coalesce((v_k->>'kicked')::boolean, false) <> (v_wait > 0) then raise exception 'PROBE FAILED: % waiting mail(s) but kick %', v_wait, v_k; end if;
  raise exception 'PROBE OK: % copy(ies) cancelled with the twin named (%), nothing else changed; kick % for % waiting', cardinality(v_cand), v_cand, v_k, v_wait;
end
$probe$;
