-- founder_directive was created without RLS and project_parity caught it: prod 0 tables without
-- RLS, staging 1, "staging only: founder_directive". Production has an event trigger that arms RLS
-- on a new table; staging does not, so the same DDL produced two different tables. The guard was
-- right and it caught it inside the same session the table was created.
--
-- No policy is added on purpose. Every read and write goes through fn_founder_settings and
-- fn_founder_apply_setting, which are SECURITY DEFINER, and service_role bypasses RLS. RLS with no
-- policy therefore means exactly what it should: nothing reaches this audit trail from a browser.
alter table public.founder_directive enable row level security;
