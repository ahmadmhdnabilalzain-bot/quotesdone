-- DOWN for O04. Classification: ADDITIVE_DDL — three tables, one trigger, four routines, one
-- committed identifier register. Dropped in dependency order: the scan table has an FK onto the
-- revision table, and O07's BR-011/BR-012 legs read all of it, so run O07's down first.
DROP FUNCTION IF EXISTS public.fn_phase_d_package_revisions_dispatchable(text);
DROP FUNCTION IF EXISTS public.fn_phase_d_file_revision_dispatchable(text, text);
DROP TABLE IF EXISTS public.phase_d_metadata_scan;
DROP TRIGGER IF EXISTS a10_phase_d_file_revision_reviewer ON public.phase_d_file_revision;
DROP FUNCTION IF EXISTS public.fn_phase_d_file_revision_reviewer_independent() CASCADE;
DROP TABLE IF EXISTS public.phase_d_file_revision;
DROP TABLE IF EXISTS public.phase_d_personal_identifier_class;
