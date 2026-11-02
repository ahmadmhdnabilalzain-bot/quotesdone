-- PROBE for a_resumed_invitation_day_sends_the_same_day.sql. Seat: sales_engineer. Rolled back by its own raise; writes nothing
-- that survives. Every change it makes (app_secrets, leads, agent_runs, invite_brake) is inside this block.
-- 1. The release obeys the go switch: invite_enabled false releases nothing.
-- 2. The release obeys the bounce brake: with the real 3-day window, if it is over the limit, nothing is released.
-- 3. With the window under the limit (the window's bounced leads read 'sent' inside this block), it releases at most the
--    18 named ids, never another held row (every other held invitation is counted before and after).
-- 4. A brake resumed after today's batch run reopens the batch (skipped before 09:00 Dubai, when the tick does not run).
do $probe$
declare
  v_out jsonb; v_r jsonb; v_hs int; v_hb int; v_max numeric; v_over boolean; v_other bigint;
  v_held18 int; v_hour int := extract(hour from now() at time zone 'Asia/Dubai');
begin
  select count(*) into v_held18 from public.notifications where id between 116650 and 116668 and status = 'held' and last_error is null;
  -- every held invitation that is not one of the 18 (a kill-switch hold of old among them) must still be held afterwards
  select count(*) into v_other from public.notifications where type = 'supplier_invite' and status = 'held' and id not between 116650 and 116668;

  -- 1. the go switch
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  v_r := public.fn_sales_engineer_releases_the_invitations_held_stale_on_2_nov();
  if (v_r->>'released')::int <> 0 then raise exception 'PROBE FAILED: released with invite_enabled false: %', v_r; end if;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';

  -- 2. the brake, on the real window
  v_max := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
  select h.sent, h.bounced into v_hs, v_hb from public.fn_invite_send_health(now() - interval '3 days') h;
  v_over := (v_hs >= 15 and round(v_hb::numeric / greatest(v_hs, 1), 3) > v_max) or v_hb >= greatest(5, ceil(v_hs * v_max)::int);
  if v_over and public.fn_supplier_outreach_golive() then
    v_r := public.fn_sales_engineer_releases_the_invitations_held_stale_on_2_nov();
    if (v_r->>'released')::int <> 0 then raise exception 'PROBE FAILED: released over the bounce limit (% of %): %', v_hb, v_hs, v_r; end if;
  end if;

  -- 3. a clean window: only the named ids
  update public.leads l set invite_status = 'sent'
    from public.notifications n
   where n.lead_id = l.id and n.type = 'supplier_invite' and n.sent_at > now() - interval '3 days' and l.invite_status in ('bounced', 'complained');
  if public.fn_supplier_outreach_golive() then
    v_r := public.fn_sales_engineer_releases_the_invitations_held_stale_on_2_nov();
    if (v_r->>'released')::int <> v_held18 then raise exception 'PROBE FAILED: released % of the % still held: %', v_r->>'released', v_held18, v_r; end if;
    if (select count(*) from public.notifications where type = 'supplier_invite' and status = 'held' and id not between 116650 and 116668) <> v_other then
      raise exception 'PROBE FAILED: a held invitation outside the 18 was released';
    end if;
  end if;

  if v_hour < 9 then
    raise exception 'PROBE OK: go switch and brake hold the release, % of % released on a clean window, the other held row stayed held; tick skipped before 09:00', v_r->>'released', v_held18;
  end if;
  -- 4. the resume reopens the batch
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', 'ok', now() - interval '1 minute', now() - interval '1 minute',
          jsonb_build_object('job', 'supplier_outreach', 'batch_waiting', false), 'probe: a batch run earlier today');
  insert into public.invite_brake (source, why, fired_at, resumed_at, resume_note)
  values ('probe', 'probe: a brake resumed after the batch', now() - interval '2 minutes', now(), 'probe');
  v_out := public.fn_sales_engineer_supplier_outreach_tick(false);
  if v_out->>'reason' = 'already ran this Dubai day' then
    raise exception 'PROBE FAILED: a resume after the day''s batch did not reopen it: %', v_out;
  end if;
  raise exception 'PROBE OK: go switch and brake hold the release, % of % released on a clean window, the other held row stayed held; a resume reopened the batch: %',
    v_r->>'released', v_held18, left(v_out::text, 300);
end
$probe$;
