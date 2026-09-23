-- The website's error ingest names the seat that owns it.
--
-- WHAT WAS WRONG. PR #852 added the edge function `site_error_ingest` — the endpoint Next.js
-- instrumentation posts the website's own runtime errors to, which is what turned resilience_ping's
-- hard-coded "unavailable ... NOT checked" reading (index.ts:1084) into a real one. The function was
-- deployed on 23 Sep 2026; its `public.function_owner` row was not written. Measured by
-- scripts/checks/every_deployed_function_has_an_owner.mjs against production:
--
--   deployed functions: 74
--      29 sales_engineer, 19 customer_support, 10 it_engineer, 10 accountant, 4 marketing, 1 ceo
--   DEPLOYED WITH NO OWNER (1): site_error_ingest
--
-- That check is the one gate that stops a surface existing with nobody answering for it, and it
-- reads production, so it went red on every open PR at once — the cost of an unowned row is not
-- theoretical, it is every branch blocked until somebody claims the function.
--
-- WHY it_engineer. The seat that runs the detection engine owns the pipe that feeds it: the rows
-- land in public.error_events, fn_it_detect raises `website_runtime_errors` off them, and
-- fn_prune_website_error_events (PR #852) keeps them only as long as that reader looks back.
-- Nothing customer-facing writes here and no other seat reads it.
--
-- Seat: it_engineer.

begin;

insert into public.function_owner (function_slug, owner, note)
values ('site_error_ingest', 'it_engineer',
        'The website posts its own runtime errors here (Next.js onRequestError -> error_events, PR #852). '
        'Public surface, verify_jwt=false, gated on the shared secret in x-qd-site-secret and rate-limited; '
        'fn_it_detect raises website_runtime_errors off the rows and fn_prune_website_error_events keeps them '
        'only as long as that reader looks back. The seat that acts on the signal owns the pipe that carries it.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

-- The verdict: every deployed function has an owner again. No `raise exception` — this file carries
-- an insert, and an exception would roll it back with the check it is meant to prove.
select case
  when (select count(*) from public.function_owner where function_slug = 'site_error_ingest' and owner = 'it_engineer') = 1
  then 'PROBE OK :: site_error_ingest is owned by it_engineer'
  else 'PROBE FAILED :: site_error_ingest still has no it_engineer owner row'
end as verdict;

commit;
