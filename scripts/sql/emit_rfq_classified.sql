-- Five trade specialists — spec_commercial, spec_construction, spec_fitout, spec_industrial,
-- spec_mep — subscribe to `rfq.classified` ("Picks up commercial services RFQs" and so on) and it
-- has NEVER been emitted. `rfq.created` is emitted, by trg_event_inquiry on insert, but nothing
-- emits the classification, so the event that carries the category — the only one that tells a
-- specialist whether the RFQ is theirs — does not exist.
--
-- `inquiries` holds zero rows today, so this fires for the first time on the first real buyer. That
-- is exactly when it matters: without it, the five specialists who should compete for the first RFQ
-- this company ever receives would not hear about it.
--
-- The transition test is in the body, not a WHEN clause: an INSERT trigger's WHEN cannot reference
-- OLD, and an inquiry can arrive already classified (trg_inquiry_enrich runs BEFORE INSERT and sets
-- the category, so the common path is an INSERT that is already classified).
create or replace function public.fn_emit_rfq_classified()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if coalesce(btrim(new.category),'') = '' then return null; end if;
  if tg_op = 'UPDATE' and coalesce(old.category,'') = coalesce(new.category,'') then return null; end if;
  perform fn_emit('rfq.classified', 'inquiry', new.id::text, 'route_inquiry',
    jsonb_build_object('category', new.category, 'trades', new.trades,
                       'rfq_ready', new.rfq_ready, 'status', new.status));
  return null;
end $$;
drop trigger if exists trg_emit_rfq_classified on public.inquiries;
create trigger trg_emit_rfq_classified after insert or update of category on public.inquiries
  for each row execute function public.fn_emit_rfq_classified();

-- SECURITY DEFINER, so the PUBLIC grant Postgres adds would otherwise raise
-- anon_security_definer_function_executable by one.
revoke execute on function public.fn_emit_rfq_classified() from public, anon, authenticated;
