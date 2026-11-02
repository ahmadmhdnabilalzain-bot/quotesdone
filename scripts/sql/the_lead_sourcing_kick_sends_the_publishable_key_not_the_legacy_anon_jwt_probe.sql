-- PROBE: THE LEAD SOURCING KICK SENDS THE PUBLISHABLE KEY (it_engineer, 27 Oct 2026). Assigned: it_engineer.
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so everything it writes rolls back. Run it after
-- the_lead_sourcing_kick_sends_the_publishable_key_not_the_legacy_anon_jwt.sql in the same rolled-back
-- transaction (scripts/checks/the_lead_sourcing_kick_sends_the_publishable_key.test.mjs does), or alone once that
-- file is live. It cannot reach anyone: the kick's net.http_post only queues a row in net.http_request_queue, and
-- pg_net's worker reads committed rows only, so the raise removes the request before it can be sent. It never
-- prints a key: every comparison happens here and only booleans leave.
--
-- It proves, by execution:
--   1. with no publishable_key row, fn_gateway_client_key() returns the live app_secrets.anon_key (the fallback);
--   2. with a publishable_key row, it returns that row, and the kick queues its request with that value as both
--      apikey and Bearer, to the marketing function, carrying the unchanged __secret;
--   3. neither routine is executable by anon or authenticated.
-- The kick is made to run by lifting lead_sourcing_daily_quota to 1 inside the transaction (it is 0 today, so the
-- kick returns before sending anything); that write rolls back with the rest.

do $probe$
declare
  v_bad text[] := '{}';
  v_anon text; v_fake constant text := 'sb_publishable_ZZPROBE_not_a_key_' || md5(clock_timestamp()::text);
  v_req bigint; v_h jsonb; v_url text; v_body text;
begin
  select value into v_anon from public.app_secrets where key = 'anon_key';
  if v_anon is null then v_bad := v_bad || 'app_secrets.anon_key is absent, so the fallback cannot be shown'::text; end if;

  -- 1. the fallback
  delete from public.app_secrets where key = 'publishable_key';
  if public.fn_gateway_client_key() is distinct from v_anon then
    v_bad := v_bad || 'without publishable_key the key is not the legacy anon_key'::text;
  end if;

  -- 2. the new key, end to end through the kick
  insert into public.app_secrets(key, value) values ('publishable_key', v_fake);
  if public.fn_gateway_client_key() is distinct from v_fake then
    v_bad := v_bad || 'with publishable_key the key is not the publishable one'::text;
  end if;
  insert into public.app_secrets(key, value) values ('lead_sourcing_daily_quota', '1')
    on conflict (key) do update set value = '1';
  if (public.fn_lead_sourcing_today()->>'stop') is not null then
    v_bad := v_bad || ('the kick would not run: ' || (public.fn_lead_sourcing_today()->>'stop'));
  else
    v_req := public.fn_lead_sourcing_kick();
    select headers, url, convert_from(body, 'UTF8') into v_h, v_url, v_body from net.http_request_queue where id = v_req;
    if v_h is null then v_bad := v_bad || 'the kick queued no request'::text;
    else
      if v_h->>'apikey' is distinct from v_fake then v_bad := v_bad || 'apikey is not the publishable key'::text; end if;
      if v_h->>'Authorization' is distinct from 'Bearer ' || v_fake then v_bad := v_bad || 'Bearer is not the publishable key'::text; end if;
      if position(v_anon in v_h::text) > 0 then v_bad := v_bad || 'the legacy anon JWT is still in the request'::text; end if;
      if v_url not like 'https://%.supabase.co/functions/v1/marketing' then v_bad := v_bad || ('wrong url ' || v_url); end if;
      if (v_body::jsonb)->>'action' is distinct from 'lead_sourcing'
         or (v_body::jsonb)->>'__secret' is distinct from (select value from public.app_secrets where key = 'cred_fn_marketing') then
        v_bad := v_bad || 'the body changed'::text;
      end if;
    end if;
  end if;

  -- 3. closed to the internet roles
  if has_function_privilege('anon', 'public.fn_gateway_client_key()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_gateway_client_key()', 'execute')
     or has_function_privilege('anon', 'public.fn_lead_sourcing_kick()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_lead_sourcing_kick()', 'execute') then
    v_bad := v_bad || 'a routine is executable by anon or authenticated'::text;
  end if;

  if cardinality(v_bad) = 0 then
    raise exception 'CHK<<PROBE OK: fallback=anon_key, new=publishable_key, kick queued apikey+Bearer=publishable (request % rolled back), closed to anon/authenticated>>', v_req;
  end if;
  raise exception 'CHK<<PROBE FAILED: %>>', array_to_string(v_bad, '; ');
end $probe$;
