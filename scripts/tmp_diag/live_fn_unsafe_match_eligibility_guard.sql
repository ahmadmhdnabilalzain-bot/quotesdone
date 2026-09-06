CREATE OR REPLACE FUNCTION public.fn_unsafe_match_eligibility_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare l record; v_reason text;
begin
  select id, company_name, banned, matching_blocked, permanently_closed, license_expiry
    into l from public.leads where id = new.supplier_id;
  if l.id is null then return new; end if;

  v_reason := case
    when coalesce(l.banned,false)             then 'supplier is banned'
    when coalesce(l.matching_blocked,false)   then 'supplier is blocked from matching'
    when coalesce(l.permanently_closed,false) then 'supplier is permanently closed'
    when l.license_expiry is not null and l.license_expiry < current_date
                                              then 'supplier licence expired ' || l.license_expiry
    else null end;
  if v_reason is null then return new; end if;

  perform public.fn_unsafe_block(
    'ineligible_supplier_match', 'trigger:a00_unsafe_match_eligibility',
    'inquiry_matches', coalesce(new.inquiry_id::text,'') || '/' || new.supplier_id::text,
    'insert match row',
    jsonb_build_object('supplier_id', new.supplier_id, 'company', l.company_name,
                       'inquiry_id', new.inquiry_id, 'reason', v_reason));
  raise warning 'unsafe_block: refused match of inquiry % to supplier % — %',
        new.inquiry_id, new.supplier_id, v_reason;
  return null;   -- row not inserted; the ledger row survives
end $function$
