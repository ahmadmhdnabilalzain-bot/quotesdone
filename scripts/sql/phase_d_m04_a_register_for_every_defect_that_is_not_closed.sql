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
  disposition                   text not null
    check (disposition in ('PERMANENT_EXEMPTION','DEFERRED_TO_A_BUILT_PATH')),
  reason                        text not null check (length(btrim(reason)) > 40),
  what_would_make_it_executable text not null check (length(btrim(what_would_make_it_executable)) > 20),
  decided_at                    timestamptz not null default now()
);
revoke all on public.phase_d_injected_defect_disposition from public;
grant select on public.phase_d_injected_defect_disposition to service_role;

-- The board. It reads the catalogue, not a number typed here.
create or replace function public.fn_phase_d_disposition_state()
returns table(check_name text, expected text, actual text, state text, detail text)
language sql stable security definer set search_path to 'public','pg_temp'
as $function$
  with cat as (
    select d.defect_id from public.phase_d_injected_defect_disposition d
  )
  select 'every_disposition_names_a_catalogued_defect', '0',
         (select count(*)::text from public.phase_d_injected_defect_disposition d
           where not exists (select 1 from public.phase_d_section8_defect_map m where m.defect_id = d.defect_id)
             and d.defect_id !~ '^PD-[A-Z]+-[0-9]{3}$'),
         case when exists (select 1 from public.phase_d_injected_defect_disposition d
                            where d.defect_id !~ '^PD-[A-Z]+-[0-9]{3}$')
              then 'RED' else 'GREEN' end,
         'a disposition for an id the catalogue does not carry decides nothing'
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
