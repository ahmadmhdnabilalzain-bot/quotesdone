-- PROBE for the_whatsapp_reply_can_start_before_the_classification_ends.sql. Seat: customer_support. Never applied: it always raises
-- CHK<<...>> and rolls back. On the reserved ZZ DEMO fixture number +971500000031 (nothing here sends anything). PROBE OK only if
--   1. fn_wa_route_dry writes 0 wa_answer_log rows;
--   2. fn_wa_route (normal) still writes exactly 1;
--   3. both return the same deterministic reply and intent, and neither asks for a person (p_needs_person false, p_intent 'none');
--   4. the dry route is callable by service_role only (no anon / authenticated / public EXECUTE).
do $probe$
declare
  f text[] := '{}'; ph text := '+971500000031'; n0 int; n1 int; n2 int; d jsonb; r jsonb; open_to text;
begin
  select count(*) into n0 from public.wa_answer_log where from_phone = ph;
  d := public.fn_wa_route_dry(ph, 'ZZ DEMO probe: do you cover glass balustrades?', false, 'none');
  select count(*) into n1 from public.wa_answer_log where from_phone = ph;
  r := public.fn_wa_route(ph, 'ZZ DEMO probe: do you cover glass balustrades?', false, false, 'none');
  select count(*) into n2 from public.wa_answer_log where from_phone = ph;
  if d is null then f := f || 'the dry route returned nothing'; end if;
  if n1 <> n0 then f := f || format('the dry route wrote %s wa_answer_log rows', n1 - n0); end if;
  if n2 <> n1 + 1 then f := f || format('the normal route wrote %s rows, expected exactly 1', n2 - n1); end if;
  if d ->> 'deterministic_reply' is distinct from r ->> 'deterministic_reply' or d ->> 'deterministic_intent' is distinct from r ->> 'deterministic_intent' then f := f || 'the dry and normal routes answered differently'; end if;
  if (d ->> 'needs_a_person') is distinct from 'false' then f := f || 'the dry route asked for a person: ' || coalesce(d ->> 'needs_a_person', 'null'); end if;
  select string_agg(grantee, ',') into open_to from information_schema.routine_privileges
   where specific_schema = 'public' and routine_name = 'fn_wa_route_dry' and privilege_type = 'EXECUTE' and grantee in ('PUBLIC', 'anon', 'authenticated');
  if open_to is not null then f := f || 'fn_wa_route_dry is executable by ' || open_to; end if;
  raise exception 'CHK<<%>> dry rows % normal rows %', case when cardinality(f) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f, '; ') end, n1 - n0, n2 - n1;
end
$probe$;
