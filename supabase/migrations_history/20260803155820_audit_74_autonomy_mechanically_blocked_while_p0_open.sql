-- AUDIT 7.4 — broad autonomy must actually be blocked while WI-001 is open.
--
-- WHAT THE AUDIT FOUND. spec_backlog id 201 (WI-001) is open, priority 0, notes "BLOCKS BROAD
-- PRODUCTION AUTONOMY" — and NOTHING READS IT. No CI check, no trigger, no code path. Meanwhile the
-- switch itself was on (agent_autonomy_enabled='true' from 30 Jul), cos_frozen='false' was the only
-- mechanical brake and it is a single unprotected app_secrets row, and widening authority needed
-- only one UPDATE org_authority or one new org_action_executor row — no approval object, no second
-- party. The declaration existed; the enforcement did not.
--
-- Note there is precedent for exactly this pattern already: backlog items 205 and 207 DO block,
-- via fn_kb_route_activation_blocked. 201 was the one left declarative.
--
-- WHAT THIS ADDS, in the order the audit raises them.
--
--   1. fn_autonomy_status()  — the missing reader. Any priority-0 spec_backlog row that is open
--      blocks autonomy, WI-001 included, and so do the kill switches. Fails CLOSED: if the check
--      itself raises, autonomy is blocked.
--   2. A trigger on org_tasks that refuses to move a task into in_progress at any non-advisory tier
--      while autonomy is blocked. This is the mechanical brake. Advisory work still runs, because
--      WI-001's own text permits shadow development.
--   3. A trigger on the four control keys in app_secrets. Widening (autonomy on, unfreeze, kill
--      switch off) requires a deliberate reason set on the SQL session; a PostgREST .update() from
--      an edge function cannot set a session GUC, so 190 service-role functions can no longer flip
--      it in passing. TIGHTENING IS ALWAYS ALLOWED — it must never be harder to stop the system
--      than to start it.
--   4. The same asymmetry on org_authority: raising a department's max_tier or its money threshold
--      needs the reason; lowering never does.
--   5. Every one of those changes writes an audit row, so "who widened autonomy and why" has an
--      answer that is not a guess.
--
-- Combined with the org_action_executor write constraint applied earlier today, both routes the
-- audit named for widening authority without a second party are now closed.

create table if not exists public.autonomy_control_audit (
  id           bigserial primary key,
  at           timestamptz not null default now(),
  object       text not null,          -- 'app_secrets:cos_frozen', 'org_authority:finance/money_move'
  op           text not null,          -- INSERT | UPDATE | DELETE
  direction    text not null,          -- 'widen' | 'tighten' | 'neutral'
  old_value    text,
  new_value    text,
  reason       text,
  db_user      text not null default current_user
);
alter table public.autonomy_control_audit enable row level security;
revoke all on public.autonomy_control_audit from anon, authenticated;
comment on table public.autonomy_control_audit is
  'Every change to an autonomy control: the kill switches and org_authority. Widening requires a '
  'reason on the session; tightening is always allowed and is recorded anyway.';

-- ---------------------------------------------------------------------------------------------
-- 1. The missing reader.
-- ---------------------------------------------------------------------------------------------
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
    v_blockers := v_blockers || ('spec_backlog#' || v_p0.id || ' open: ' || left(v_p0.item, 90));
  end loop;

  select value into v_enabled from public.app_secrets where key = 'agent_autonomy_enabled';
  select value into v_from    from public.app_secrets where key = 'agent_autonomy_from';
  select value into v_frozen  from public.app_secrets where key = 'cos_frozen';
  select value into v_kill    from public.app_secrets where key = 'ai_kill_switch';

  if coalesce(v_enabled, 'false') <> 'true' then
    v_blockers := v_blockers || 'agent_autonomy_enabled is not true';
  end if;
  if v_frozen = 'true' then
    v_blockers := v_blockers || 'cos_frozen is true';
  end if;
  if v_kill is not null and v_kill <> 'false' then
    v_blockers := v_blockers || 'ai_kill_switch is set';
  end if;
  begin
    if v_from is not null and v_from::date > current_date then
      v_blockers := v_blockers || ('agent_autonomy_from is in the future: ' || v_from);
    end if;
  exception when others then
    v_blockers := v_blockers || ('agent_autonomy_from is unparseable: ' || coalesce(v_from, 'null'));
  end;

  return jsonb_build_object(
    'allowed',  cardinality(v_blockers) = 0,
    'blockers', to_jsonb(v_blockers),
    'checked_at', now()
  );
exception when others then
  -- FAIL CLOSED. A monitoring query that cannot answer must not read as permission.
  return jsonb_build_object(
    'allowed', false,
    'blockers', to_jsonb(array['autonomy status could not be determined: ' || sqlerrm]),
    'checked_at', now());
end $fn$;
revoke all on function public.fn_autonomy_status() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. The mechanical brake.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_autonomy_brake()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare v jsonb;
begin
  if new.status is distinct from 'in_progress' or old.status = 'in_progress' then
    return new;
  end if;
  if coalesce(new.tier, 'advisory') = 'advisory' then
    return new;   -- WI-001 permits shadow development; advice-only work is not broad autonomy
  end if;
  v := public.fn_autonomy_status();
  if (v ->> 'allowed')::boolean then
    return new;
  end if;
  raise exception
    'org_tasks: task % cannot start at tier %. Broad autonomy is blocked: %. This is WI-001 being '
    'enforced rather than merely declared — clear the blocker, or drop the task to advisory.',
    new.id, new.tier, (v ->> 'blockers')
    using errcode = 'check_violation';
end $fn$;
revoke all on function public.fn_org_task_autonomy_brake() from public, anon, authenticated;

drop trigger if exists trg_org_task_autonomy_brake on public.org_tasks;
create trigger trg_org_task_autonomy_brake
  before update of status on public.org_tasks
  for each row execute function public.fn_org_task_autonomy_brake();

-- ---------------------------------------------------------------------------------------------
-- 3. The control keys.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_autonomy_control_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_key    text := coalesce(new.key, old.key);
  v_old    text := old.value;
  v_new    text := new.value;
  v_reason text := nullif(trim(coalesce(current_setting('app.change_reason', true), '')), '');
  v_dir    text := 'neutral';
  v_widen  boolean := false;
begin
  if v_key not in ('agent_autonomy_enabled','agent_autonomy_from','cos_frozen','ai_kill_switch') then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    -- Deleting cos_frozen or ai_kill_switch removes a brake; deleting the enable flag adds one.
    v_widen := v_key in ('cos_frozen','ai_kill_switch');
  elsif v_key = 'agent_autonomy_enabled' then
    v_widen := v_new = 'true' and coalesce(v_old,'false') <> 'true';
  elsif v_key = 'cos_frozen' then
    v_widen := coalesce(v_new,'false') <> 'true' and v_old = 'true';
  elsif v_key = 'ai_kill_switch' then
    v_widen := coalesce(v_new,'false') = 'false' and coalesce(v_old,'false') <> 'false';
  elsif v_key = 'agent_autonomy_from' then
    v_widen := tg_op = 'INSERT' or v_new is distinct from v_old;   -- any move of the date is a widen
  end if;
  v_dir := case when v_widen then 'widen' else 'tighten' end;

  if v_widen and (v_reason is null or length(v_reason) < 12) then
    raise exception
      'app_secrets.%: widening autonomy needs a stated reason. Run '
      '`set local app.change_reason = ''why, in a sentence'';` in the same transaction. '
      'A PostgREST update from an edge function cannot set that, which is the point — this key '
      'was reachable by all 190 service-role functions. Tightening (freeze, kill switch, disable) '
      'never needs a reason and is never refused.', v_key
      using errcode = 'check_violation';
  end if;

  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  values ('app_secrets:' || v_key, tg_op, v_dir, v_old, v_new, v_reason);

  return coalesce(new, old);
end $fn$;
revoke all on function public.fn_autonomy_control_guard() from public, anon, authenticated;

drop trigger if exists trg_autonomy_control_guard on public.app_secrets;
create trigger trg_autonomy_control_guard
  before insert or update or delete on public.app_secrets
  for each row execute function public.fn_autonomy_control_guard();

-- ---------------------------------------------------------------------------------------------
-- 4. org_authority: raising needs a reason, lowering never does.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_authority_rank(p text)
returns int language sql immutable as $$
  -- How much UNSUPERVISED power the tier confers. advisory advises only; gated needs approval
  -- before acting; supervised acts and is reviewed after; autonomous acts unreviewed.
  select case p when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2
                when 'autonomous' then 3 else 3 end;   -- unknown tier ranks highest: fail closed
$$;

create or replace function public.fn_org_authority_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_reason text := nullif(trim(coalesce(current_setting('app.change_reason', true), '')), '');
  v_widen  boolean;
  v_obj    text := 'org_authority:' || coalesce(new.dept_key, old.dept_key) || '/'
                                    || coalesce(new.action_class, old.action_class);
begin
  if tg_op = 'DELETE' then
    v_widen := false;   -- removing a row removes a permission
  else
    v_widen := public.fn_authority_rank(new.max_tier) > public.fn_authority_rank(coalesce(old.max_tier, 'advisory'))
            or coalesce(new.threshold_aed, 0) > coalesce(old.threshold_aed, 0);
  end if;

  if v_widen and (v_reason is null or length(v_reason) < 12) then
    raise exception
      'org_authority %: raising a department''s tier or money threshold needs a stated reason. '
      'Run `set local app.change_reason = ''why, in a sentence'';` in the same transaction. '
      'Lowering never needs one.', v_obj
      using errcode = 'check_violation';
  end if;

  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  values (v_obj, tg_op,
          case when v_widen then 'widen' else 'tighten' end,
          coalesce(old.max_tier,'') || '/' || coalesce(old.threshold_aed::text,''),
          coalesce(new.max_tier,'') || '/' || coalesce(new.threshold_aed::text,''),
          v_reason);
  return coalesce(new, old);
end $fn$;
revoke all on function public.fn_org_authority_guard() from public, anon, authenticated;

drop trigger if exists trg_org_authority_guard on public.org_authority;
create trigger trg_org_authority_guard
  before insert or update or delete on public.org_authority
  for each row execute function public.fn_org_authority_guard();

-- ---------------------------------------------------------------------------------------------
-- 5. Operator view.
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_autonomy_status as
select (public.fn_autonomy_status() ->> 'allowed')::boolean as autonomy_allowed,
       public.fn_autonomy_status() -> 'blockers'            as blockers,
       (select count(*) from public.spec_backlog where priority = 0 and status = 'open') as p0_open,
       (select count(*) from public.autonomy_control_audit where direction = 'widen')    as widenings_ever,
       (select max(at)  from public.autonomy_control_audit where direction = 'widen')    as last_widening;
comment on view public.v_autonomy_status is
  'Whether broad autonomy is permitted right now and, if not, exactly what is blocking it. '
  'autonomy_allowed=false with p0_open>0 is WI-001 doing its job.';;
