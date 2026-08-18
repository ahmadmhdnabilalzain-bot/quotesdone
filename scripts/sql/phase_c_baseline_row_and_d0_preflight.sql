-- PHASE C BASELINE ROW, AND THE TWO AUTHENTICATION CASES OWED TO PHASE D D0.
--
-- Companion to scripts/sql/phase_c_founder_approved_and_frozen.sql. That file recorded the approval
-- and froze the fifteen subjects; this one puts Phase C into public.org_phase_baseline beside
-- Phase A and Phase B so all three approvals are readable from one place, and records the
-- verification debt the founder named.
--
-- Changes no Phase C architecture. Two inserts and one small register.

begin;

-- ---------------------------------------------------------------- 1. the baseline row
insert into public.org_phase_baseline (
  phase, approved_by, approved_at, project_ref, final_commit,
  counts, organization_sha256, registry_sha256, migrations, rollbacks, deferred, note)
select
  'C', 'founder', timestamptz '2026-08-18 11:45:00+00', 'htdblwldjkcgjvmqkbeh',
  'f0f7339d0c39d6dea918d1d24da81f8ff7e09f14',
  jsonb_build_object(
    'components_declared_crosswalk_live', '1801/1801/1801',
    'components_live',              (select count(*) from public.phase_c_component),
    'frozen_subjects',              (select count(*) from public.phase_c_frozen_subject),
    'protected_tables',             (select split_part(a.actual,' of ',1)::int
                                       from public.fn_kernel_truncate_protection_state() a
                                      where a.check_name='raw_enforcing_tables_watched'),
    'truncate_attempts_refused',    '75/75',
    'direct_truncate_accepted',     0,
    'founder_chain',                '30/30',
    'command_acceptance',           '20/20',
    'negative_guard_cases_refused', '58/58',
    'genuine_positive_controls',    '13/13',
    'canonical_kernel_entry_doors', (select count(*) from public.kernel_write_authority a
                                      where not exists (select 1 from public.kernel_retired_path p
                                                         where p.path_name = a.routine_name)),
    'canonical_routines',           1022,
    'edge_functions_at_parity',     202,
    'phase_a_drift',                (select count(*) from public.fn_phase_a_baseline_drift()),
    'phase_b_drift',                (select count(*) from public.fn_phase_b_baseline_drift()),
    'phase_c_drift',                (select count(*) from public.fn_phase_c_baseline_drift()),
    'phase_d_profile',              '300/300 on two consecutive runs',
    'openrouter_http_requests',     0,
    'paid_inference_cost_usd',      '0.00',
    'live_external_effects',        0,
    'unresolved_phase_c_defects',   0),
  -- The Phase C fingerprint, quoted from the approval record rather than recomputed, so the two
  -- rows can be checked against each other instead of each agreeing with itself.
  (select phase_c_fingerprint from public.phase_c_founder_approval where approval_id='PCA-2026-08-18-001'),
  jsonb_build_object(
    'approval_record',            'PCA-2026-08-18-001',
    'audit_report',               'PHASE_C_IMMUTABLE_CLOSURE_AUDIT_2026-08-18.md',
    'audit_sha256',               'c7eed77aef879e21ab96d1b11d6db7f97ba844c0ceae5c8ac687f7d51ad5dd58',
    'component_crosswalk_sha256', '46cb7165c46ade1615d86df0eb9460dffaddd171a561882b9ad4c55d9e9c66d7',
    'routine_manifest_sha256',    'd84ede4cfe60f401a1e82b84dd22c915f08ac28d60ba7ef36cbaec3d6b25d608',
    'full_schema_sha256',         '875c488ffc4e25f949865fafa47c55b0073f235a0c8c34119c146633458f4abb',
    'edge_parity_sha256',         '2a6c6b840e321ae7722b1d4d078ca50e35d6c0c8e6b9f09f494564ea3fab43ea'),
  jsonb_build_array(
    'scripts/sql/the_truncate_protection_was_a_typed_list.sql',
    'scripts/sql/phase_c_founder_approved_and_frozen.sql',
    'scripts/sql/phase_c_baseline_row_and_d0_preflight.sql'),
  jsonb_build_object(
    'tag',                'phase-c-founder-approved-2026-08-18',
    'commit',             'f0f7339d0c39d6dea918d1d24da81f8ff7e09f14',
    'previous_main',      'e753505095e72eec79026b99c444953cfe65fd3a',
    'phase_a_tag',        'phase-a-founder-approved-2026-08-15',
    'phase_b_tag',        'phase-b-founder-approved-2026-08-15'),
  jsonb_build_array(
    jsonb_build_object('item','valid enabled founder JWT -> success',
                       'owner','Phase D D0 preflight','kind','verification debt'),
    jsonb_build_object('item','valid non-founder JWT -> 403',
                       'owner','Phase D D0 preflight','kind','verification debt')),
  'Founder approved Phase C on 18 Aug 2026 on the independent immutable closure audit, which was '
  'performed READ-ONLY against main f0f7339 and production htdblwldjkcgjvmqkbeh by a session that '
  'did not implement the fix it was auditing. Applied by the production-direct protocol '
  '(scripts/apply_sql.mjs posts the committed bytes and reads the definitions back), NOT by the '
  'Supabase migration runner, so these versions are deliberately absent from '
  'supabase_migrations.schema_migrations; the file digest is the version that means anything. '
  'Fifteen subjects are frozen in public.phase_c_frozen_subject and checked by '
  'public.fn_phase_c_freeze_drift(), which is a GATE board rather than a ratchet. That mechanism is '
  'DETECTIVE, not preventive: a trigger cannot fire on CREATE OR REPLACE FUNCTION, so a frozen '
  'routine can still be edited — it simply cannot be shipped, because the board fails CI and every '
  'pull request. TWO THINGS THIS APPROVAL DOES NOT CLAIM. First, the two founder-JWT authentication '
  'cases in "deferred" were never executed against production; they need minted sessions, which the '
  'read-only audit refused to create, and they are owed at Phase D D0 as verification debt, not as '
  'permission to reopen Phase C. Second, seven board checks are red by disclosure and remain so: '
  'each is a recorded ratchet in scripts/checks/kernel-boards.json, at or below its baseline, and '
  'they are open debt rather than hidden failure. The selective automation hold is unchanged by '
  'this approval: kernel infrastructure and read-only monitoring stay active, and business '
  'automation, notifications, social publishing, payment and refund execution, external provider '
  'effects and all paid AI stay HELD.'
where not exists (select 1 from public.org_phase_baseline where phase = 'C');

-- ---------------------------------------------------------------- 2. Phase D D0 preflight debt
--
-- Deliberately NOT a board. A board with an outstanding row would be red, and
-- kernel_boards_are_green treats an unratcheted red as a failure — which would turn honest,
-- founder-acknowledged verification debt into a broken Phase C gate. This is a register that
-- Phase D D0 reads, not a check that Phase C must satisfy.
create table if not exists public.phase_d_preflight_requirement (
  requirement_id text        primary key,
  phase_gate     text        not null,
  requirement    text        not null,
  expected       text        not null,
  why_not_done   text        not null,
  status         text        not null default 'OUTSTANDING'
                 check (status in ('OUTSTANDING','SATISFIED')),
  raised_by      text        not null,
  raised_at      timestamptz not null default now(),
  satisfied_at   timestamptz,
  evidence       text
);

comment on table public.phase_d_preflight_requirement is
  'Verification owed before Phase D deterministic work begins. Raised by the founder when he '
  'approved Phase C on 18 Aug 2026. These are things not yet PROVEN, never permission to reopen or '
  'redesign what Phase C froze.';

insert into public.phase_d_preflight_requirement
  (requirement_id, phase_gate, requirement, expected, why_not_done, raised_by)
values
  ('D0-AUTH-001','Phase D D0',
   'valid enabled founder JWT reaches the Command Center',
   'success (2xx) for an identity that is active in public.phase_c_founder_identity',
   'The independent closure audit was read-only and declined to mint a production authentication '
   'session. The five unauthenticated shapes were all proved to return 401, and build-mode identity '
   'is inactive, but the positive case was never executed.',
   'founder, on Phase C approval 2026-08-18'),
  ('D0-AUTH-002','Phase D D0',
   'valid non-founder JWT is refused by the Command Center',
   '403 for a real signed-in identity that is not in public.phase_c_founder_identity',
   'Same reason: proving it needs a real non-founder session. The branch exists and was read at '
   'supabase/functions/os_api/index.ts:186, but reading a branch is not executing it.',
   'founder, on Phase C approval 2026-08-18')
on conflict (requirement_id) do nothing;

commit;
