CREATE OR REPLACE FUNCTION public.a00_kernel_routine_ownership_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_d       jsonb;
  v_derived text;
begin
  v_d := public.fn_kernel_routine_ownership(
           NEW.schema_name || '.' || NEW.routine_name, NEW.identity_args, NEW.source_kind);
  v_derived := v_d->>'ownership_class';

  if v_derived is distinct from NEW.ownership_class then
    raise exception
      'kernel_routine_ownership refuses %.%(%): recorded class %, but the facts support %. Rule %. %',
      NEW.schema_name, NEW.routine_name, NEW.identity_args, NEW.ownership_class, v_derived,
      v_d->>'rule', v_d->>'evidence'
      using errcode = '23514';
  end if;

  if NEW.classified_by_rule is distinct from (v_d->>'rule') then
    raise exception
      'kernel_routine_ownership refuses %.%(%): recorded rule % is not the rule that fired (%). %',
      NEW.schema_name, NEW.routine_name, NEW.identity_args, NEW.classified_by_rule,
      v_d->>'rule', v_d->>'evidence'
      using errcode = '23514';
  end if;

  return null;
end
$function$
