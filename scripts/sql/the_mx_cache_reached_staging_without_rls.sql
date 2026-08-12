-- The MX cache reached staging without RLS
-- ========================================
--
-- project_parity caught it: "table WITHOUT rls  prod 0  staging 1 - staging only: email_domain_mx".
-- Identical DDL was applied to both projects, so production enabled RLS on the new table by itself
-- and staging did not. Whatever the asymmetry is, the check is right and the guard belongs in the
-- migration rather than in whatever happened to run on one project.
--
-- No policies. email_domain_mx is a DNS answer cache read by fn_email_sendable, which is SECURITY
-- DEFINER, and by the sweep script running as service_role. Neither goes through RLS. RLS enabled
-- with no policy means anon and authenticated read nothing, which is exactly right: it is a list of
-- which domains are dead, and there is no reason for a browser to hold it.

alter table public.email_domain_mx enable row level security;
