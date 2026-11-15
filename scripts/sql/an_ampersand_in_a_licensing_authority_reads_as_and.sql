-- Assigned: customer_support
-- AN AMPERSAND IN A LICENSING AUTHORITY READS AS "AND" (15 Nov 2026, customer_support; Monday checklist, founder ledger 1692).
--
-- MEASURED, read-only on production, 15 Nov 2026 (SELECT public.fn_licence_authority_class(...) over 52 printed spellings):
-- every mainland and free-zone authority a UAE general manager may hold classed 'uae', including SAIF, Masdar, KEZAD, Ajman Free
-- Zone, Hamriyah, Fujairah Free Zone, UAQ Free Trade Zone, Dubai South, DWTC, ADRA and twofour54. Four did not:
--   'Department of Economy & Tourism'  -> unknown      (Dubai's own licensing body, written with its ampersand and no "Dubai")
--   'Economic Department', 'TAMM'      -> unknown      (left as they are: neither names an emirate or a licensing body)
--   'Sharjah Chamber of Commerce ...'  -> unknown      (right: a_chamber_of_commerce_or_a_residency_office_is_not_a_licensing_authority.sql)
-- fn_licence_authority_norm turns every run of non-letters into one space, so '&' vanished and "department of economy tourism"
-- matched neither 'department of economy and tourism' nor any emirate. 'unknown' holds the registration as
-- licence_authority_unconfirmed for a person (fn_sales_engineer_verifies_supplier), and a held licence has no screen for accepting it
-- (docs/reports/2026-11-12-evening-releases.md). The model is told to give the authority "as printed", so a Dubai licence read as
-- "Department of Economy & Tourism" is one plausible answer away from a held registration on Monday.
-- WHAT CHANGES: '&' (and its HTML form) is read as ' and ' before the existing normalisation. fn_licence_authority_class, its one
-- caller, is not touched; every name that does not print an ampersand normalises exactly as before (the probe holds both).
-- Replaced from the canonical definition in only_a_readable_uae_authority_is_approved_and_a_held_registration_has_a_decider.sql;
-- CREATE OR REPLACE keeps the ACL; the revoke is repeated. IMMUTABLE and search_path unchanged.
-- Probe: scripts/sql/an_ampersand_in_a_licensing_authority_reads_as_and_probe.sql
create or replace function public.fn_licence_authority_norm(p_authority text)
 returns text language sql immutable set search_path to 'public', 'pg_temp'
as $fn$
  select btrim(regexp_replace(replace(replace(replace(
           translate(replace(replace(lower(coalesce(p_authority, '')), '&amp;', ' and '), '&', ' and '), 'أإآةى', 'اااهي'),
           'abudhabi', 'abu dhabi'), 'rasalkhaimah', 'ras al khaimah'), 'ابوظبي', 'ابو ظبي'),
         '[^[:alnum:]؀-ۿ]+', ' ', 'g'))
$fn$;
revoke execute on function public.fn_licence_authority_norm(text) from public, anon, authenticated;
