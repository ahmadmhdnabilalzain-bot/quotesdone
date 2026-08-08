-- undo_log existed with no writer: the rollback facility was decorative.
-- Capture before-state on the surface where the company changes ITSELF - governance,
-- knowledge, goals, targets, policy, flags. Deliberately NOT on high-traffic marketplace
-- tables (leads/quotes/inquiries): those need business-level reversal, not row restore,
-- and a trigger on 20k+ rows is a cost with no matching benefit.

create or replace function public.trg_undo_capture()
returns trigger
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_actor text;
begin
  v_actor := coalesce(
    nullif(current_setting('app.actor', true), ''),
    nullif(current_setting('request.jwt.claim.email', true), ''),
    session_user);

  if tg_op = 'DELETE' then
    insert into undo_log (table_name, row_id, op, before, actor)
    values (tg_table_name, (to_jsonb(old)->>(tg_argv[0])), 'DELETE', to_jsonb(old), v_actor);
    return old;
  else
    insert into undo_log (table_name, row_id, op, before, actor)
    values (tg_table_name, (to_jsonb(old)->>(tg_argv[0])), 'UPDATE', to_jsonb(old), v_actor);
    return new;
  end if;
exception when others then
  -- never let audit failure block the company's work
  if tg_op = 'DELETE' then return old; else return new; end if;
end $fn$;

do $do$
declare t record;
begin
  for t in
    select * from (values
      ('agent_knowledge','id'), ('company_goals','key'), ('employee_kpi','id'),
      ('decision_policy','key'), ('org_tasks','id'), ('priority_hierarchy','rank'),
      ('business_rules','id'), ('feature_flags','id'), ('model_policy','id'),
      ('employee_authority','agent_key'), ('governance_rule','id'), ('department_objective','id')
    ) v(tbl, pk)
  loop
    if exists (select 1 from information_schema.tables
               where table_schema='public' and table_name=t.tbl) then
      execute format('drop trigger if exists trg_undo_%1$s on public.%1$I', t.tbl);
      execute format(
        'create trigger trg_undo_%1$s before update or delete on public.%1$I
         for each row execute function public.trg_undo_capture(%2$L)', t.tbl, t.pk);
    end if;
  end loop;
end $do$;

-- Reverse a captured change.
create or replace function public.fn_undo(p_undo_id bigint, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v_cols text; v_sql text;
begin
  select * into r from undo_log where id = p_undo_id;
  if not found then return jsonb_build_object('ok',false,'error','undo_log row not found'); end if;
  if r.reverted then return jsonb_build_object('ok',false,'error','already reverted'); end if;

  if r.op = 'DELETE' then
    select string_agg(quote_ident(key), ', ') into v_cols from jsonb_object_keys(r.before) as key;
    v_sql := format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)', r.table_name, r.table_name);
    execute v_sql using r.before;
  else
    v_sql := format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) where %I::text = $2',
                    r.table_name,
                    (select string_agg(quote_ident(k), ', ') from jsonb_object_keys(r.before) k),
                    (select string_agg(quote_ident(k), ', ') from jsonb_object_keys(r.before) k),
                    r.table_name,
                    (select column_name from information_schema.columns
                      where table_schema='public' and table_name=r.table_name
                      order by ordinal_position limit 1));
    execute v_sql using r.before, r.row_id;
  end if;

  update undo_log set reverted = true where id = p_undo_id;

  insert into os_audit_log (actor, action, entity, entity_id, detail, ok)
  values (coalesce(r.actor,'system'), 'undo', r.table_name, r.row_id,
          jsonb_build_object('undo_id',p_undo_id,'op',r.op,'reason',p_reason), true);

  return jsonb_build_object('ok',true,'table',r.table_name,'row_id',r.row_id,'op',r.op);
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end $fn$;

revoke execute on function public.fn_undo(bigint,text) from public, anon, authenticated;

comment on function public.fn_undo(bigint,text) is
  'Restores a row captured in undo_log. Reversal is now a system action, not a human redo.';