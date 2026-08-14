-- A score with no history cannot tell you what moved.
--
-- 14 Aug 2026: Row #3 read 136/152 at the start of a session and 135/152 at the end, and the
-- question "which check changed" was unanswerable — the scorer printed its verdicts and kept
-- none of them, and no artefact in the repository holds a per-check list from a previous run.
-- Both numbers were true and the difference between them was lost.
--
-- Every blueprint run now writes one row per check. The diff becomes a query.
create table if not exists os_blueprint_result (
  run_id     uuid not null default gen_random_uuid(),
  run_at     timestamptz not null default now(),
  spec_file  text not null,          -- 'row3_executive_ui' | 'row4_customer_portal'
  ref        text not null,          -- the project the run measured
  check_id   text not null,
  ok         boolean not null,
  name       text,
  evidence   text,
  primary key (run_id, check_id)
);
create index if not exists os_blueprint_result_run on os_blueprint_result (spec_file, ref, run_at desc);
alter table os_blueprint_result enable row level security;

-- What changed between the two most recent runs of one spec on one project. Returns nothing
-- when the run is the first — which is a true answer, not a green one.
create or replace function fn_blueprint_regressions(p_spec text, p_ref text)
returns table (check_id text, name text, was boolean, now_ boolean, direction text, evidence text)
language sql stable security definer set search_path = public as $$
  with runs as (
    select distinct run_id, run_at from os_blueprint_result
     where spec_file = p_spec and ref = p_ref order by run_at desc limit 2
  ), newest as (select * from os_blueprint_result where run_id = (select run_id from runs order by run_at desc limit 1)),
     prev   as (select * from os_blueprint_result where run_id = (select run_id from runs order by run_at asc  limit 1))
  select n.check_id, n.name, p.ok, n.ok,
         case when p.ok and not n.ok then 'REGRESSED'
              when not p.ok and n.ok then 'FIXED'
              else 'unchanged' end,
         n.evidence
    from newest n
    join prev p using (check_id)
   where (select count(*) from runs) = 2
     and p.ok is distinct from n.ok
   order by 5, 1;
$$;
revoke all on function fn_blueprint_regressions(text, text) from public;

-- Keep a quarter of history and no more; the value is in the recent diff, not in the archive.
create or replace function fn_blueprint_result_prune() returns integer
language sql security definer set search_path = public as $$
  with d as (delete from os_blueprint_result where run_at < now() - interval '90 days' returning 1)
  select count(*)::int from d;
$$;
revoke all on function fn_blueprint_result_prune() from public;
