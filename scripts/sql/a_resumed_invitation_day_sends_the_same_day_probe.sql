-- PROBE for a_resumed_invitation_day_sends_the_same_day.sql. Seat: sales_engineer. Rolled back by its own raise; writes nothing.
-- 1. No supplier invitation the old stale rule held (held, no reason, never sent, reachable, class open) is left behind.
-- 2. A brake resumed after today's batch run reopens the batch: the tick no longer answers "already ran this Dubai day".
--    Its own batch-run row and resumed brake are inserted here; before 09:00 Dubai the tick does not run, so 2 is skipped.
do $probe$
declare v_left int; v_out jsonb; v_hour int := extract(hour from now() at time zone 'Asia/Dubai');
begin
  select count(*) into v_left
    from public.notifications n
    join public.leads l on l.id = n.lead_id
    left join public.email_domain_mx m on m.domain = split_part(lower(btrim(n.to_email)), '@', 2)
   where n.type = 'supplier_invite' and n.status = 'held' and n.last_error is null
     and n.sent_at is null and n.provider_message_id is null
     and public.fn_supplier_outreach_reachable(l, lower(btrim(n.to_email)))
     and public.fn_mail_provider_class(m.domain, m.hosts) = any(public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date));
  if v_left > 0 then
    raise exception 'PROBE FAILED: % supplier invitation(s) still held by the stale rule', v_left;
  end if;

  if v_hour < 9 then
    raise exception 'PROBE OK: 0 stale-held invitations left; the tick check is skipped before 09:00 Dubai';
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', 'ok', now() - interval '1 minute', now() - interval '1 minute',
          jsonb_build_object('job', 'supplier_outreach', 'batch_waiting', false), 'probe: a batch run earlier today');
  insert into public.invite_brake (source, why, fired_at, resumed_at, resume_note)
  values ('probe', 'probe: a brake resumed after the batch', now() - interval '2 minutes', now(), 'probe');
  v_out := public.fn_sales_engineer_supplier_outreach_tick(false);
  if v_out->>'reason' = 'already ran this Dubai day' then
    raise exception 'PROBE FAILED: a resume after the day''s batch did not reopen it: %', v_out;
  end if;
  raise exception 'PROBE OK: 0 stale-held invitations left; a resume reopened the batch: %', left(v_out::text, 300);
end
$probe$;
