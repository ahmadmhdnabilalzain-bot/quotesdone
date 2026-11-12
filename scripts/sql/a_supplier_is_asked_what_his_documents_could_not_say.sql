-- A SUPPLIER IS ASKED WHAT HIS DOCUMENTS COULD NOT SAY (12 Nov 2026, sales_engineer; built by it_engineer).
-- Seat: sales_engineer. Founder rulings 1647 ("where the profile is not straightforward the agent gets specific": the
-- recruitment company is asked "what sort of staff"; a decoration company's pools "through a subcontractor"), 1628 (the AI
-- proposes, the supplier confirms, matching is code over confirmed keys) and 1645 (his standard for every screen). Design:
-- docs/reports/2026-11-12-supplier-service-profiling.md 3.8 (the questions are a record, not a screen) and 3.10; slice 4.
--
-- MEASURED (12 hard profiles, 12 Nov 2026): the supplier was asked 0 questions in 18 readings, and every service a profile
-- said goes through a partner was dropped (22 of 22). Reader @5 (supplier_profile_reading.proposalOf) now DRAFTS the
-- questions; this file is where they are kept, answered and remembered.
--
-- WHAT THIS ADDS:
--   1. public.supplier_service_question: one row per question put to one supplier (kind, his sentence in `about`, the English
--      prompt, the options fixed at reading time, open / later / answered / skipped / expired, his answer). UNIQUE on
--      (supplier_id, kind, about_hash), so a re-read of the same documents never asks the same question twice
--      (_shared/supplier_service_questions.ts storeQuestions inserts on that key and ignores a duplicate). A supplier never
--      reads it directly: only supplier_api, which resolves his id from his own session (actions services_questions and
--      services_answer). RLS on with the estate's service-role-only policy; revoked from anon and authenticated.
--   2. supplier_capabilities.services_partner text[] not null default '{}': the confirmed services (a SUBSET of services) he
--      delivers through a partner. THE SAME COLUMN, SAME DEFINITION, is added by
--      a_partner_service_is_matched_knowingly.sql (the matcher, slice 5); `add column if not exists` in both makes the two
--      files independent of each other's order. THE SUBSET RULE IS ENFORCED WHERE IT IS WRITTEN: capabilityConfirm (the one
--      writer, _shared/supplier_capability.ts) keeps only partner keys that are in the services it writes, and the probe
--      proves no row breaks it. It is not a CHECK constraint on purpose: the matcher's probe writes a partner key that is not
--      in services, in its rolled-back transaction, to prove such a key matches nothing, and a constraint would refuse it.
--   3. The export registry row for the new table (a supplier record, exported).
-- No routine is created or changed.
--
-- APPLY WITH: node scripts/apply_sql.mjs scripts/sql/a_supplier_is_asked_what_his_documents_could_not_say.sql --apply --ddl
-- LOCKS: the ALTER takes ACCESS EXCLUSIVE on supplier_capabilities, and the foreign key a SHARE ROW EXCLUSIVE on leads.
--   Queued behind a long reader either would block the matcher and sign-in, so the file starts with lock_timeout 3 s: it
--   fails fast instead, and is simply applied again.
-- ORDER: apply BEFORE deploying this branch's functions, the four whose import graph reaches supplier_doc_trades.ts,
--   supplier_capability.ts, supplier_services.ts or supplier_service_questions.ts: supplier_api, supplier_portal, supplier_catalog_ingest
--   and sales_engineer (they write services_partner and the question rows). The matcher's functions
--   (sales_engineer, customer_api from a_partner_service_is_matched_knowingly) must be live before the first services_partner
--   is written, because they strip the partner detail from what a customer can read.
-- prevented by: scripts/sql/a_supplier_is_asked_what_his_documents_could_not_say_probe.sql (rolled back, ZZ DEMO only),
--               supabase/functions/_shared/supplier_service_questions.test.ts,
--               scripts/checks/a_supplier_is_asked_never_assumed.test.mjs.

set local lock_timeout = '3s';

alter table public.supplier_capabilities add column if not exists services_partner text[] not null default '{}';
comment on column public.supplier_capabilities.services_partner is
  'sales_engineer: the confirmed services (a subset of services) he delivers through a partner, not his own team; matched after own-team suppliers (fn_match_capability partner_hits).';

create table if not exists public.supplier_service_question (
  id           bigint generated always as identity primary key,
  supplier_id  bigint not null references public.leads(id) on delete cascade,
  -- the reading's kinds (supplier_profile_reading.QuestionKind), 'new_key' for "Something else" words that map to a key behind,
  -- and the later triggers of the design (3.8, slice 7)
  kind         text not null check (kind in ('nothing', 'vague', 'trade_services', 'partner', 'shown', 'umbrella', 'licence',
                                            'new_key', 'new_evidence', 'quoted', 'declined', 'still_right')),
  about        jsonb not null default '{}'::jsonb,
  about_hash   text not null check (length(about_hash) between 1 and 64),
  prompt_en    text not null check (length(btrim(prompt_en)) > 0),
  options      jsonb not null default '[]'::jsonb check (jsonb_typeof(options) = 'array'),
  multi        boolean not null default true,
  status       text not null default 'open' check (status in ('open', 'later', 'answered', 'skipped', 'expired')),
  answer       jsonb,
  source       text not null,
  asked_at     timestamptz not null default now(),
  answered_at  timestamptz,
  reminded_at  timestamptz,
  constraint supplier_service_question_once unique (supplier_id, kind, about_hash),
  constraint supplier_service_question_answered check ((status = 'answered') = (answer is not null and answered_at is not null))
);
comment on table public.supplier_service_question is
  'sales_engineer: each question put to a supplier about his services (ruling 1647; report 3.8): drafted by the reading or a later trigger, answered on the Services tab through supplier_api, never read by the supplier directly.';
create index if not exists supplier_service_question_supplier on public.supplier_service_question (supplier_id, status);
alter table public.supplier_service_question enable row level security;
drop policy if exists supplier_service_question_service_role_only on public.supplier_service_question;
create policy supplier_service_question_service_role_only on public.supplier_service_question
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_service_question from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('supplier_service_question', true, 'supplier', 'Each question put to a supplier about his services and his answer: the record of why a service is on his list (ruling 1647).', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- Verdict row (DDL file, so no raise): the column, the table closed to the public roles with its policy, the registry row,
-- and no supplier holding a partner key outside his services.
select case
  when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'supplier_capabilities'
                     and column_name = 'services_partner' and is_nullable = 'NO')
    then 'PROBE FAILED: supplier_capabilities.services_partner is missing or nullable'
  when not (select relrowsecurity from pg_class where oid = 'public.supplier_service_question'::regclass)
    then 'PROBE FAILED: supplier_service_question has no row level security'
  when not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'supplier_service_question')
    then 'PROBE FAILED: supplier_service_question has no policy'
  when has_table_privilege('anon', 'public.supplier_service_question', 'select')
    or has_table_privilege('authenticated', 'public.supplier_service_question', 'select')
    then 'PROBE FAILED: a public role can read supplier_service_question'
  when not exists (select 1 from public.table_export_registry where table_name = 'supplier_service_question' and exported)
    then 'PROBE FAILED: supplier_service_question is not in the export registry'
  when exists (select 1 from public.supplier_capabilities where not (services_partner <@ coalesce(services, '{}'::text[])))
    then 'PROBE FAILED: a supplier holds a partner service that is not one of his services'
  else 'PROBE OK' end as verdict;
