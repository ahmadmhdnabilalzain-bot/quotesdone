-- marketing, 24 Sep 2026, ledger 993: prove the supplier invitations land in the inbox and the domain
-- cannot get reported or blocked before the founder's go.
--
-- MEASURED (24 Sep 2026, production, read-only):
--   * fn_invite_ramp runs ONCE a day, before the batch, and reads 48 h of health. The hard brake in
--     enqueue_supplier_invites (invite_max_bounce_rate 5% over 3 days) also runs only at enqueue time.
--   * enqueue_supplier_invites spreads the day's batch over 09:00-17:00 Dubai with notifications.not_before.
--     So once the morning batch is queued, NOTHING stops it: a list segment bouncing at 15% at 10:00 keeps
--     sending until 17:00. History says it happens: 6 Aug 3/20 bounced (15%), 15 Aug 5/50 (10%).
--   * Gmail and Yahoo bulk-sender rules: spam rate under 0.3%, aim under 0.1%. At 30 a day ONE complaint is
--     3.3%, so a complaint has to stop the rest of that day's mail, not wait for tomorrow's ramp.
--
-- WHAT THIS ADDS: an AFTER UPDATE trigger on leads.invite_status. Every bounce or complaint recomputes the
-- Dubai day's rates. On a breach it (1) sets invite_enabled = false, (2) cancels every supplier_invite
-- still queued (send_outbox only sends status 'queued'), (3) opens it_watch_finding
-- 'deliverability:supplier_invite' so it_engineer owns it, (4) logs agent_runs. Resuming is a deliberate
-- act: invite_enabled goes back to true only by hand, after the finding is read.
--   Breach = complaints today >= same_day_pause_min_complaints (1) and rate >= pause_complaint_rate (0.3%)
--         OR bounces today >= same_day_pause_min_bounces (3) and rate >= same_day_pause_bounce_rate (5%).
-- A deliverability safety guard, not a budget cap. The founder's go (invite_enabled, supplier_outreach_golive)
-- is untouched unless the guard fires.
--
-- Prevented by: scripts/sql/an_invitation_bounce_or_complaint_spike_stops_the_campaign_the_same_hour_probe.sql

update public.app_secrets
   set value = (nullif(value,'')::jsonb || jsonb_build_object(
                  'same_day_pause_bounce_rate', 0.05, 'same_day_pause_min_bounces', 3,
                  'same_day_pause_min_complaints', 1))::text
 where key = 'invite_warmup'
   and not (nullif(value,'')::jsonb ? 'same_day_pause_bounce_rate');

create or replace function public.fn_invite_same_day_brake()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_br_max numeric := coalesce((c->>'same_day_pause_bounce_rate')::numeric, 0.05);
  v_b_min  int     := coalesce((c->>'same_day_pause_min_bounces')::int, 3);
  v_cr_max numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_c_min  int     := coalesce((c->>'same_day_pause_min_complaints')::int, 1);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_sent int; v_b int; v_c int; v_why text; v_cancelled int;
begin
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    return null;  -- already stopped; nothing more to stop
  end if;

  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_sent, v_b, v_c
    from leads
   where invited_at is not null and (invited_at at time zone 'Asia/Dubai')::date = v_day;

  if v_c >= v_c_min and v_c::numeric / greatest(v_sent, 1) >= v_cr_max then
    v_why := v_c || ' spam complaint(s) on ' || v_sent || ' invitation(s) today';
  elsif v_b >= v_b_min and v_b::numeric / greatest(v_sent, 1) >= v_br_max then
    v_why := v_b || ' bounce(s) on ' || v_sent || ' invitation(s) today (' || round(v_b * 100.0 / greatest(v_sent, 1), 1) || '%)';
  else
    return null;
  end if;

  update app_secrets set value = 'false' where key = 'invite_enabled';
  update notifications set status = 'cancelled'
   where type = 'supplier_invite' and status = 'queued';
  get diagnostics v_cancelled = row_count;

  insert into it_watch_finding(detector_key, detector, subject, state, severity, title, evidence)
  values ('deliverability:supplier_invite', 'deliverability', 'supplier_invite', 'paused', 'high',
          'Supplier invitations auto-paused: ' || v_why,
          jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c,
                             'cancelled_queued', v_cancelled, 'resume', 'set app_secrets.invite_enabled=true after reading the bounces/complaints'))
  on conflict (detector_key) do update
     set state = excluded.state, severity = excluded.severity, title = excluded.title, evidence = excluded.evidence,
         last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_same_day_brake', 'error',
          jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c, 'cancelled_queued', v_cancelled),
          'PAUSED: ' || v_why || '; invite_enabled=false, ' || v_cancelled || ' queued invitation(s) cancelled, it_engineer finding opened.', now());
  return null;
end
$fn$;

revoke execute on function public.fn_invite_same_day_brake() from public, anon, authenticated;

drop trigger if exists z80_invite_same_day_brake on public.leads;
create trigger z80_invite_same_day_brake
  after update of invite_status on public.leads
  for each row
  when (new.invite_status in ('bounced', 'complained') and old.invite_status is distinct from new.invite_status)
  execute function public.fn_invite_same_day_brake();
