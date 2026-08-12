-- apply_sql --promote carries the routine DEFINITION, not the GRANTS. The revokes in
-- the_channel_gets_its_own_eyes.sql therefore landed on staging alone, and project_parity caught it
-- one command later: "anon-executable SECURITY DEFINER  prod 57  staging 56 ... prod only:
-- fn_wa_context". A SECURITY DEFINER function that returns the whole company snapshot for
-- p_audience='founder' was executable by anon on production. --ddl carries the whole file to both.
revoke all on function public.fn_wa_context(text, text) from public;
revoke all on function public.fn_wa_context(text, text) from anon;
