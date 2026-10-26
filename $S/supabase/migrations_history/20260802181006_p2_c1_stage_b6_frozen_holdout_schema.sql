-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802181006   name: p2_c1_stage_b6_frozen_holdout_schema
-- SHA-256 of the applied SQL: f0e8659ea527ea7f4e5e538490724fe5aa2976392a00fdc7a7dee692cef445e3
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- P2-C1 STAGE B.6 (1/n) - THE FROZEN BILINGUAL HOLDOUT, created and checksummed BEFORE any
-- interpretation code is written. That order is the whole point: a holdout authored after the
-- implementation measures the implementation's opinion of itself.
--
-- Expected outcomes are immutable by trigger. The only legitimate way to change one is through the
-- existing P2-C5 expectation-change controls, which demand a reason, a work item and a person.

create table if not exists public.p2c1_holdout_case (
  case_key           text primary key,
  category           text not null,
  text_en            text,
  text_ar            text,
  expect_active      text[] not null default '{}',
  expect_dispositions jsonb not null default '{}'::jsonb,
  expect_components  jsonb not null default '{}'::jsonb,
  expect_clarify     boolean not null default false,
  expect_conflict    boolean not null default false,
  note               text,
  frozen_at          timestamptz not null default now()
);
alter table public.p2c1_holdout_case enable row level security;

comment on table public.p2c1_holdout_case is
  'Frozen paired English/Arabic holdout. expect_* columns are immutable: a suite whose expectations can be edited to match the code is not a holdout, it is a mirror.';

create table if not exists public.p2c1_holdout_seal (
  id           integer primary key default 1 check (id = 1),
  case_count   integer not null,
  checksum_sha text not null,
  sealed_at    timestamptz not null default now(),
  sealed_by    text not null,
  note         text
);
alter table public.p2c1_holdout_seal enable row level security;

create or replace function public.trg_holdout_expectations_immutable()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    if coalesce(current_setting('quotesdone.holdout_change', true),'') = 'approved' then return old; end if;
    raise exception 'holdout case % cannot be deleted', old.case_key
      using hint = 'Use the P2-C5 expectation-change controls. A holdout that can be quietly pruned proves nothing.';
  end if;
  if coalesce(current_setting('quotesdone.holdout_change', true),'') = 'approved' then return new; end if;
  if new.expect_active       is distinct from old.expect_active
     or new.expect_dispositions is distinct from old.expect_dispositions
     or new.expect_components   is distinct from old.expect_components
     or new.expect_clarify      is distinct from old.expect_clarify
     or new.expect_conflict     is distinct from old.expect_conflict
     or new.text_en             is distinct from old.text_en
     or new.text_ar             is distinct from old.text_ar then
    raise exception 'holdout case % is frozen; its expectation cannot be edited in place', old.case_key
      using hint = 'Changing an expectation to match the code is how a suite stops being evidence.';
  end if;
  return new;
end $fn$;

drop trigger if exists holdout_expectations_immutable on public.p2c1_holdout_case;
create trigger holdout_expectations_immutable before update or delete on public.p2c1_holdout_case
  for each row execute function public.trg_holdout_expectations_immutable();

create or replace function public.fn_p2c1_holdout_checksum()
returns text language sql stable security definer set search_path to 'public' as $fn$
  select encode(extensions.digest(string_agg(
           case_key || '|' || coalesce(text_en,'') || '|' || coalesce(text_ar,'') || '|'
           || array_to_string(expect_active,',') || '|' || expect_dispositions::text || '|'
           || expect_components::text || '|' || expect_clarify::text || '|' || expect_conflict::text,
           E'\n' order by case_key), 'sha256'), 'hex')
    from public.p2c1_holdout_case;
$fn$;

create or replace function public.fn_p2c1_holdout_verify_seal()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare s public.p2c1_holdout_seal%rowtype; v_now text; v_n integer;
begin
  select * into s from public.p2c1_holdout_seal where id = 1;
  if not found then return jsonb_build_object('ok', false, 'error','not_sealed'); end if;
  v_now := public.fn_p2c1_holdout_checksum();
  select count(*) into v_n from public.p2c1_holdout_case;
  return jsonb_build_object('ok', (v_now = s.checksum_sha and v_n = s.case_count),
    'sealed_checksum', s.checksum_sha, 'current_checksum', v_now,
    'sealed_case_count', s.case_count, 'current_case_count', v_n,
    'sealed_at', s.sealed_at, 'sealed_by', s.sealed_by,
    'intact', (v_now = s.checksum_sha and v_n = s.case_count));
end $fn$;

revoke all on function public.fn_p2c1_holdout_checksum() from public, anon, authenticated;
revoke all on function public.fn_p2c1_holdout_verify_seal() from public, anon, authenticated;
;