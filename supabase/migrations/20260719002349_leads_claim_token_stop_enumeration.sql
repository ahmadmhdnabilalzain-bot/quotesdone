-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719002349   name: leads_claim_token_stop_enumeration
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Give every lead a non-enumerable claim token.
--
-- WHY (19 Jul 2026): the claim_lookup edge function is public by design - a supplier who receives
-- an invitation must be able to confirm "is this your company?" before claiming it. But it keyed
-- on leads.id, a sequential integer, and returned company_name + emirate. Iterating id = 1..N
-- therefore walked the entire 20,470-row supplier database, which is the core commercial asset of
-- the marketplace. No authentication could be added without breaking the public claim flow, so the
-- fix is to make the identifier unguessable instead.
--
-- Timing: zero claim invitations have been sent and zero leads have been claimed, so switching the
-- contract now costs nothing. Doing it after outreach begins would have invalidated live links.

alter table public.leads
  add column if not exists claim_token uuid not null default gen_random_uuid();

-- Unique so a token identifies exactly one lead, and indexed because it becomes the lookup key.
create unique index if not exists leads_claim_token_key on public.leads (claim_token);

comment on column public.leads.claim_token is
  'Unguessable public identifier for the supplier claim flow. Invitation links must carry this, never leads.id - id is sequential and would let anyone enumerate the whole supplier database via claim_lookup.';
