-- THE INTERNAL PHASE-D REGISTRIES THAT LEAKED TO AUTHENTICATED (6 Sep 2026).
--
-- The daily self-audit has fired anon_exposure_drift = 'anon_readable_tables=6' every morning
-- (security_events 1114..1119, last 2026-09-06 03:20Z). MEASURED, the six are:
--
--   documents                 RLS on, 1 policy  -> INTENTIONAL: the SPEC 14 customer document vault
--                             grants SELECT to authenticated, row-scoped by documents_customer_select
--                             to the caller's own (ref_table, ref_id). It is added to the self-audit's
--                             NAMED allowlist (ai-organization/db-functions/fn_security_selfaudit.sql),
--                             the same mechanism category_specs and blog_posts use.
--
--   phase_d_handler_binding   RLS on, 0 policies -> STRAY. The five phase_d D1/D3/D5 registries were
--   phase_d_handler_schema    granted `select ... to service_role, authenticated` in their build
--   phase_d_rule_enforcement  migrations. They are internal kernel registries read only by the
--   phase_d_gate_contract     SECURITY DEFINER fn_phase_d_* routines (which run as owner, unaffected by
--   phase_d_payment_state     this grant). No src/ or edge client reads them through an authenticated
--                             JWT. With RLS on and no policy the grant already returns zero rows to
--                             authenticated, so this REVOKE removes a misleading grant and changes no
--                             actual access — it just stops the invariant reading as broken.
--
-- This is the fix the self-audit exists to force: the grant is removed, not the check weakened. After
-- it, anon/authenticated reach only category_specs, published blog_posts, and their own rows in
-- documents — which is the anonymity-by-construction invariant, now true again.
--
--   node scripts/apply_sql.mjs scripts/sql/the_internal_registries_that_leaked_to_authenticated.sql --apply --ddl

begin;

revoke select on public.phase_d_handler_binding  from authenticated, anon;
revoke select on public.phase_d_handler_schema   from authenticated, anon;
revoke select on public.phase_d_rule_enforcement from authenticated, anon;
revoke select on public.phase_d_gate_contract    from authenticated, anon;
revoke select on public.phase_d_payment_state    from authenticated, anon;

-- AND ONE SECURITY DEFINER FUNCTION THAT LEAKED EXECUTE TO PUBLIC (6 Sep 2026). The self-audit's
-- secdef_fns_anon count went from 0 to 1 when trg_pages_legal_sync() -- the pages -> legal_documents
-- sync trigger a sibling item added today to populate the legal registry -- was created and, like
-- every freshly CREATEd SECURITY DEFINER routine, granted EXECUTE to PUBLIC. A trigger function is
-- run by the trigger with the table's privileges and never needs a direct EXECUTE grant, so this
-- revoke removes the anon reach without affecting the trigger. Guarded so it is a no-op if the
-- function is not present. CREATE OR REPLACE preserves an ACL, so this revoke survives a re-apply of
-- the sibling's file; a DROP+CREATE there would re-grant, which the daily self-audit would re-flag.
do $revoke_secdef$
begin
  if to_regprocedure('public.trg_pages_legal_sync()') is not null then
    execute 'revoke execute on function public.trg_pages_legal_sync() from public, anon, authenticated';
  end if;
end $revoke_secdef$;

do $proof$
declare v_leak int; v_fn int;
begin
  select count(*) into v_leak from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind='r'
     and c.relname in ('phase_d_handler_binding','phase_d_handler_schema','phase_d_rule_enforcement',
                       'phase_d_gate_contract','phase_d_payment_state')
     and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'));
  if v_leak <> 0 then
    raise exception 'still % phase_d registr(ies) readable by anon/authenticated after revoke', v_leak;
  end if;
  select count(*) into v_fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_fn <> 0 then
    raise exception 'still % security-definer function(s) executable by anon after revoke', v_fn;
  end if;
  raise notice 'proof: 0 phase_d registries anon-readable and 0 secdef functions anon-executable';
end $proof$;

commit;
