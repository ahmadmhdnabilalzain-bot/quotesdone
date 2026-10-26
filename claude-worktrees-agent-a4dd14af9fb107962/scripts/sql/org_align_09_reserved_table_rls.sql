-- ORG ALIGNMENT 09 — the reserved-decision registry had RLS on one project and not the other.
--
-- project_parity: "table WITHOUT rls  prod 0  staging 1 — staging only:
-- founder_reserved_decision". The table exists on both with the same 11 rows and the same trigger;
-- production enables RLS on a new public table automatically and staging did not, so the same DDL
-- produced two different security postures.
--
-- No policy is added, deliberately. The only readers are SECURITY DEFINER routines
-- (trg_org_role_no_reserved_decision) and the service role, both of which bypass RLS. RLS with no
-- policy therefore denies anon and authenticated, which is the correct posture for a registry of
-- what the founder has reserved to himself.
--
-- Idempotent: a no-op on production, which already has it.

alter table public.founder_reserved_decision enable row level security;
