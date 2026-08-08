-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260802162637   name: p2_02_scenario_expectation_change_ledger
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- P2-C5 - THE EXPECTATION LEDGER. APPEND-ONLY, AND ENFORCED BY THE DATABASE.
--
-- Taken out of the stated order deliberately: P2-C1 will change what some MEP scenarios expect, and
-- the rule is that any such change carries its original, its replacement, a reason and an approving
-- work item. The ledger therefore has to exist BEFORE the thing that writes to it. Building MEP
-- first would mean the first expectation changes are made with nowhere to record them - exactly the
-- silent edit this control exists to prevent. Nothing here touches routing.
--
-- A rule in a document is obeyed until the night someone is tired and the suite is red. `expected`
-- is now unwritable in place; the only path is fn_scenario_expectation_change, which will not run
-- without a reason, a real work item and a person.
--
-- Two shape notes. scenario_tests.expected is TEXT, so the ledger stores text - normalising into
-- jsonb would mean a comparison that can silently reformat, and therefore silently differ. And
-- work_item is validated by trigger rather than a foreign key, because only 7 of 193 spec_backlog
-- rows carry a spec_ref: a partial unique index cannot back an FK, and making spec_ref mandatory on
-- 186 unrelated legacy rows to satisfy one constraint would be the tail wagging the dog.

create unique index if not exists spec_backlog_spec_ref_uidx
  on public.spec_backlog (spec_ref) where spec_ref is not null;

create table if not exists public.scenario_expectation_baseline (
  scenario_id   text primary key,
  expected      text not null,
  expected_sha  text not null,
  captured_at   timestamptz not null default now()
);

insert into public.scenario_expectation_baseline (scenario_id, expected, expected_sha)
select s.scenario_id, coalesce(s.expected, ''),
       encode(extensions.digest(coalesce(s.expected, ''), 'sha256'), 'hex')
  from kb_stage.scenario_tests s
on conflict (scenario_id) do nothing;

create table if not exists public.scenario_expectation_change (
  id                bigserial primary key,
  scenario_id       text not null,
  original_expected text not null,
  new_expected      text not null,
  reason            text not null,
  work_item         text not null,
  changed_by        text not null,
  changed_at        timestamptz not null default now(),
  constraint sec_reason_not_blank     check (btrim(reason) <> ''),
  constraint sec_work_item_not_blank  check (btrim(work_item) <> ''),
  constraint sec_changed_by_not_blank check (btrim(changed_by) <> ''),
  constraint sec_actually_changed     check (original_expected is distinct from new_expected)
);
create index if not exists scenario_expectation_change_scenario_idx
  on public.scenario_expectation_change (scenario_id, changed_at desc);
alter table public.scenario_expectation_change enable row level security;
alter table public.scenario_expectation_baseline enable row level security;

comment on table public.scenario_expectation_change is
  'Append-only. Every change to a scenario expectation: what it was, what it became, why, under which work item, by whom. UPDATE and DELETE are refused by trigger.';

create or replace function public.trg_expectation_ledger_append_only()
returns trigger language plpgsql as $fn$
begin
  raise exception 'scenario_expectation_change is append-only: % is not permitted.', tg_op
    using hint = 'The point of this table is that history cannot be rewritten. Record a new change instead.';
end $fn$;

drop trigger if exists expectation_ledger_no_update on public.scenario_expectation_change;
create trigger expectation_ledger_no_update before update or delete on public.scenario_expectation_change
  for each row execute function public.trg_expectation_ledger_append_only();

drop trigger if exists expectation_baseline_immutable on public.scenario_expectation_baseline;
create trigger expectation_baseline_immutable before update or delete on public.scenario_expectation_baseline
  for each row execute function public.trg_expectation_ledger_append_only();

create or replace function public.trg_expectation_work_item_real()
returns trigger language plpgsql as $fn$
begin
  if not exists (select 1 from public.spec_backlog where spec_ref = new.work_item) then
    raise exception 'work_item % does not resolve to a tracked item in spec_backlog', new.work_item
      using hint = 'Open the work item first. An expectation change approved by nothing is approved by nobody.';
  end if;
  return new;
end $fn$;

drop trigger if exists expectation_work_item_real on public.scenario_expectation_change;
create trigger expectation_work_item_real before insert on public.scenario_expectation_change
  for each row execute function public.trg_expectation_work_item_real();

create or replace function public.trg_scenario_expected_needs_ledger()
returns trigger language plpgsql as $fn$
begin
  if new.expected is distinct from old.expected
     and coalesce(current_setting('quotesdone.expectation_change', true), '') <> 'approved' then
    raise exception 'scenario_tests.expected cannot be changed directly (scenario %)', old.scenario_id
      using hint = 'Use public.fn_scenario_expectation_change(scenario_id, new_expected, reason, work_item, changed_by).';
  end if;
  return new;
end $fn$;

drop trigger if exists scenario_expected_needs_ledger on kb_stage.scenario_tests;
create trigger scenario_expected_needs_ledger before update on kb_stage.scenario_tests
  for each row execute function public.trg_scenario_expected_needs_ledger();

create or replace function public.fn_scenario_expectation_change(
  p_scenario_id text, p_new_expected text, p_reason text, p_work_item text, p_changed_by text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_current text; v_id bigint;
begin
  if coalesce(btrim(p_reason),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'reason_required',
      'message', 'An expectation change without a written reason is a silent edit with extra steps.');
  end if;
  if coalesce(btrim(p_changed_by),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'changed_by_required');
  end if;
  if not exists (select 1 from public.spec_backlog where spec_ref = p_work_item) then
    return jsonb_build_object('ok', false, 'error', 'unknown_work_item',
      'message', 'work_item must resolve to a tracked item in spec_backlog. Open one first.');
  end if;

  select expected into v_current from kb_stage.scenario_tests where scenario_id = p_scenario_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_scenario'); end if;
  if coalesce(v_current,'') is not distinct from coalesce(p_new_expected,'') then
    return jsonb_build_object('ok', false, 'error', 'no_change');
  end if;

  insert into public.scenario_expectation_change
    (scenario_id, original_expected, new_expected, reason, work_item, changed_by)
  values (p_scenario_id, coalesce(v_current,''), coalesce(p_new_expected,''), btrim(p_reason), p_work_item, btrim(p_changed_by))
  returning id into v_id;

  perform set_config('quotesdone.expectation_change', 'approved', true);
  update kb_stage.scenario_tests set expected = p_new_expected where scenario_id = p_scenario_id;
  perform set_config('quotesdone.expectation_change', '', true);

  return jsonb_build_object('ok', true, 'ledger_id', v_id, 'scenario_id', p_scenario_id, 'work_item', p_work_item);
end $fn$;

create or replace view public.v_scenario_expectation_current as
select b.scenario_id, b.expected as original_expected,
       coalesce(c.new_expected, b.expected) as current_expected,
       (c.id is not null) as revised,
       c.reason, c.work_item, c.changed_by, c.changed_at
  from public.scenario_expectation_baseline b
  left join lateral (
    select * from public.scenario_expectation_change ch
     where ch.scenario_id = b.scenario_id order by ch.changed_at desc, ch.id desc limit 1
  ) c on true;

create or replace function public.fn_scenario_verdict(p_scenario_id text, p_actual text)
returns text language sql stable security definer set search_path to 'public' as $fn$
  select case
    when coalesce(p_actual,'') is not distinct from
         (select coalesce(original_expected,'') from public.v_scenario_expectation_current where scenario_id = p_scenario_id)
      then 'pass_original'
    when coalesce(p_actual,'') is not distinct from
         (select coalesce(current_expected,'')  from public.v_scenario_expectation_current where scenario_id = p_scenario_id)
      then 'pass_revised'
    else 'fail' end;
$fn$;

create or replace view public.v_scenario_expectation_drift as
select s.scenario_id, b.expected as baseline_expected, s.expected as live_expected
  from kb_stage.scenario_tests s
  join public.scenario_expectation_baseline b on b.scenario_id = s.scenario_id
 where coalesce(s.expected,'') is distinct from coalesce(b.expected,'')
   and not exists (select 1 from public.scenario_expectation_change c
                    where c.scenario_id = s.scenario_id and c.new_expected = coalesce(s.expected,''));

revoke all on function public.fn_scenario_expectation_change(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.fn_scenario_verdict(text, text) from public, anon, authenticated;
