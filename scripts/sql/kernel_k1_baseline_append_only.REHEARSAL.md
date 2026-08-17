# Aborted-transaction rehearsal — `kernel_k1_baseline_append_only.sql`

**Not yet run. Not yet applied.** This file is the exact SQL to paste, and what a pass looks like.

A migration that adds a guard has one question worth asking, and it is not "did it create the
trigger". It is **did the guard actually refuse, and refuse the right things** — a `create trigger`
that succeeds proves creation, never execution. So the rehearsal fires both branches (`UPDATE` and
`DELETE`) inside one transaction, catches each refusal, and then aborts on purpose so production is
left exactly as it was found. Nothing below writes: the outer transaction ends in `rollback`, and it
gets there by raising, so a copy-paste that loses the last line still cannot commit.

Two facts are asserted before the probes so that a green result cannot be green for the wrong reason:

* the trigger **did not already exist** — otherwise the rehearsal would be testing something that was
  already there and proving nothing about this file;
* the guard function is **not executable by `anon` or `authenticated`** — it is `SECURITY DEFINER`,
  and the `REVOKE` is part of what is being rehearsed.

## The SQL

```sql
begin;

-- ---------------------------------------------------------------- 0. the state before the migration
do $before$
begin
  if exists (select 1 from pg_trigger t
              where t.tgrelid = 'public.org_phase_baseline'::regclass
                and t.tgname = 'a00_org_phase_baseline_append_only'
                and not t.tgisinternal) then
    raise exception 'a00_org_phase_baseline_append_only ALREADY EXISTS — this rehearsal would be '
                 || 'measuring a guard that was already in place, not the one in this file. Stop.';
  end if;
end $before$;

-- ---------------------------------------------------------------- 1. THE MIGRATION, verbatim
--    (scripts/sql/kernel_k1_baseline_append_only.sql — header comments omitted for length only)
create or replace function public.fn_org_phase_baseline_append_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  raise exception
    'org_phase_baseline is append-only: % on the frozen phase % baseline is refused',
    tg_op, coalesce(old.phase, '?')
    using errcode = '23514',
          hint = 'These rows are the founder-approved record of what a phase WAS when it was '
              || 'approved, and four drift checks read them as the fixed point they measure '
              || 'against. To change one, raise a Phase change request: write '
              || 'scripts/sql/pacr_NNN_<what_and_why>.sql which drops trigger '
              || 'a00_org_phase_baseline_append_only, makes the change with every digest '
              || 'RECOMPUTED in place, recreates the trigger in the same transaction, and is '
              || 'appended to scripts/sql/MANIFEST.txt. The dropped trigger in that file is the '
              || 'record that the freeze was deliberately opened.';
end $$;

revoke all on function public.fn_org_phase_baseline_append_only() from public;
grant execute on function public.fn_org_phase_baseline_append_only() to service_role;

drop trigger if exists a00_org_phase_baseline_append_only on public.org_phase_baseline;
create trigger a00_org_phase_baseline_append_only
  before update or delete on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

-- ---------------------------------------------------------------- 2. probe it, then abort on purpose
do $rehearsal$
declare
  v_upd    text := 'NOT REFUSED — THE TRIGGER DID NOT FIRE';
  v_del    text := 'NOT REFUSED — THE TRIGGER DID NOT FIRE';
  v_before bigint;
  v_after  bigint;
  v_anon   boolean;
  v_auth   boolean;
  v_svc    boolean;
  v_ok     boolean;
begin
  select count(*) into v_before from public.org_phase_baseline;

  -- UPDATE branch. The statement is a realistic one: it is the shape pacr_001 used, which is the
  -- write that actually landed four times on the phase 'A' note.
  begin
    update public.org_phase_baseline
       set note = coalesce(note, '') || E'\n\nrehearsal write that must never land'
     where phase = 'A';
    v_upd := 'NOT REFUSED — ' || 'the UPDATE succeeded, which is the defect this file exists to stop';
  exception
    when sqlstate '23514' then v_upd := 'refused 23514 — ' || sqlerrm;
    when others           then v_upd := 'refused with the WRONG sqlstate ' || sqlstate || ' — ' || sqlerrm;
  end;

  -- DELETE branch. A BEFORE UPDATE trigger that forgot OR DELETE looks identical to a correct one
  -- until someone deletes a row, so this branch is not optional.
  begin
    delete from public.org_phase_baseline where phase = 'B';
    v_del := 'NOT REFUSED — the DELETE succeeded, which is the defect this file exists to stop';
  exception
    when sqlstate '23514' then v_del := 'refused 23514 — ' || sqlerrm;
    when others           then v_del := 'refused with the WRONG sqlstate ' || sqlstate || ' — ' || sqlerrm;
  end;

  select count(*) into v_after from public.org_phase_baseline;

  v_anon := has_function_privilege('anon',          'public.fn_org_phase_baseline_append_only()', 'execute');
  v_auth := has_function_privilege('authenticated', 'public.fn_org_phase_baseline_append_only()', 'execute');
  v_svc  := has_function_privilege('service_role',  'public.fn_org_phase_baseline_append_only()', 'execute');

  v_ok := v_upd like 'refused 23514%'
      and v_del like 'refused 23514%'
      and v_before = v_after
      and v_before = 2
      and not v_anon and not v_auth and v_svc;

  raise exception E'\n=== K1 REHEARSAL %  (this transaction is being aborted ON PURPOSE) ===\n'
                   'UPDATE phase A : %\n'
                   'DELETE phase B : %\n'
                   'rows before/after : % / %  (must be 2 / 2)\n'
                   'execute: anon=%  authenticated=%  service_role=%  (must be f f t)\n',
    case when v_ok then 'PASSED' else 'FAILED' end,
    v_upd, v_del, v_before, v_after, v_anon, v_auth, v_svc;
end $rehearsal$;

rollback;
```

## What a pass looks like

The whole run comes back as **one error**, and that is the intended outcome — the result is carried
in the exception message because a `raise` is the only way to guarantee the transaction cannot
commit even if the trailing `rollback;` is lost:

```
=== K1 REHEARSAL PASSED  (this transaction is being aborted ON PURPOSE) ===
UPDATE phase A : refused 23514 — org_phase_baseline is append-only: UPDATE on the frozen phase A baseline is refused
DELETE phase B : refused 23514 — org_phase_baseline is append-only: DELETE on the frozen phase B baseline is refused
rows before/after : 2 / 2  (must be 2 / 2)
execute: anon=f  authenticated=f  service_role=t  (must be f f t)
```

`PASSED` in that first line is the only thing that counts. Any of these is a **FAIL**, and each one
names a different real bug rather than a flaky test:

| symptom | what it means |
|---|---|
| `UPDATE ... NOT REFUSED` | the trigger is not on `UPDATE`, or is `AFTER` rather than `BEFORE`, or is `FOR EACH STATEMENT` and matched no row |
| `DELETE ... NOT REFUSED` | `or delete` was dropped from the trigger definition — the most likely typo in this file |
| `refused with the WRONG sqlstate` | the `using errcode = '23514'` was lost, so callers cannot distinguish this refusal from any other error |
| `rows before/after` not `2 / 2` | a write landed. Something is very wrong; do not apply |
| `anon=t` or `authenticated=t` | the `REVOKE` did not take — a new `SECURITY DEFINER` function is anon-executable |

## After the rehearsal

Nothing is applied by this document. Applying is the separate, deliberate step:

```
node scripts/apply_sql.mjs scripts/sql/kernel_k1_baseline_append_only.sql --promote --ddl
```

Then append `scripts/sql/kernel_k1_baseline_append_only.sql` to `scripts/sql/MANIFEST.txt` (it is
already listed there as part of increment K1) and re-run
`node scripts/checks/canonical_routines.test.mjs`.

One caveat that belongs with the apply and not with the rehearsal: `--promote` posts the *routine
definition* read back from the applied database. The `REVOKE`/`GRANT` and the `CREATE TRIGGER` in
this file are not part of a routine definition, so confirm on production, after applying, that
`a00_org_phase_baseline_append_only` exists on `public.org_phase_baseline` and that
`has_function_privilege('anon', 'public.fn_org_phase_baseline_append_only()', 'execute')` is false.
