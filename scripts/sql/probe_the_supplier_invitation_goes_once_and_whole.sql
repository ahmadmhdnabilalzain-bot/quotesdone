-- PROBE: the supplier invitation goes once, whole, in the supplier's language, and never to a demo,
-- banned, screened or already-invited lead (21 Sep 2026, customer_support under ceo oversight).
--
-- Pure read. No DDL, no writes, touches no real row. Run AFTER
-- scripts/sql/the_supplier_invitation_goes_once_in_the_suppliers_language_and_never_to_a_demo_or_sanctioned_lead.sql
-- Returns ONE verdict row: 'PROBE OK' or 'PROBE FAILED: <every reason>'.
--
-- It reads the dry run itself — fn_supplier_invite_candidates(50) is exactly who would be written
-- to the outbox next and with what words — and asserts on that set, so it fails if the recipient
-- rule regresses even while every definition still "looks" right.
with c as (select * from public.fn_supplier_invite_candidates(50)),
cs as (
  select count(*) n,
         count(distinct lower(to_email)) n_distinct,
         count(*) filter (where public.fn_is_demo_email(to_email) or company_name ~* '^\s*zz\s*demo') n_demo,
         count(*) filter (where body !~ '/(en|ar)/portal[?]t=[0-9a-f-]{36}') n_nolink,
         count(*) filter (where body like '%{{%' or subject like '%{{%') n_placeholder,
         count(*) filter (where lang = 'ar' and body !~ '[؀-ۿ]') n_lang_mismatch,
         count(*) filter (where not exists (select 1 from public.leads l where l.id = c.lead_id and public.fn_supplier_invite_eligible(l))) n_ineligible,
         count(*) filter (where exists (select 1 from public.notifications n where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(c.to_email))) n_already
    from c
),
pool as (select count(*) n from public.leads l where public.fn_supplier_invite_eligible(l)),
fails as (
  select unnest(array[
    case when not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'notifications_supplier_invite_once_uidx'
                          and indexdef ilike 'create unique index%') then 'no unique one-invitation-per-address index' end,
    case when not exists (select 1 from pg_trigger where tgrelid = 'public.notifications'::regclass
                          and tgname = 'a07_notifications_supplier_invite_is_whole' and tgenabled <> 'D') then 'the invitation-is-whole trigger is missing or disabled' end,
    case when position('fn_supplier_invite_candidates' in pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure)) = 0
         then 'enqueue_supplier_invites no longer selects through fn_supplier_invite_candidates (dry run and send could diverge)' end,
    case when position('fn_supplier_invite_eligible' in pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure)) = 0
         then 'the pool count no longer uses the eligibility rule' end,
    case when exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                       where s.nspname = 'public'
                         and p.proname in ('fn_supplier_invite_eligible','fn_supplier_invite_candidates','enqueue_supplier_invites',
                                           'fn_supplier_invite_test_send','fn_notifications_supplier_invite_is_whole')
                         and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                              or not coalesce(array_to_string(p.proconfig, ',') like '%search_path%', false)))
         then 'an invitation routine is callable by anon/authenticated or has no pinned search_path' end,
    case when coalesce((select value from public.app_secrets where key = 'invite_body_ar'), '') not like '%{{link}}%'
           or coalesce((select value from public.app_secrets where key = 'invite_body_ar'), '') !~ '[؀-ۿ]'
         then 'the Arabic invitation is missing, has no Arabic, or has no {{link}}' end,
    case when (select n from pool) > 0 and cs.n = 0 then 'eligible leads exist but the dry run selects nobody' end,
    case when cs.n <> cs.n_distinct then 'the dry run names one address twice' end,
    case when cs.n_demo > 0 then cs.n_demo || ' demo recipient(s) in the dry run' end,
    case when cs.n_nolink > 0 then cs.n_nolink || ' invitation(s) with no portal link' end,
    case when cs.n_placeholder > 0 then cs.n_placeholder || ' invitation(s) with an unsubstituted placeholder' end,
    case when cs.n_lang_mismatch > 0 then cs.n_lang_mismatch || ' Arabic invitation(s) with no Arabic' end,
    case when cs.n_ineligible > 0 then cs.n_ineligible || ' ineligible lead(s) in the dry run' end,
    case when cs.n_already > 0 then cs.n_already || ' already-invited address(es) in the dry run' end
  ]) as why
  from cs
)
select case when count(why) = 0
            then 'PROBE OK: ' || (select n from cs) || ' of ' || (select n from pool) || ' eligible lead(s) in the dry run; one invitation per address enforced'
            else 'PROBE FAILED: ' || string_agg(why, '; ') end as verdict
  from fails;
