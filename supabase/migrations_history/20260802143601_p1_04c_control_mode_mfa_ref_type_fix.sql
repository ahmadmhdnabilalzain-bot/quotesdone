-- phone_verifications.id is a uuid, not a bigint. Caught by the happy-path test: without it, the
-- ONLY path that actually opens Control Mode would have failed at runtime while every refusal path
-- worked - a gate that can never be opened looks exactly like a gate that works, until the founder
-- needs it at 3am.
alter table public.control_mode_session
  alter column mfa_ref type uuid using nullif(mfa_ref::text,'')::uuid;
