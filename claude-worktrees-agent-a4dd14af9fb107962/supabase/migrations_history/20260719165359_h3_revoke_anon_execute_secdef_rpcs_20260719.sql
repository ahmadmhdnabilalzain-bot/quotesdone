-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719165359   name: h3_revoke_anon_execute_secdef_rpcs_20260719
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H3: remove the unauthenticated RPC surface on 20 SECURITY DEFINER functions.
-- Must revoke from PUBLIC as well as anon/authenticated (all three held EXECUTE).
-- service_role + postgres keep EXECUTE, so the edge-function (service-role) callers are unaffected.
-- Trigger functions are included for hygiene; triggers fire regardless of EXECUTE grants.
revoke execute on function public.fn_assign_founding_rank()                     from public, anon, authenticated;
revoke execute on function public.fn_assign_founding_ranks()                    from public, anon, authenticated;
revoke execute on function public.fn_customer_stats(uuid)                       from public, anon, authenticated;
revoke execute on function public.fn_dropbox_list(text)                         from public, anon, authenticated;
revoke execute on function public.fn_expiring_docs(integer)                     from public, anon, authenticated;
revoke execute on function public.fn_invite_week_activate()                     from public, anon, authenticated;
revoke execute on function public.fn_llm_drift_watch()                          from public, anon, authenticated;
revoke execute on function public.fn_os_detail(text, text)                      from public, anon, authenticated;
revoke execute on function public.fn_os_list(text, jsonb)                       from public, anon, authenticated;
revoke execute on function public.fn_policy_consistency_check()                 from public, anon, authenticated;
revoke execute on function public.fn_protect_gate_secrets()                     from public, anon, authenticated;
revoke execute on function public.fn_reconcile_licence_blocks(integer)          from public, anon, authenticated;
revoke execute on function public.fn_sla_watch()                                from public, anon, authenticated;
revoke execute on function public.fn_subscription_billing_run(boolean)          from public, anon, authenticated;
revoke execute on function public.fn_supplier_expiries(bigint)                  from public, anon, authenticated;
revoke execute on function public.fn_supplier_stats(bigint)                     from public, anon, authenticated;
revoke execute on function public.rl_check(text, integer, integer)              from public, anon, authenticated;
revoke execute on function public.trg_block_banned_inquiry()                    from public, anon, authenticated;
revoke execute on function public.trg_customer_abandon_ban()                    from public, anon, authenticated;
revoke execute on function public.trg_inquiry_enrich()                          from public, anon, authenticated;
