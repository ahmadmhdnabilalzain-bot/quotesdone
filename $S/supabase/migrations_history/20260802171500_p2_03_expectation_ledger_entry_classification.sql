-- P2-C5 follow-up - the two verification rows must be identifiable, WITHOUT rewriting history.
--
-- The founder is right that the P2-C5 verification left two rows in a ledger meant to record real
-- decisions, and that founder-facing change reports should not show them. The obvious fix - add a
-- column and UPDATE those two rows - is the one thing this table forbids, and disabling the
-- append-only trigger to do it would defeat the control on the second day of its life.
--
-- So history is ANNOTATED, never edited. Annotations are themselves append-only, carry an author
-- and a reason, and live beside the ledger rather than inside it. New entries declare their kind on
-- insert and default to 'change', so the annotation path is only ever needed for rows written
-- before this migration existed.

alter table public.scenario_expectation_change
  add column if not exists entry_kind text not null default 'change';
alter table public.scenario_expectation_change drop constraint if exists sec_entry_kind_chk;
alter table public.scenario_expectation_change add constraint sec_entry_kind_chk
  check (entry_kind in ('change','verification'));

create table if not exists public.scenario_expectation_annotation (
  id           bigserial primary key,
  change_id    bigint not null references public.scenario_expectation_change (id),
  kind         text   not null check (kind in ('change','verification')),
  reason       text   not null check (btrim(reason) <> ''),
  annotated_by text   not null check (btrim(annotated_by) <> ''),
  annotated_at timestamptz not null default now()
);
alter table public.scenario_expectation_annotation enable row level security;

drop trigger if exists expectation_annotation_append_only on public.scenario_expectation_annotation;
create trigger expectation_annotation_append_only before update or delete on public.scenario_expectation_annotation
  for each row execute function public.trg_expectation_ledger_append_only();

comment on table public.scenario_expectation_annotation is
  'Append-only annotations over the expectation ledger. Exists because ledger rows cannot be edited: classifying a historical entry is a new fact about it, not a correction of it.';

insert into public.scenario_expectation_annotation (change_id, kind, reason, annotated_by)
select id, 'verification',
       'Written by the P2-C5 verification suite on 2 Aug 2026 to prove the ledger works. Not a product decision; excluded from founder-facing change reports.',
       'management@quotesdone.com'
  from public.scenario_expectation_change
 where reason in ('MEP umbrella architecture splits this into trade workstreams',
                  'reverting the P2-C5 verification change')
   and not exists (select 1 from public.scenario_expectation_annotation a where a.change_id = scenario_expectation_change.id);

create or replace view public.v_scenario_expectation_ledger as
select c.*,
       coalesce(a.kind, c.entry_kind) as effective_kind,
       a.reason as annotation_reason, a.annotated_by, a.annotated_at
  from public.scenario_expectation_change c
  left join lateral (
    select * from public.scenario_expectation_annotation an
     where an.change_id = c.id order by an.annotated_at desc, an.id desc limit 1
  ) a on true;

create or replace view public.v_scenario_expectation_changes_reportable as
select scenario_id, original_expected, new_expected, reason, work_item, changed_by, changed_at
  from public.v_scenario_expectation_ledger
 where effective_kind = 'change'
 order by changed_at desc;

comment on view public.v_scenario_expectation_changes_reportable is
  'Genuine expectation changes only. Verification and audit entries are annotated out - visible in v_scenario_expectation_ledger, absent from founder-facing reports.';
