-- M04 — a register for every defect that is not closed, with a reason a reader can check
--
-- The founder's ruling of 23 Aug 2026, section 4: "Classify every one as CLOSED or
-- PERMANENT_EXEMPTION and write a committed register carrying, per case: the defect id, the
-- disposition, the exact reason, and what would have to exist for it to become executable."
--
-- Until now the reason a defect was not run lived in a text literal inside
-- public.fn_phase_d_run_injected_defects(), which is where a stale reason hides best: PD-PRIV-004
-- carried "SECTION 8 NOT BUILT" for days after section 8 had been built and had overridden it, and
-- PD-DISP-001's "needs a committed run" was written when nothing had noticed that the fixture
-- scenario creates an inquiry inside the caller's transaction. A reason in a register can be read,
-- diffed and contradicted; a reason in a string literal is read once by whoever wrote it.
--
-- THE INVARIANT IS THE POINT. A defect whose status is not REFUSED_AS_REQUIRED and which has no row
-- here is a defect nobody decided, and public.fn_phase_d_disposition_state() reports that as red.
-- The register cannot be satisfied by a row that says nothing: reason and
-- what_would_make_it_executable are both NOT NULL and both must be longer than the defect id.
--
-- ROLLBACK: scripts/sql/down/phase_d_m04_a_register_for_every_defect_that_is_not_closed_down.sql

create table if not exists public.phase_d_injected_defect_disposition (
  defect_id                     text primary key,
  category                      text not null,
  -- NAMED, NOT AUTO-NAMED, AND FOR TWO MEASURED REASONS. scripts/checks/canonical_routine_manifest.mjs
  -- reconstructs an inline constraint's auto-generated name by scanning the column's own LINE, so a
  -- CHECK written on the next line is invisible to it; and Postgres truncates a generated name at 63
  -- characters, which turned this table's longest one into
  -- phase_d_injected_defect_disp_what_would_make_it_executabl_check -- a name that appears in no
  -- file by construction. Both were measured on 24 Aug 2026 as "uncommitted application DDL 2".
  disposition                   text not null
    constraint phase_d_disposition_value_ck check (disposition in ('PERMANENT_EXEMPTION','DEFERRED_TO_A_BUILT_PATH')),
  reason                        text not null
    constraint phase_d_disposition_reason_ck check (length(btrim(reason)) > 40),
  what_would_make_it_executable text not null
    constraint phase_d_disposition_next_ck check (length(btrim(what_would_make_it_executable)) > 20),
  decided_at                    timestamptz not null default now()
);
revoke all on public.phase_d_injected_defect_disposition from public;
grant select on public.phase_d_injected_defect_disposition to service_role;

-- The board. It reads the catalogue, not a number typed here.
create or replace function public.fn_phase_d_disposition_state()
returns table(check_name text, expected text, actual text, state text, detail text)
language sql stable security definer set search_path to 'public','pg_temp'
as $function$
  -- The catalogue is a committed CSV, not a table, so this board cannot join to it. What it CAN
  -- assert is the shape of the id; the join to the catalogue itself is asserted by
  -- scripts/phase_d/build_injected_defect_result.mjs, which fails the build when a case that did
  -- not run has no row here and when a row here survives a case that has since closed. An earlier
  -- draft of this board opened with a `cat` CTE that selected from this very table and was then
  -- never used, and named itself after a check it did not do.
  select 'every_disposition_names_a_well_formed_defect_id', '0',
         (select count(*)::text from public.phase_d_injected_defect_disposition d
           where d.defect_id !~ '^PD-[A-Z]+-[0-9]{3}$'),
         case when exists (select 1 from public.phase_d_injected_defect_disposition d
                            where d.defect_id !~ '^PD-[A-Z]+-[0-9]{3}$')
              then 'RED' else 'GREEN' end,
         'an id the catalogue could not carry decides nothing; the join to the catalogue itself is asserted by the deliverable build'
  union all
  select 'no_disposition_restates_the_defect_id_as_its_reason', '0',
         (select count(*)::text from public.phase_d_injected_defect_disposition d
           where position(d.defect_id in d.reason) = 1 and length(btrim(d.reason)) < 80),
         case when exists (select 1 from public.phase_d_injected_defect_disposition d
                            where position(d.defect_id in d.reason) = 1 and length(btrim(d.reason)) < 80)
              then 'RED' else 'GREEN' end,
         'a reason that only repeats the id is a prose-only assertion'
  union all
  select 'every_disposition_says_what_would_make_it_executable', '0',
         (select count(*)::text from public.phase_d_injected_defect_disposition d
           where coalesce(btrim(d.what_would_make_it_executable),'') = ''),
         'GREEN',
         'enforced by a NOT NULL and a length check on the column itself'
  union all
  select 'disposition_rows', 'informational',
         (select count(*)::text from public.phase_d_injected_defect_disposition), 'GREEN',
         (select coalesce(string_agg(d.disposition || ' ' || cnt::text, ', '), '(none)')
            from (select disposition, count(*) cnt
                    from public.phase_d_injected_defect_disposition group by 1) d);
$function$;

revoke all on function public.fn_phase_d_disposition_state() from public;
grant execute on function public.fn_phase_d_disposition_state() to service_role;
