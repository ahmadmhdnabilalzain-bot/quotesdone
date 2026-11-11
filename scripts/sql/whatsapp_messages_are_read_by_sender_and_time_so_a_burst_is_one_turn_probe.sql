-- whatsapp_messages_are_read_by_sender_and_time_so_a_burst_is_one_turn_probe.sql — a PURE probe: it always raises CHK<<...>>,
-- so everything it does rolls back. Assigned: it_engineer. It writes nothing to a real row: the only rows it touches are its
-- own, from a reserved fixture number (+971 50 000 00xx, never contacted: _shared/demo_identity.ts), counted before and after.
-- Run after the DDL file, or with it in one rolled-back transaction. Expect: CHK<<PROBE OK ...>>.
-- It proves the index and the claim the turn gate relies on: a conditional update on stage 'received' and burst unset wins
-- once, and a second claim of the same row wins nothing.
do $probe$
declare
  v_from text := 'whatsapp:+971500000099';
  v_real_before bigint := (select count(*) from public.wa_messages where wa_from <> v_from);
  v_id bigint; v_first int; v_second int;
begin
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'wa_messages_from_created_idx'
                 and indexdef like '%(wa_from, created_at)%') then
    raise exception 'CHK<<PROBE FAILED: wa_messages_from_created_idx is missing or not on (wa_from, created_at)>>';
  end if;
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, lang, escalated, sent, created_at, meta)
    values (v_from, 'whatsapp:+14155550100', 'ZZ DEMO burst probe', '', 'en', false, false, now(), jsonb_build_object('stage', 'received', 'media', 0))
    returning id into v_id;
  update public.wa_messages set meta = meta || jsonb_build_object('stage', 'merged', 'burst', 'merged')
   where id = v_id and meta->>'stage' = 'received' and meta->>'burst' is null;
  get diagnostics v_first = row_count;
  update public.wa_messages set meta = meta || jsonb_build_object('burst', 'lead')
   where id = v_id and meta->>'stage' = 'received' and meta->>'burst' is null;
  get diagnostics v_second = row_count;
  if (select count(*) from public.wa_messages where wa_from <> v_from) <> v_real_before then
    raise exception 'CHK<<PROBE FAILED: a real row changed>>';
  end if;
  if v_first <> 1 or v_second <> 0 then
    raise exception 'CHK<<PROBE FAILED: the first claim won % row(s), the second % (expected 1 and 0)>>', v_first, v_second;
  end if;
  raise exception 'CHK<<PROBE OK: the index is on (wa_from, created_at); a claim wins once and a second claim wins nothing>>';
end
$probe$;
