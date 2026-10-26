-- A QUOTATION'S SUPPLIER NEVER CHANGES.
--
-- The supplier on a quotation is the identity the buyer is being priced by. Moving it after the
-- fact would re-attribute a price to a company that never quoted it, so the trigger refuses the
-- change rather than recording who made it.
--
-- This file carries the definition that is deployed on production, taken from pg_get_functiondef.
-- It is a repository reorganisation: the routine was written inside a file whose name belonged to a
-- programme that no longer exists, and the routine outlived it. Nothing about the behaviour changes.

CREATE OR REPLACE FUNCTION public.fn_quote_supplier_is_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.supplier_id is not distinct from OLD.supplier_id then return NEW; end if;
  raise exception 'quotes %: this quotation belongs to supplier % and the write names supplier %. A quotation does not change hands; a correction is a new revision by its own author. (pd_object_cross_owner_write)',
    OLD.id, OLD.supplier_id, coalesce(NEW.supplier_id::text,'(none)') using errcode = '23514';
end $function$;
