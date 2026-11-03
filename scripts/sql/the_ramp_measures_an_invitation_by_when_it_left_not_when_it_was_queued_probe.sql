-- PROBE for the_ramp_measures_an_invitation_by_when_it_left_not_when_it_was_queued.sql. Never applied: it always raises,
-- so the ramp's run row, any cap change and any alert it writes are rolled back. Must print PROBE OK. Seat: it_engineer.
-- It runs the routine and holds it to the outbox: the run is a restart exactly when no real invitation was SENT in the
-- last three days, and a restart's note names the last real send (on 3 Nov the old body named a queue time, 30 Oct 05:00Z).
do $$
declare v_last timestamptz; v_cap int; r record; v_expect boolean;
begin
  select max(n.sent_at) into v_last
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= public.fn_invite_lane_since()
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email);
  v_cap := public.fn_invite_ramp();
  select a.counts, a.note into r from public.agent_runs a where a.agent = 'invite_ramp' order by a.id desc limit 1;
  if coalesce((r.counts->>'paused')::boolean, false) then raise exception 'CHK<<PROBE OK (invite_enabled is false: the ramp measured nothing)>>'; end if;
  if r.note like 'PAUSED ON COMPLAINTS%' then raise exception 'CHK<<PROBE OK (complaint pause: no restart judged)>>'; end if;
  v_expect := v_last is null or v_last < now() - interval '3 days';
  if coalesce((r.counts->>'restart')::boolean, false) <> v_expect then
    raise exception 'CHK<<PROBE FAILED: restart=% but the last real send was %>>', r.counts->>'restart', v_last;
  end if;
  if v_expect and v_last is not null and position(to_char(v_last at time zone 'UTC', 'YYYY-MM-DD HH24:MI') in r.note) = 0 then
    raise exception 'CHK<<PROBE FAILED: the restart note does not name the last real send (%): %>>', v_last, r.note;
  end if;
  if has_function_privilege('anon', 'public.fn_invite_ramp()', 'execute') then raise exception 'CHK<<PROBE FAILED: anon may execute>>'; end if;
  raise exception 'CHK<<PROBE OK restart=% last_sent=% cap=%>>', v_expect, v_last, v_cap;
end $$;
