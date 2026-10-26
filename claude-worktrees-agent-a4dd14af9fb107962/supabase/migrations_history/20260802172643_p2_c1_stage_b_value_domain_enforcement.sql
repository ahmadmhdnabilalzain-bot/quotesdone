-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802172643   name: p2_c1_stage_b_value_domain_enforcement
-- SHA-256 of the applied SQL: d89d6cba92352f35ab12ce796a484424651577b7393fcc5d25304d0f5e109a35
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Enforce allowed_values at the table, not only in the setter. A domain that only one write path
-- respects is a domain that the second write path will break.
create or replace function public.trg_inquiry_answer_value_domain()
returns trigger language plpgsql as $fn$
begin
  if not public.fn_field_value_allowed(new.field_id, new.value) then
    raise exception 'value %L is not in the allowed domain for field %', new.value, new.field_id
      using hint = 'Allowed values are listed in field_definition.allowed_values.';
  end if;
  return new;
end $fn$;

drop trigger if exists inquiry_answer_value_domain on public.inquiry_answer;
create trigger inquiry_answer_value_domain before insert on public.inquiry_answer
  for each row execute function public.trg_inquiry_answer_value_domain();

-- The fixture helper must produce domain-valid values now that domains exist.
create or replace function public.fn_p2c1_fixture_satisfy(
  p_group bigint, p_ws bigint, p_actor text default 'selftest')
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare rec record; n integer := 0; v_val text;
begin
  for rec in
    select r.field_id, fd.scope, fd.allowed_values
      from public.inquiry_workstream_requirement r
      join public.field_definition fd on fd.field_id = r.field_id
     where r.workstream_id = p_ws and r.mandatory
  loop
    v_val := coalesce(rec.allowed_values[1], 'fixture-value');
    if rec.scope = 'shared' then
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, v_val,
                'customer_confirmed', 'customer', p_actor);
    else
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, v_val,
                'customer_confirmed', 'customer', p_actor, null, array[p_ws]);
    end if;
    n := n + 1;
  end loop;

  insert into public.inquiry_gate (group_id, workstream_id, gate_key, state, asserted_by)
  select p_group, p_ws, gr.gate_key, 'passed'::public.gate_state, p_actor
    from public.inquiry_gate_required gr where gr.level = 'workstream'
  on conflict do nothing;

  return n;
end $fn$;

revoke all on function public.fn_p2c1_fixture_satisfy(bigint, bigint, text) from public, anon, authenticated;
revoke all on function public.fn_field_value_allowed(text, text) from public, anon, authenticated;
;