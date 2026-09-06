CREATE OR REPLACE FUNCTION public.fn_org_phase_baseline_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
