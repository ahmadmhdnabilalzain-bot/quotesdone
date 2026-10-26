-- Part 2 of "the licence arrived and nothing read it": resolving the sender to a lead ROW.
--
-- fn_wa_context already scopes a supplier to their own record and deliberately returns no primary
-- key — everything it returns is destined for a model prompt, and an internal id in a prompt is
-- one more thing that can be echoed back at us. The document path needs the opposite: the id and
-- nothing else, for code, never for a prompt.
--
-- The phone normalisation is the same expression fn_wa_context uses (strip to digits, match
-- phone_e164 / phone / whatsapp, prefer a claimed row) so a supplier who is found by the chat path
-- is found by the document path and vice versa. Two different normalisations would mean a supplier
-- whose licence updates a record the assistant then cannot see.
create or replace function public.fn_wa_lead_id(p_phone text)
 returns bigint
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select l.id
    from public.leads l
   where regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g') <> ''
     and (regexp_replace(coalesce(l.phone_e164, l.phone, ''), '[^0-9]', '', 'g')
            = regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')
       or regexp_replace(coalesce(l.whatsapp,''), '[^0-9]', '', 'g')
            = regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'))
   order by coalesce(l.claimed,false) desc, l.id
   limit 1;
$function$;

-- New SECURITY DEFINER function: EXECUTE is granted to PUBLIC on creation. Revoked here, and this
-- file goes out with --promote --ddl so the REVOKE reaches production rather than staging alone.
revoke all on function public.fn_wa_lead_id(text) from public, anon, authenticated;
grant execute on function public.fn_wa_lead_id(text) to service_role;
