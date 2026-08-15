-- REORGANISING THE AGENT COMPANY - 19: the last drifting object.
--
-- project_parity reported 63 drifting objects at the start of this session, 29 after the first nine
-- v3_repair files reached production, and 1 after the tool-registry chain landed. This is that one.
--
-- public.task_commercial_effect exists on BOTH projects, but row-level security is enabled on
-- production and was never enabled on staging. Measured on staging before this file: relrowsecurity
-- false, 0 policies, 0 grants to anon or authenticated.
--
-- So nothing was exposed - the table is reachable only by service_role, which bypasses RLS anyway,
-- and by definers. That is why this has sat unnoticed. It is still real drift, and it drifts in the
-- direction that matters: staging is the project where a new policy gets written and tested, and a
-- policy authored against a table with RLS off behaves differently from the same policy on
-- production. The two projects must agree about whether the gate exists before anyone reasons about
-- what the gate allows.
--
-- No policy is added here. Adding one would be inventing an access decision this file is not
-- making; production has none either. Enabling RLS with no policy denies everything except
-- service_role and the table's definers, which is exactly production's current behaviour.

begin;

alter table public.task_commercial_effect enable row level security;

commit;
