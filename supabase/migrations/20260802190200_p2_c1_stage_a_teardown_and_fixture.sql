-- P2-C1 STAGE A - the fixture teardown gate and the fixture helper.
-- Applied as migration 20260802165847 p2_c1_stage_a_teardown_gate.
--
-- Test fixtures have to be removable, and evidence has to be undeletable. Both, at once.
-- The gate is a transaction-local setting that only a SECURITY DEFINER function sets and clears,
-- so a caller with table rights still cannot delete evidence: they can reach the tables, but not
-- the setting. UPDATE stays refused unconditionally - history is never rewritten, only removed
-- wholesale by a fixture teardown that names itself.

create or replace function public.trg_p2c1_append_only()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE'
     and coalesce(current_setting('quotesdone.p2c1_teardown', true), '') = 'approved' then
    return old;
  end if;
  raise exception '% is append-only: % is not permitted.', tg_table_name, tg_op
    using hint = 'Evidence that can be deleted is evidence nobody can rely on. Record a new row instead.';
end $fn$;

create or replace function public.trg_inquiry_answer_value_immutable()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    if coalesce(current_setting('quotesdone.p2c1_teardown', true), '') = 'approved' then
      return old;
    end if;
    raise exception 'inquiry_answer rows are never deleted (id %)', old.id
      using hint = 'Supersede the answer instead. The chain is the history.';
  end if;
  if new.value       is distinct from old.value
     or new.field_id    is distinct from old.field_id
     or new.group_id    is distinct from old.group_id
     or new.precedence  is distinct from old.precedence
     or new.source_kind is distinct from old.source_kind then
    raise exception 'inquiry_answer % is immutable; supersede it instead of editing it', old.id;
  end if;
  if old.superseded_by is not null and new.superseded_by is distinct from old.superseded_by then
    raise exception 'inquiry_answer % is already superseded by %', old.id, old.superseded_by;
  end if;
  return new;
end $fn$;

-- Fill every mandatory requirement of one workstream, so a test can isolate the ONE thing it is
-- actually about instead of drowning in setup.
create or replace function public.fn_p2c1_fixture_satisfy(
  p_group bigint, p_ws bigint, p_actor text default 'selftest')
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare rec record; n integer := 0;
begin
  for rec in
    select r.field_id, fd.scope
      from public.inquiry_workstream_requirement r
      join public.field_definition fd on fd.field_id = r.field_id
     where r.workstream_id = p_ws and r.mandatory
  loop
    if rec.scope = 'shared' then
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, 'fixture-value',
                'customer_confirmed', 'customer', p_actor);
    else
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, 'fixture-value',
                'customer_confirmed', 'customer', p_actor, null, array[p_ws]);
    end if;
    n := n + 1;
  end loop;

  insert into public.inquiry_gate (group_id, workstream_id, gate_key, passed, asserted_by)
  select p_group, p_ws, gr.gate_key, true, p_actor
    from public.inquiry_gate_required gr where gr.level = 'workstream'
  on conflict do nothing;

  return n;
end $fn$;

revoke all on function public.fn_p2c1_fixture_satisfy(bigint, bigint, text) from public, anon, authenticated;
