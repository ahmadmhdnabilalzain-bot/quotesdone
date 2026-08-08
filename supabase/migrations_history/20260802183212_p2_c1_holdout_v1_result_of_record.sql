-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802183212   name: p2_c1_holdout_v1_result_of_record
-- SHA-256 of the applied SQL: 33be6f4351e857f32d5ab795d2b23689b3dabafa3d6bec8d280ec6d527ee1a75
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- HOLDOUT V1 - RESULT OF RECORD, and its demotion.
--
-- v1 has now been measured against and its failures inspected. From this point it is a REGRESSION
-- suite, not an independent holdout: its power to surprise us is spent. v2 must be authored and
-- sealed in a separate session that has not seen the implementation.
--
-- Also recorded here: a correction to how v1 was reported. "Disposition agreement 54/54" measured
-- ENGLISH-vs-ARABIC PARITY, not agreement with the expectation. Case x09 returned by_others in both
-- languages against an expectation of excluded - identical, therefore "agreeing", and wrong twice.
-- Undetected trades are invisible to that metric too: the comparison string is built only from
-- non-`included` dispositions, so a trade that was never detected contributes nothing and two empty
-- strings compare equal. A parity metric cannot see a symmetric error. v2 must report agreement
-- with the EXPECTATION per trade, with an explicit denominator, alongside parity.

create table if not exists public.p2c1_holdout_result_of_record (
  holdout_version    text primary key,
  checksum_sha       text not null,
  case_count         integer not null,
  cases_passed       integer not null,
  false_positives    integer not null,
  false_negatives    integer not null,
  trade_set_parity   integer,
  disposition_parity integer,
  component_parity   integer,
  clarify_parity     integer,
  conflicts_correct  integer,
  status             text not null check (status in ('independent_holdout','regression_suite')),
  recorded_at        timestamptz not null default now(),
  note               text not null
);
alter table public.p2c1_holdout_result_of_record enable row level security;

create or replace function public.trg_holdout_record_immutable()
returns trigger language plpgsql as $fn$
begin
  raise exception 'holdout result of record is immutable: % is not permitted', tg_op
    using hint = 'The first measurement of a holdout happens once. Re-running it later is a regression run, not a new first result.';
end $fn$;
drop trigger if exists holdout_record_immutable on public.p2c1_holdout_result_of_record;
create trigger holdout_record_immutable before update or delete on public.p2c1_holdout_result_of_record
  for each row execute function public.trg_holdout_record_immutable();

insert into public.p2c1_holdout_result_of_record
 (holdout_version, checksum_sha, case_count, cases_passed, false_positives, false_negatives,
  trade_set_parity, disposition_parity, component_parity, clarify_parity, conflicts_correct,
  status, note)
values ('v1','cfb06e11e05b0645527a0ecc9cbded37273eab342826ce34fff1d7bd651fb089',
        54, 49, 0, 5, 51, 54, 54, 52, 54, 'regression_suite',
        'FIRST AND ONLY INDEPENDENT EVALUATION: 49/54, 0 false positives, 5 false negatives. Note the initial run before the m04 clause-boundary fix was 48/54 with 3 false positives; the fix closed a genuine defect (a full-scope modifier reaching an MEP anchor across a full stop) and false positives went to 0. Verdicts at time of record: PASS 49, PARITY_MISMATCH 3, DISPOSITION_MISMATCH 1, COMPONENT_MISMATCH 1. The parity columns measure EN-vs-AR agreement, NOT agreement with the expectation - x09 was wrong identically in both languages and still counted as parity. Demoted to regression suite because its failures have been inspected.')
on conflict (holdout_version) do nothing;

comment on table public.p2c1_holdout_result_of_record is
  'Immutable. One row per holdout version, written once at its first evaluation. A holdout measures an implementation exactly once; every later run is regression.';
;