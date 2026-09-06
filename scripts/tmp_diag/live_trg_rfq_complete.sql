CREATE OR REPLACE FUNCTION public.trg_rfq_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c jsonb;
begin
  c := public.fn_rfq_score(NEW);
  NEW.completeness := c; NEW.rfq_ready := (c->>'ready')::boolean;
  return NEW;
end $function$
