-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d11_two_hundred_and_seventy_three_events_that_have_never_happened.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   public.phase_d_event_reconciliation — 23 columns, event_id text primary key, with
--   phase_d_event_reconciliation_factual_ck, _runtime_ck, and
--   phase_d_event_reconciliation_event_fkey -> public.phase_b_event(event_id) ON DELETE CASCADE
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.3 "Data at risk on a drop" and
-- D.1 item 17):
--   public.phase_d_event_reconciliation   347 rows — one per frozen Phase B event. The event ids
--   survive in public.phase_b_event; the reconciliation verdict for each — whether the event has a
--   producer, a consumer, a binding that is factual rather than declared — does not.
--
--   Note the file name says 273 and the table holds 347. Both are real: 273 is the count the file
--   was written about; 347 is what the table holds now, and it is the number this rollback destroys.
--
-- KNOWN CONSUMER: scripts/phase_d/build_handoff_event_result.mjs reads this table for the 347 event
-- rows of docs/phase-d/PHASE_D_HANDOFF_EVENT_RESULT.csv. After this rollback that builder fails its
-- count guard. Expected.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d11. A create-or-replace has no down —
-- see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop table if exists public.phase_d_event_reconciliation;

do $ctl$
begin
  if to_regclass('public.phase_d_event_reconciliation') is not null then
    raise exception 'D11 down did not take: public.phase_d_event_reconciliation is still present.';
  end if;

  raise notice 'D11 down: phase_d_event_reconciliation is gone, and with it 347 reconciliation verdicts.';
end $ctl$;

commit;
