-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719171145   name: h4a_revoke_anon_default_privileges_public_20260719
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H4a: stop new public objects created by `postgres` (dashboard/SQL editor — the C1 vector)
-- being born anon/authenticated-readable. Future-only; cannot affect any existing object.
alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions  from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences  from anon, authenticated;
