-- PROBE: the first-reply watch reads the address inside <...> and matches the machine word as a whole word
-- (27 Oct 2026). Assigned: customer_support.
--
-- A PURE PROBE: no DDL, and it ALWAYS ENDS IN `raise exception 'CHK<<…>>'`, so every row it writes and every
-- finding the tick touches is rolled back by its own last statement, whatever the verdict. It can never commit.
-- The verdict is the text between CHK<< and >>: 'PROBE OK …' or 'PROBE FAILED: …'. Run it AFTER
-- support_reply_watch_reads_the_bracketed_address_and_matches_whole_words.sql is applied, or ahead of it inside
-- one rolled-back statement. Against the body live on 27 Oct 2026 20:29 UTC it reports PROBE FAILED.
--
-- Fixture senders are on probe-never-sent.com: the watch skips @example.invalid as a demo address
-- (fn_is_demo_email), so the fixtures must be a domain it counts. The watch sends nothing, and the final raise
-- rolls back everything anyway.
do $probe$
declare
  f text[] := '{}';
  v jsonb; v_prev int; v_now int; v_over interval; v_addr text; v_counted boolean;
  v_cases jsonb := jsonb_build_array(
    -- [From header, counted as a customer waiting?]
    jsonb_build_array('"noreply@spoof.com" <bob@probe-never-sent.com>', true),          -- review of #1684: a customer
    jsonb_build_array('"Mailer-Daemon@x.com" <carol.ops@probe-never-sent.com>', true),   -- same shape, another word
    jsonb_build_array('noreplying@probe-never-sent.com', true),                          -- a longer word: a person
    jsonb_build_array('donotreplyteam@probe-never-sent.com', true),
    jsonb_build_array('Alice <alice.noreply.fan@probe-never-sent.com>', true),           -- kept from #1684
    jsonb_build_array('alice+noreply@probe-never-sent.com', true),
    jsonb_build_array('noreen@probe-never-sent.com', true),
    jsonb_build_array('"Bob" <noreply@probe-never-sent.com>', false),                   -- the bracketed address is the machine
    jsonb_build_array('LinkedIn <security-noreply@probe-never-sent.com>', false),        -- the #1684 miss stays exempt
    jsonb_build_array('noreply@probe-never-sent.com', false),
    jsonb_build_array('noreply.alerts@probe-never-sent.com', false),
    jsonb_build_array('no-reply2@probe-never-sent.com', false),
    jsonb_build_array('MAILER-DAEMON@probe-never-sent.com', false),
    jsonb_build_array('alerts_no_reply+bounce@probe-never-sent.com', false),
    jsonb_build_array('account-do-not-reply@probe-never-sent.com', false));
begin
  if has_function_privilege('anon', 'public.fn_support_reply_watch_tick()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_support_reply_watch_tick()', 'execute') then
    f := f || text 'fn_support_reply_watch_tick is callable by anon/authenticated'; end if;

  -- one sender at a time, measured by the tick's own over_sla count (never by the 20-id evidence list)
  v := public.fn_support_reply_watch_tick();
  v_prev := coalesce((v->'email'->>'over_sla')::int, 0);
  v_over := make_interval(hours => ceil(coalesce((v->>'sla_hours')::numeric, 24))::int + 1);   -- just past the live SLA
  for i in 0 .. jsonb_array_length(v_cases) - 1 loop
    v_addr := v_cases->i->>0; v_counted := (v_cases->i->>1)::boolean;
    insert into public.inbound_messages (from_email, to_email, subject, body, created_at)
    values (v_addr, 'zz.support.watch.probe@probe-never-sent.com', 'ZZ DEMO support watch probe', 'probe', now() - v_over);
    v := public.fn_support_reply_watch_tick();
    v_now := coalesce((v->'email'->>'over_sla')::int, 0);
    if v_counted and v_now <> v_prev + 1 then
      f := f || (v_addr || ' is a customer and was NOT counted as waiting');
    elsif not v_counted and v_now <> v_prev then
      f := f || (v_addr || ' is a machine sender and WAS counted as a customer waiting');
    end if;
    v_prev := v_now;
  end loop;

  raise exception 'CHK<<%>>', case when cardinality(f) = 0
    then 'PROBE OK: the address inside <...> decides (a machine-looking display name hides no customer), noreplying@ and donotreplyteam@ are people, and security-noreply, noreply.alerts, no-reply2, MAILER-DAEMON, no_reply and do-not-reply stay exempt; alice.noreply.fan, alice+noreply and noreen still counted; everything rolled back by this raise'
    else 'PROBE FAILED: ' || array_to_string(f, '; ') end;
end $probe$;
