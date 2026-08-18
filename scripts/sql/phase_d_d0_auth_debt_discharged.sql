-- PHASE D · D0 — THE TWO AUTHENTICATION CASES THE FOUNDER NAMED ARE NOW EXECUTED, NOT READ.
--
-- public.phase_d_preflight_requirement carried these as OUTSTANDING from the Phase C approval:
--
--   D0-AUTH-001  valid enabled founder JWT reaches the Command Center     expected 2xx
--   D0-AUTH-002  valid non-founder JWT is refused by the Command Center   expected 403
--
-- The Phase C closure audit was read-only and declined to mint a production session, so both were
-- recorded as verification debt owed at Phase D D0. Its own note on D0-AUTH-002 is the reason this
-- file exists: "The branch exists and was read at supabase/functions/os_api/index.ts:186, but
-- reading a branch is not executing it."
--
-- BOTH WERE EXECUTED AGAINST PRODUCTION on 2026-08-18 by
-- scripts/phase_d/discharge_d0_auth_debt.mjs, which is committed beside this file so the run is
-- repeatable rather than a story about a run:
--
--   PASS  D0-AUTH-001  management@quotesdone.com          expected 2xx, got 200
--         {"ok":true,"user":"management@quotesdone.com"}
--   PASS  D0-AUTH-002  zz-phase-d-canary@example.invalid  expected 403, got 403
--         {"error":"forbidden"}
--
-- HOW EACH IDENTITY WAS OBTAINED. The founder session was minted with the admin generate_link
-- API, which returns a link and sends no mail, then verified for a real bearer. No password was
-- read, set or handled and the founder's account was not modified. The non-founder session used a
-- canary auth identity under the repository's established fixture convention — ZZ-prefixed, at
-- example.invalid — created, used for exactly one request, and deleted in the same run. Its
-- removal was proved by read-back, not assumed from the delete returning 200: DELETE -> 200,
-- subsequent GET -> 404. PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md permits explicitly
-- namespaced/cleaned canaries and forbids persistent demo customers and suppliers; this was an
-- auth identity only, and no customer, supplier, inquiry or other business row was created.
--
-- WHAT THIS DOES NOT CLAIM. Two identity branches of one edge function were executed with one
-- already-classified read-only action. It is not a statement about any other action, any other
-- function, or authorization beyond the founder/non-founder split those two cases name.

begin;

update public.phase_d_preflight_requirement
   set status       = 'SATISFIED',
       satisfied_at = timestamptz '2026-08-18 14:56:00+00',
       evidence     = jsonb_build_object(
         'executed_by',  'scripts/phase_d/discharge_d0_auth_debt.mjs',
         'executed_at',  '2026-08-18T14:56:00Z',
         'project_ref',  'htdblwldjkcgjvmqkbeh',
         'endpoint',     'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api',
         'action',       'ping (read-only, already classified in ACTION_CLASS)',
         'identity',     'management@quotesdone.com — active, kind email, in public.phase_c_founder_identity',
         'expected',     '2xx',
         'observed',     '200 {"ok":true,"user":"management@quotesdone.com"}',
         'session_minted_by', 'auth admin generate_link (returns a link, sends no mail) then /auth/v1/verify',
         'password_handled',  false,
         'limitation',   'One identity branch of one edge function, exercised with one read-only action. Not a statement about other actions or other functions.')
 where requirement_id = 'D0-AUTH-001';

update public.phase_d_preflight_requirement
   set status       = 'SATISFIED',
       satisfied_at = timestamptz '2026-08-18 14:56:00+00',
       evidence     = jsonb_build_object(
         'executed_by',  'scripts/phase_d/discharge_d0_auth_debt.mjs',
         'executed_at',  '2026-08-18T14:56:00Z',
         'project_ref',  'htdblwldjkcgjvmqkbeh',
         'endpoint',     'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api',
         'action',       'ping (read-only, already classified in ACTION_CLASS)',
         'identity',     'zz-phase-d-canary@example.invalid — a real signed-in identity absent from public.phase_c_founder_identity',
         'expected',     '403',
         'observed',     '403 {"error":"forbidden"}',
         'canary_lifecycle', 'created, used for exactly one request, deleted in the same run; removal proved by read-back DELETE 200 then GET 404, not assumed from the delete status',
         'business_rows_created', 0,
         'limitation',   'Proves the non-founder branch returns 403 for one action. Not a statement about per-action authorization inside the Command Center.')
 where requirement_id = 'D0-AUTH-002';

-- The register is only worth having if it refuses a silent no-op. If either row failed to move,
-- the update above matched nothing and this raises rather than committing a file whose comment
-- says two requirements were discharged.
do $assert$
declare n_open int;
begin
  select count(*) into n_open
    from public.phase_d_preflight_requirement
   where requirement_id in ('D0-AUTH-001','D0-AUTH-002')
     and (status <> 'SATISFIED' or satisfied_at is null or evidence is null);
  if n_open > 0 then
    raise exception 'phase_d_d0_auth_debt_discharged: % of the 2 preflight rows did not move to SATISFIED with evidence', n_open
      using errcode = '23514';
  end if;
end $assert$;

commit;
