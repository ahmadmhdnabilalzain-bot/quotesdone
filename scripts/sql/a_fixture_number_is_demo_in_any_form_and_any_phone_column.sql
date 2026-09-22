-- A FIXTURE NUMBER IS DEMO IN ANY FORM, AND IN EITHER PHONE COLUMN.
--
-- Assigned: it_engineer. 22 Sep 2026 (coordinator item 6).
--
-- MEASURED (production, 22 Sep 2026 ~11:50Z):
--   customers.is_demo = fn_is_demo_email(email) OR fn_is_demo_phone(phone) OR full_name ILIKE 'ZZ DEMO%'
--     -- whatsapp_phone is not read. customers has 4 rows (3 demo); none holds a fixture number in
--     whatsapp_phone alone today, so the rewrite below flips no row.
--   fn_is_demo_phone('0500000097') = false: the rule matched only '^9715000000[0-9]{2}$' after stripping
--     non-digits, so the local form of the reserved block read as a real person.
--   leads.is_demo also calls fn_is_demo_phone(phone): 22,267 rows, 0 with a local-form fixture phone, so
--     its stored values need no recompute (a stored generated column recomputes only when its row changes).
--   One view reads customers.is_demo: v_accountant_refund_reserve.
--
-- WHAT IS WRONG: (a) a fixture number in customers.whatsapp_phone on a real-address row leaves the row
--   'real'; (b) 050 000 00xx is the same reserved block as +971 50 000 00xx and was not recognised.
--
-- WHAT CHANGES:
--   1. fn_is_demo_phone: '^(971|0)5000000[0-9]{2}$' -- international or local form. Same rule as
--      supabase/functions/_shared/demo_identity.ts RESERVED_FIXTURE_MOBILE (changed in the same PR).
--   2. customers.is_demo also reads fn_is_demo_phone(whatsapp_phone). ALTER COLUMN ... SET EXPRESSION
--      (Postgres 17) rewrites the table -- 4 rows -- under lock_timeout 3 s, so a busy table makes this
--      file fail rather than queue sign-ins behind it (memory: an apply can lock sign-in).
--
-- WHAT DOES NOT CHANGE: fn_is_demo_email; leads.is_demo's expression; every reader of is_demo.
--
-- PREVENTED BY: the probe at the foot of this file (PROBE OK / PROBE FAILED row: local form, whatsapp
--   column, controls), supabase/functions/_shared/demo_identity.test.ts (the TypeScript twin, same cases),
--   and scripts/checks/a_phone_cannot_select_an_account.test.mjs, which now names the ids, demo marker and
--   column behind any "number is carried by a real customers row" so a transient reading is told apart.
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/a_fixture_number_is_demo_in_any_form_and_any_phone_column.sql --apply --ddl

set local lock_timeout = '3s';

create or replace function public.fn_is_demo_phone(p_phone text)
returns boolean language sql immutable
set search_path to 'pg_catalog', 'pg_temp'
as $fn$
  select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') ~ '^(971|0)5000000[0-9]{2}$'
$fn$;

comment on function public.fn_is_demo_phone(text) is
  'True for the reserved fixture mobile block +971 50 000 00xx, international or local (050 000 00xx) form. Same rule as _shared/demo_identity.ts.';

alter table public.customers alter column is_demo set expression as (
  public.fn_is_demo_email(email) or public.fn_is_demo_phone(phone) or public.fn_is_demo_phone(whatsapp_phone)
  or coalesce(full_name, '') ilike 'ZZ DEMO%'
);

-- VERDICT (no DDL after it; nothing it does survives -- it only reads and compares).
select case when public.fn_is_demo_phone('0500000097') and public.fn_is_demo_phone('050 000 0042')
             and public.fn_is_demo_phone('+971 50 000 0042') and public.fn_is_demo_phone('971500000097')
             and not public.fn_is_demo_phone('0501234567') and not public.fn_is_demo_phone('+971501234567')
             and not public.fn_is_demo_phone('+971500000100') and not public.fn_is_demo_phone('050000001')
             and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
                   join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
                  where d.adrelid = 'public.customers'::regclass and a.attname = 'is_demo') like '%fn_is_demo_phone(whatsapp_phone)%'
             and not exists (select 1 from public.customers c
                              where c.is_demo is distinct from (public.fn_is_demo_email(c.email) or public.fn_is_demo_phone(c.phone)
                                    or public.fn_is_demo_phone(c.whatsapp_phone) or coalesce(c.full_name, '') ilike 'ZZ DEMO%'))
            then 'PROBE OK: the local form and customers.whatsapp_phone are demo; controls stay real; every customers row recomputed'
            else 'PROBE FAILED: fn_is_demo_phone or customers.is_demo is not what this file defines' end verdict;
