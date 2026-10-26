-- A LARGE CAD DRAWING IS READ OFF THE REQUEST PATH.
--
-- Assigned: sales_engineer. 22 Sep 2026. Founder instructions 31/63/64/696 ("finish the drawing matter
-- now"; OpenConstructionERP-level take-off from every common format) and 22 Sep: "customer will share
-- cad files or pdf mainly" - a DWG of ANY size must be read.
--
-- MEASURED BEFORE THIS FILE (production, 22 Sep 2026, read-only calls to the deployed drawing_boq):
--   * Every DWG sent to drawing_boq mode 'document' - 22 KB, 183 KB, 389 KB, 408 KB, 562 KB, 569 KB -
--     answered HTTP 546 WORKER_RESOURCE_LIMIT, and the function log reads "Memory limit exceeded". The
--     LibreDWG .wasm declares a 1 GB MINIMUM memory; the edge counts it. So no DWG of any size was read on
--     production, though #821 measured them read on a laptop. Fixed in _shared/doc_read/dwg.ts
--     (lowerMemoryFloor), which needs a deploy, not this file.
--   * Even with that fixed, the cost of a DWG is not its size: on the dev machine, cold, a 562 KB drawing
--     with 2,551 entities took 1.9 s of CPU and a 2.1 MB one 2.7 s - past the edge's 2 s CPU cap - while a
--     1.4 MB one took 0.45 s. A CPU kill ends the worker with no catch and no finding.
--
-- WHAT THIS CHANGES:
--   public.cad_read_jobs holds a CAD original that the edge could not read inside its caps (over the
--   edge ceiling, or the edge worker died reading it). customer_api writes the row and tells the customer
--   the drawing is being processed; .github/workflows/cad-read-worker.yml runs scripts/cad_read_worker.ts
--   on a GitHub runner (no 2 s CPU cap, 7 GB memory) with the SAME reader code, and writes the take-off
--   back here; customer_api action 'cad_read_status' hands it to the customer's own screen.
--   fn_cad_read_claim hands a worker at most p_limit jobs with FOR UPDATE SKIP LOCKED, so two runners
--   never read the same drawing, and takes back a job whose runner died (running for 30 minutes).
--   A job that failed or died three times is marked 'failed' with its reason, and the customer is told.
--
-- THE SAME QUEUE CARRIES A PDF SET'S LENGTHS. Measured on production the same day with the synthetic CAD set
-- of scripts/e2e/drawing_reaches_suppliers.mjs: the take-off answered 200 at 8, 20 and 40 sheets (1.1-1.8 s
-- wall), and the lengths call (drawing_set.ts, a second call) answered 200 at 8 and 20 sheets and 546 at 40.
-- customer_api queues that one with the counted take-off in boq_in, and the worker merges the lengths in.
--
-- WHAT IT DOES NOT CHANGE: no reader logic lives here, nothing is read or scored in SQL, and no existing
-- table or routine is touched. The storage object stays in drawing-files where storeOriginal put it.
--
-- RLS: service role only (customer_api and the worker). No customer reads this table directly; the
-- customer sees their own job only through customer_api, which checks customer_id.

create table if not exists public.cad_read_jobs (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  customer_id  uuid,
  owner_email  text,
  source_path  text not null,
  file_name    text not null default '',
  mime         text not null default '',
  bytes        integer,
  why          text not null check (why in ('over_edge_ceiling', 'edge_worker_died', 'edge_reader_failed', 'pdf_lengths_worker_died')),
  -- For a PDF drawing set whose LENGTHS call died on the edge: the counted take-off the lengths merge into.
  boq_in       jsonb,
  status       text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed')),
  attempts     integer not null default 0,
  claimed_at   timestamptz,
  finished_at  timestamptz,
  result       jsonb,
  error        text
);
create index if not exists cad_read_jobs_open on public.cad_read_jobs (created_at) where status in ('queued', 'running');
create index if not exists cad_read_jobs_customer on public.cad_read_jobs (customer_id, created_at desc);

alter table public.cad_read_jobs enable row level security;
drop policy if exists cad_read_jobs_service_role_only on public.cad_read_jobs;
create policy cad_read_jobs_service_role_only on public.cad_read_jobs
  as permissive for all to public using (false) with check (false);
revoke all on public.cad_read_jobs from anon, authenticated;

-- Claim up to p_limit jobs: queued ones, and running ones whose runner went silent 30 minutes ago.
-- A job already tried three times is failed instead of claimed again, with the reason kept.
create or replace function public.fn_cad_read_claim(p_limit integer default 3)
returns setof public.cad_read_jobs
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  update public.cad_read_jobs j
     set status = 'failed', finished_at = now(),
         error = coalesce(j.error, 'the reader stopped three times without finishing')
   where j.status in ('queued', 'running') and j.attempts >= 3
     and (j.status = 'queued' or j.claimed_at < now() - interval '30 minutes');
  return query
  update public.cad_read_jobs j
     set status = 'running', attempts = j.attempts + 1, claimed_at = now()
   where j.id in (
     select c.id from public.cad_read_jobs c
      where c.attempts < 3
        and (c.status = 'queued' or (c.status = 'running' and c.claimed_at < now() - interval '30 minutes'))
      order by c.created_at
      limit greatest(1, least(coalesce(p_limit, 3), 10))
      for update skip locked)
  returning j.*;
end;
$fn$;
revoke execute on function public.fn_cad_read_claim(integer) from public, anon, authenticated;

-- Verdict row (no DDL is undone by it): the table is closed to anon/authenticated and the claim is
-- callable by nobody but the service role.
select case when
    (select relrowsecurity from pg_class where oid = 'public.cad_read_jobs'::regclass)
    and not has_table_privilege('anon', 'public.cad_read_jobs', 'select')
    and not has_table_privilege('authenticated', 'public.cad_read_jobs', 'select')
    and not has_function_privilege('anon', 'public.fn_cad_read_claim(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.fn_cad_read_claim(integer)', 'execute')
  then 'PROBE OK' else 'PROBE FAILED' end as verdict;
