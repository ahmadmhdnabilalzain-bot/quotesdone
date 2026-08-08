-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711191945   name: revoke_execute_on_trigger_functions_from_public_roles
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Security hardening: trigger/event_trigger functions must not be directly
-- executable by anon/authenticated via PostgREST RPC. They fire via triggers
-- regardless of direct EXECUTE grants; the app uses the service role.
-- Clears 24 Supabase security-advisor WARN findings (12 anon + 12 authenticated).
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.fn_category_knowledge_promote()',
    'public.fn_enforce_rls_on_new_tables()',
    'public.fn_gl_journal_immutable()',
    'public.fn_gl_lines_immutable()',
    'public.fn_notify_matched_supplier()',
    'public.fn_security_audit()',
    'public.trg_autodispatch_inquiry()',
    'public.trg_company_faq_sync()',
    'public.trg_enrich_capability()',
    'public.trg_gate_incomplete_match()',
    'public.trg_quote_items_rescore()',
    'public.trg_self_reg_category()'
  ]
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
  end loop;
end $$;
