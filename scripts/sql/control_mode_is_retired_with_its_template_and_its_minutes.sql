-- CONTROL MODE IS RETIRED, WITH ITS WHATSAPP TEMPLATE AND ITS MINUTES SETTING.
--
-- Assigned: accountant (the last money path that needed it was refunds_api 'resolve').
--
-- WHAT WAS MEASURED (15 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * refunds_api 'resolve' answers 410 since the one refund rail (14 Sep 2026); it was the last
--     edge function that called fn_control_mode_require. The os_api Control Mode handlers left on
--     6 Sep, and fn_control_mode_open/close/status/sweep/minutes/challenge_* were dropped 7 Sep
--     (scripts/sql/DROPPED.txt).
--   * public.fn_control_mode_require(text,text): 0 routine bodies call it, 0 triggers, 0 pg_depend
--     rows, 0 views, 0 policies, 0 column defaults, 0 cron jobs. Repository: 0 references in
--     supabase/functions, src or .github; the only mentions are RETIRED checks, the identity-coverage
--     baseline and history files.
--   * public.fn_phase1_disarmed(): its ONLY caller is fn_control_mode_require (same measurements).
--   * messaging_template, template_key 'control_mode_code' (en): status 'rejected' by Meta, note
--     "Control Mode is retired ... not a sender path". 0 routine bodies name the key; the only reader
--     of the table, fn_company_self_knowledge_sync, lists whatever rows exist.
--   * app_secrets 'control_mode_minutes': 0 routine bodies name it (its reader fn_control_mode_minutes
--     was dropped 7 Sep); 0 repository references outside history. It is not one of the keys
--     fn_protect_app_secret or fn_autonomy_control_guard protect.
--
-- WHAT THIS DOES: drops the two routines (recorded in scripts/sql/DROPPED.txt) and deletes exactly
-- one messaging_template row and exactly one app_secrets row.
-- WHAT THIS DOES NOT DO: the control_mode_* tables stay (control_mode_session keeps its one row from
-- 4 Aug and its trigger fn_control_mode_session_mfa_is_real, which still guards writes to it;
-- control_mode_action keeps 108 rows). They are history, and removing a table is a separate decision.
--
--   node scripts/apply_sql.mjs scripts/sql/control_mode_is_retired_with_its_template_and_its_minutes.sql --apply --ddl

-- Refuse the whole file if anything started calling either routine since the measurement.
do $$
declare v text;
begin
  -- Every schema except the system ones (review of this file: a caller outside public, e.g. a
  -- staging schema, would otherwise slip past; measured 15 Sep 2026 there is none).
  select string_agg(n.nspname || '.' || p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema')
     and p.oid not in ('public.fn_control_mode_require(text,text)'::regprocedure, 'public.fn_phase1_disarmed()'::regprocedure)
     and p.prosrc ~* 'fn_control_mode_require|fn_phase1_disarmed';
  if v is not null then raise exception 'a routine now calls Control Mode: %', v; end if;
  if exists (select 1 from pg_trigger t where t.tgfoid in ('public.fn_control_mode_require(text,text)'::regprocedure, 'public.fn_phase1_disarmed()'::regprocedure))
    then raise exception 'a trigger is bound to a Control Mode routine'; end if;
  if exists (select 1 from cron.job where command ~* 'fn_control_mode_require|fn_phase1_disarmed')
    then raise exception 'a cron job names a Control Mode routine'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~* 'control_mode_minutes|control_mode_code')
    then raise exception 'a routine reads control_mode_minutes or control_mode_code'; end if;
end $$;

drop function if exists public.fn_control_mode_require(text, text);
drop function if exists public.fn_phase1_disarmed();

delete from public.messaging_template
 where template_key = 'control_mode_code' and lang = 'en' and channel = 'whatsapp' and status = 'rejected';
delete from public.app_secrets where key = 'control_mode_minutes';

do $$
begin
  if exists (select 1 from pg_proc where proname in ('fn_control_mode_require', 'fn_phase1_disarmed'))
    then raise exception 'a Control Mode routine is still defined'; end if;
  if exists (select 1 from public.messaging_template where template_key = 'control_mode_code')
    then raise exception 'the control_mode_code template row is still there'; end if;
  if exists (select 1 from public.app_secrets where key = 'control_mode_minutes')
    then raise exception 'app_secrets.control_mode_minutes is still there'; end if;
  raise notice 'control_mode_is_retired_with_its_template_and_its_minutes: 2 routines, 1 template row, 1 secret row gone';
end $$;
