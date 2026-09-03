-- fn_undo REVERTS BY THE TABLE'S REAL PRIMARY KEY, NOT WHATEVER COLUMN HAPPENS TO COME FIRST.
--
-- The previous body chose the key as `information_schema.columns ... order by ordinal_position limit 1`
-- — the first column by position. On the eleven tables undo_log has ever recorded, ten happen to lead
-- with their key, so it worked by luck. employee_authority does not: its key is the COMPOSITE
-- (agent_key, action_class), its first column is agent_key alone, and supplier_verification holds nine
-- authority rows — so reverting one change to one of them would have rewritten all nine with the
-- before-image of the one. That is corruption dressed as an undo.
--
-- Now the key is read from pg_constraint (contype 'p'), every key column is matched, and the key
-- VALUES come from the logged before-image (a composite key cannot ride the single-text row_id). A
-- table with no primary key is refused rather than guessed at. Supersedes the definition in
-- supabase/migrations_history/20260728172931_fn_undo_correct_uuid_signature.sql; CREATE OR REPLACE
-- keeps the existing ACL, so no revoke here.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_undo_uses_the_real_primary_key.sql --apply --ddl

create or replace function public.fn_undo(p_undo_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_pk_cols text[]; v_where text;
begin
  select * into r from undo_log where id = p_undo_id;
  if not found then return jsonb_build_object('ok',false,'error','undo_log row not found'); end if;
  if r.reverted then return jsonb_build_object('ok',false,'error','already reverted'); end if;

  -- The real primary key, in constraint order.
  select array_agg(a.attname::text order by k.ord) into v_pk_cols
    from pg_constraint c
    join lateral unnest(c.conkey) with ordinality as k(attnum, ord) on true
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
   where c.conrelid = ('public.' || quote_ident(r.table_name))::regclass
     and c.contype = 'p';
  if v_pk_cols is null then
    return jsonb_build_object('ok',false,'error',
      'no primary key on '||r.table_name||' - refusing to guess which row to revert');
  end if;

  if r.op = 'DELETE' then
    execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)',
                   r.table_name, r.table_name) using r.before;
  else
    -- Match EVERY key column; take the key values from the before-image.
    select string_agg(format('t.%I::text = (select %I::text from jsonb_populate_record(null::public.%I, $1))',
                             k, k, r.table_name), ' and ')
      into v_where from unnest(v_pk_cols) k;
    execute format(
      'update public.%I t set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) where %s',
      r.table_name,
      (select string_agg(quote_ident(k), ', ') from jsonb_object_keys(r.before) k),
      (select string_agg(quote_ident(k), ', ') from jsonb_object_keys(r.before) k),
      r.table_name, v_where)
    using r.before;
  end if;

  update undo_log set reverted = true where id = p_undo_id;

  begin
    insert into os_audit_log (actor, action, entity, entity_id, detail, ok)
    values (coalesce(r.actor,'system'),'undo', r.table_name, r.row_id,
            jsonb_build_object('undo_id',p_undo_id,'op',r.op,'reason',p_reason,'key',v_pk_cols), true);
  exception when others then null; end;

  return jsonb_build_object('ok',true,'table',r.table_name,'row_id',r.row_id,'op',r.op,'key',to_jsonb(v_pk_cols));
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end $function$;
