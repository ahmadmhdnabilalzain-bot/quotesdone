-- Supabase security advisor, 28 Jul 2026: four SECURITY DEFINER TRIGGER functions were
-- callable by anon and authenticated through /rest/v1/rpc/<name>. A trigger function has no
-- business being reachable over REST at all - it only ever runs from its trigger - and each of
-- these runs with definer privileges, so leaving them exposed is a needless attack surface.
-- Direct invocation would fail for want of trigger context, but the endpoint should not exist.
revoke execute on function trg_ai_cost_attribute() from public, anon, authenticated;
revoke execute on function trg_audit_agent_run()   from public, anon, authenticated;
revoke execute on function trg_goal_cascade()      from public, anon, authenticated;
revoke execute on function trg_undo_capture()      from public, anon, authenticated;

-- Same class of exposure for everything built today. These are already revoked at creation,
-- but re-asserting is idempotent and makes the guarantee explicit in one place.
revoke execute on function fn_ai_route(text,text,numeric,text,boolean) from public, anon, authenticated;
revoke execute on function fn_select_model(text,text,numeric)          from public, anon, authenticated;
revoke execute on function fn_faq_answer(text,numeric,vector,numeric)  from public, anon, authenticated;
revoke execute on function fn_rate_limit(text,integer,integer)         from public, anon, authenticated;
revoke execute on function fn_model_cost_usd(text,integer,integer,integer) from public, anon, authenticated;
revoke execute on function fn_agent_context_capped(text,integer)       from public, anon, authenticated;
revoke execute on function fn_ai_spend_guard()                         from public, anon, authenticated;
revoke execute on function fn_edge_health_scan()                       from public, anon, authenticated;
revoke execute on function fn_llm_cache_lookup(text,vector,text,numeric) from public, anon, authenticated;
revoke execute on function fn_llm_cache_store(text,text,text,text,text,integer,vector,numeric) from public, anon, authenticated;