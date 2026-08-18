-- PHASE D · D8f — THE FIXTURE READS THE CHECK CONSTRAINT INSTEAD OF ARGUING WITH IT.
--
--   W04-S01  new row for relation "customers" violates check constraint "customers_locale_chk"
--
-- A CHECK constraint has caught a real mistake in this repository before, and the standing rule is
-- to read what it says rather than route around it. `locale` is not free text: the constraint
-- enumerates the values the column may hold, and 'ZZ DEMO — locale-W04-S01' is not one of them.
--
-- The wrong fixes, both rejected:
--   * drop constrained columns from the fixture — which is how the payload became empty enough to
--     move nothing and trip pd_object_no_state_change in the first place;
--   * relax the constraint — a guard weakened to make a harness pass is worth less than no guard.
--
-- The fix is to READ the constraint. fn_phase_d_fixture_for_column pulls the column's own CHECK
-- definitions out of pg_constraint and, where one enumerates literals, uses the first of them.
-- Where a constraint is not an enumeration the typed fixture is returned unchanged and the write is
-- allowed to refuse — which is honest, and names the constraint that refused it.
--
-- The single-column check is found through pg_constraint.conkey, so a multi-column check that
-- happens to mention the column is not mistaken for an enumeration of it.

begin;

create or replace function public.fn_phase_d_fixture_for_column(
  p_relation text, p_column text, p_label text)
returns jsonb
language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_oid    oid := p_relation::regclass;
  v_ftype  text;
  v_tcat   text;
  v_attnum smallint;
  v_def    text;
  v_lits   text[];
begin
  select a.attnum, format_type(a.atttypid, a.atttypmod),
         (select ty.typcategory from pg_type ty where ty.oid = a.atttypid)
    into v_attnum, v_ftype, v_tcat
    from pg_attribute a
   where a.attrelid = v_oid and a.attname = p_column and a.attnum > 0;
  if v_attnum is null then
    raise exception 'fn_phase_d_fixture_for_column: % has no column %', p_relation, p_column
      using errcode = '42703';
  end if;

  -- conkey = ARRAY[attnum] restricts this to checks over THIS column alone. A multi-column check
  -- that merely mentions the column enumerates a relationship, not a value set, and reading its
  -- literals would produce a value that satisfies nothing.
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = v_oid and c.contype = 'c' and c.conkey = array[v_attnum]
   order by c.conname
   limit 1;

  if v_def is not null then
    select array_agg(m[1] order by ord) into v_lits
      from regexp_matches(v_def, '''([^'']+)''', 'g') with ordinality t(m, ord);
    if v_lits is not null and cardinality(v_lits) > 0 then
      -- An enumerated column takes a DECLARED value. It is no longer visibly a fixture, and that is
      -- the constraint's decision, not a shortcut: the row is still identifiable as a fixture by
      -- every unconstrained column on it.
      if v_tcat = 'A' then
        return jsonb_build_array(v_lits[1]);
      end if;
      return to_jsonb(v_lits[1]);
    end if;
  end if;

  return public.fn_phase_d_fixture_value(v_ftype, v_tcat, p_label);
end $fn$;

revoke all on function public.fn_phase_d_fixture_for_column(text, text, text) from public;
grant execute on function public.fn_phase_d_fixture_for_column(text, text, text) to service_role;

commit;
