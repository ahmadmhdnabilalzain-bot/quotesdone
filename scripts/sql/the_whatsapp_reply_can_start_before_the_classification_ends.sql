-- THE WHATSAPP REPLY CAN START BEFORE THE CLASSIFICATION ENDS: fn_wa_route_dry, the route that writes nothing.
-- Seat: customer_support (WhatsApp). 2 Nov 2026. Measured on the real exchange (wa-exchange-real run 41402449617): p50 23.0 s,
-- p95 41.9 s, and 11-14 s of every model turn is the classification, which the reply waited for. wa_inbound now asks the reply
-- beside the classification, on the commonest class (needs no person, no intent row fits: p_needs_person false, p_intent 'none'),
-- and uses that draft only when the classification says exactly that.
--
-- WHY A WRAPPER, NOT A NEW PARAMETER ON fn_wa_route. A sixth parameter is a new overload, so the five-argument calls already in
-- production would be ambiguous and the ACL of the old signature would not carry over. fn_wa_route itself is unchanged
-- (canonical: the_whatsapp_fallback_chain_names_the_founders_matrix_v2.sql). fn_wa_route calls fn_wa_answer, which inserts a
-- wa_answer_log row on every call ('none' files the question as BACKLOG); a speculative call must not file that. The wrapper
-- runs the real route inside a sub-transaction that always ends in an exception: every database write the route makes is
-- rolled back, and the local variable keeps the answer (PL/pgSQL does not restore variables on a caught exception). The result is
-- the route's own output, byte for byte, so the reply composed on it is the reply composed on the real route.
-- Prevented by: the_whatsapp_reply_can_start_before_the_classification_ends_probe.sql (dry writes 0 wa_answer_log rows, the normal
-- route still writes exactly 1, and both give the same answer).
create or replace function public.fn_wa_route_dry(p_phone text, p_body text, p_needs_person boolean default null, p_intent text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_out jsonb;
begin
  begin
    v_out := public.fn_wa_route(p_phone, p_body, false, p_needs_person, p_intent);
    raise exception 'qd_dry_route';
  exception when raise_exception then
    if sqlerrm is distinct from 'qd_dry_route' then raise; end if;
  end;
  return v_out;
end;
$function$;
revoke execute on function public.fn_wa_route_dry(text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.fn_wa_route_dry(text, text, boolean, text) to service_role;
comment on function public.fn_wa_route_dry(text, text, boolean, text) is
  'fn_wa_route for a TEXT message (no audio) with every write rolled back: the same answer, no wa_answer_log row. For a reply started before the classification returns (wa_inbound). scripts/sql/the_whatsapp_reply_can_start_before_the_classification_ends.sql';
