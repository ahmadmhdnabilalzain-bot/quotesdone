-- THE ORGANISATION BASELINE IS APPEND-ONLY.
--
-- A baseline record states what the organisation looked like at a moment. Editing one rewrites a
-- measurement that was already taken, so the trigger refuses an UPDATE or a DELETE and lets an
-- INSERT through. A correction is a new row, never a changed one.
--
-- This file carries the definition that is deployed on production, taken from pg_get_functiondef.
-- It is a repository reorganisation: the routine was written inside a file whose name belonged to a
-- programme that no longer exists, and the routine outlived it. Nothing about the behaviour changes.

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
end $function$;
