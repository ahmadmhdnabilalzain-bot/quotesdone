CREATE OR REPLACE FUNCTION public.fn_phase_c_overlay_may_not_dispatch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kind text;
begin
  select kind into v_kind from public.fn_phase_c_resolve_actor(new.accountable_role_id);
  if v_kind = 'overlay' then
    raise exception 'phase_c_task: category overlay % may advise but may never own a task or hold dispatch authority. Invoke it with fn_phase_c_overlay_invoke and return its advice to a canonical owner.',
      new.accountable_role_id using errcode = '23514';
  end if;
  return new;
end $function$
