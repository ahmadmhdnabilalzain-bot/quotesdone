drop function if exists public.fn_undo(bigint, text);

create or replace function public.fn_undo(p_undo_id uuid, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v_pk text; v_sql text;
begin
  select * into r from undo_log where id = p_undo_id;
  if not found then return jsonb_build_object('ok',false,'error','undo_log row not found'); end if;
  if r.reverted then return jsonb_build_object('ok',false,'error','already reverted'); end if;

  select column_name into v_pk from information_schema.columns
   where table_schema='public' and table_name=r.table_name order by ordinal_position limit 1;

  if r.op = 'DELETE' then
    execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)',
                   r.table_name, r.table_name) using r.before;
  else
    execute format(
      'update public.%I t set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) where t.%I::text = $2',
      r.table_name,
      (select string_agg(quote_ident(k), ', ') from jsonb_object_keys(r.before) k),
      (select string_agg(quote_ident(k), ', ') from jsonb_object_keys(r.before) k),
      r.table_name, v_pk)
    using r.before, r.row_id;
  end if;

  update undo_log set reverted = true where id = p_undo_id;

  begin
    insert into os_audit_log (actor, action, entity, entity_id, detail, ok)
    values (coalesce(r.actor,'system'),'undo', r.table_name, r.row_id,
            jsonb_build_object('undo_id',p_undo_id,'op',r.op,'reason',p_reason), true);
  exception when others then null; end;

  return jsonb_build_object('ok',true,'table',r.table_name,'row_id',r.row_id,'op',r.op);
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end $fn$;

revoke execute on function public.fn_undo(uuid,text) from public, anon, authenticated;