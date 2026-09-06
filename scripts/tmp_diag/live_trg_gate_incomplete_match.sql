CREATE OR REPLACE FUNCTION public.trg_gate_incomplete_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ready boolean;
begin
  select rfq_ready into ready from public.inquiries where id = NEW.inquiry_id;
  if ready is not true then return null; end if;   -- silently skip: incomplete RFQs don't qualify for routing
  return NEW;
end $function$
