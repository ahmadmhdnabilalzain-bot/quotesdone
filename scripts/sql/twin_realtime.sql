-- The company twin refreshes in real time — safely.
--
-- All thirteen twin tables have RLS ENABLED WITH ZERO POLICIES, which is deny-all. That is why
-- publishing them to realtime on its own would have been theatre: the browser holds an
-- authenticated key, not the service role, so a subscription would have been a permanent no-op and
-- the check would have gone green over a feature that does nothing.
--
-- The real fix is a policy, and the policy has to be narrow. Each table gets ONE select policy
-- gated on fn_role_of(), the same owner/admin test os_api already uses at its own door:
--
--   * the founder's session (owner/admin) can read, so realtime delivers to the console
--   * every other authenticated identity — every supplier and every customer holding a
--     QuotesDone login — is denied exactly as it is today, because there is no other policy
--   * the anon key is denied, because these policies are `to authenticated`
--
-- This does widen what the founder's own browser can read directly through PostgREST. That is the
-- point: it is what "every twin object refreshes in real time" requires, and it grants the founder
-- read access to data os_api already returns to them under the service role. No other identity
-- gains anything.
--
--   node scripts/apply_sql.mjs scripts/sql/twin_realtime.sql --ddl --promote
do $$
declare t text;
  twin text[] := array['customers','leads','org_agents','kb_chunks','inquiries','transactions',
                       'gl_journal','ai_cost_log','workflow','edge_health_probe','risk_register',
                       'expenses','vision_horizon'];
begin
  foreach t in array twin loop
    if to_regclass('public.' || t) is null then continue; end if;

    -- One narrow policy per table. Dropped first so this file is idempotent.
    execute format('drop policy if exists os_owner_admin_read on public.%I', t);
    execute format($p$create policy os_owner_admin_read on public.%I
                      for select to authenticated
                      using (public.fn_role_of(auth.jwt() ->> 'email') in ('owner','admin'))$p$, t);

    -- Without membership of the publication a subscription delivers nothing at all, so this is
    -- the other half and neither is sufficient alone.
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
