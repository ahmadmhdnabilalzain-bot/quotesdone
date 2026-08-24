-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d6_handler_status_is_measured.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads what is destroyed below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   column public.phase_d_handler_binding.business_write_wired
--   (boolean not null default false; attnum 29 on production)
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   No rows are deleted. public.phase_d_handler_binding keeps all 257 rows; each loses one boolean.
--   business_write_wired is a MEASURED value — d6 wrote it from whether the binding's handler
--   actually reaches a business write — so it is not recoverable by retyping. It is recoverable by
--   re-running d6, which measures it again.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d6, fn_phase_d_handler_state(). A
-- create-or-replace has no down — see scripts/sql/down/README.md. That board reads
-- business_write_wired, so after this rollback it raises on a missing column. Expected.
-- =================================================================================================


alter table public.phase_d_handler_binding
  drop column if exists business_write_wired;

do $ctl$
begin
  if exists (
    select 1
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'phase_d_handler_binding'
       and a.attname = 'business_write_wired'
       and a.attnum > 0
       and not a.attisdropped
  ) then
    raise exception 'D6 down did not take: phase_d_handler_binding.business_write_wired is still present.';
  end if;

  raise notice 'D6 down: phase_d_handler_binding.business_write_wired is gone; all binding rows survive.';
end $ctl$;

