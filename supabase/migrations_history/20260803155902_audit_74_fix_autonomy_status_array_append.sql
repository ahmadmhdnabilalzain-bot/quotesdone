-- Fix: `text[] || text` is ambiguous in Postgres and tried to parse the message AS an array literal,
-- so fn_autonomy_status raised "malformed array literal" on every call and fell into its own
-- exception handler. The RESULT still read allowed=false, so the brake worked and the probe looked
-- like a pass — but the blockers list said only "could not be determined", i.e. the function could
-- never tell an operator WHY autonomy was blocked. Fail-closed hid a real defect; array_append fixes
-- it. Worth stating plainly: the outcome was right for the wrong reason.
create or replace function public.fn_autonomy_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_blockers text[] := '{}';
  v_p0       record;
  v_enabled  text;
  v_from     text;
  v_frozen   text;
  v_kill     text;
begin
  for v_p0 in
    select id, item from public.spec_backlog where priority = 0 and status = 'open' order by id
  loop
    v_blockers := array_append(v_blockers, 'spec_backlog#' || v_p0.id || ' open: ' || left(v_p0.item, 90));
  end loop;

  select value into v_enabled from public.app_secrets where key = 'agent_autonomy_enabled';
  select value into v_from    from public.app_secrets where key = 'agent_autonomy_from';
  select value into v_frozen  from public.app_secrets where key = 'cos_frozen';
  select value into v_kill    from public.app_secrets where key = 'ai_kill_switch';

  if coalesce(v_enabled, 'false') <> 'true' then
    v_blockers := array_append(v_blockers, 'agent_autonomy_enabled is not true');
  end if;
  if v_frozen = 'true' then
    v_blockers := array_append(v_blockers, 'cos_frozen is true');
  end if;
  if v_kill is not null and v_kill <> 'false' then
    v_blockers := array_append(v_blockers, 'ai_kill_switch is set');
  end if;
  begin
    if v_from is not null and v_from::date > current_date then
      v_blockers := array_append(v_blockers, 'agent_autonomy_from is in the future: ' || v_from);
    end if;
  exception when others then
    v_blockers := array_append(v_blockers, 'agent_autonomy_from is unparseable: ' || coalesce(v_from, 'null'));
  end;

  return jsonb_build_object(
    'allowed',    cardinality(v_blockers) = 0,
    'blockers',   to_jsonb(v_blockers),
    'checked_at', now());
exception when others then
  return jsonb_build_object(
    'allowed', false,
    'blockers', to_jsonb(array['autonomy status could not be determined: ' || sqlerrm]),
    'checked_at', now());
end $fn$;
revoke all on function public.fn_autonomy_status() from public, anon, authenticated;;
