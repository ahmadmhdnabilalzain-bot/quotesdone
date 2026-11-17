-- PROBE for three_hand_over_kinds_made_after_the_pool_have_an_owner_and_an_audience.sql. Seat: it_engineer. Never applied: it
-- writes nothing and always raises CHK<<...>>. Run after the file. Asserts, for each of the sixteen echo types: exactly one
-- owner row, the owner is the kind's from_seat in seat_handoff_kind, and a failed echo also reaches it_engineer.
do $probe$
declare v_bad text := ''; k record; st text; n int;
begin
  for k in select distinct type, from_seat from public.seat_handoff_kind where type in ('partnership.proposed', 'supplier.reply_overdue', 'comparison.points', 'mail.routed') loop
    foreach st in array array['sent', 'waiting', 'done', 'failed'] loop
      select count(*) into n from public.event_subscription where event_type = 'handoff.' || k.type || '.' || st and owns;
      if n <> 1 then v_bad := v_bad || ' owners(' || k.type || '.' || st || ')=' || n; end if;
      if not exists (select 1 from public.event_subscription where event_type = 'handoff.' || k.type || '.' || st and owns and agent_key = k.from_seat) then
        v_bad := v_bad || ' owner-not-sender:' || k.type || '.' || st; end if;
    end loop;
    if not exists (select 1 from public.event_subscription where event_type = 'handoff.' || k.type || '.failed' and agent_key = 'it_engineer') then
      v_bad := v_bad || ' no-it-on-failed:' || k.type; end if;
  end loop;
  if (select count(distinct type) from public.seat_handoff_kind where type in ('partnership.proposed', 'supplier.reply_overdue', 'comparison.points', 'mail.routed')) <> 4 then
    v_bad := v_bad || ' kinds-missing'; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK 16 echo types, one owner each, the sender owns, IT watches the failed>>';
end $probe$;
