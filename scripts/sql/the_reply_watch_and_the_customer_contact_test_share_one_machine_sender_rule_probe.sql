-- PROBE: the reply watch and the customer-contact test share one machine-sender rule (27 Oct 2026).
-- Assigned: customer_support.
--
-- A PURE PROBE: no DDL, and EVERY path ends in `raise exception 'CHK<<…>>'` -- the work sits in an inner block
-- whose error handler only records the error, so even a failure inside it reaches the final raise. Every row it
-- writes and every finding the tick touches is rolled back by that raise, whatever the verdict: it can never
-- commit. (A probe that returns a verdict row commits whatever ran before it, including DDL.)
--
-- Two ways to run it, both rolled back by its own raise:
--   BEFORE  this probe alone against live            -> fn_is_machine_sender is absent; the table shows what
--                                                       (a) and (b) decide today, and the verdict is PROBE FAILED.
--   AFTER   the .sql file followed by this probe, sent as ONE query (one implicit transaction), so the DDL is
--           rolled back with the probe                -> the verdict must be PROBE OK.
--
-- For each From header in the table it records: whether it is a machine (the expected answer), what
-- fn_is_machine_sender says, what the reply watch (a) does with it -- measured by inserting one inbound message
-- just past the SLA and reading the tick's own over_sla count -- and what fn_support_email_is_a_customer_contact
-- (b) returns for it. Every fixture address is on probe-never-sent.com: nothing here can reach a real mailbox,
-- the watch only counts, and the final raise removes the rows anyway. The probe also counts, over all stored
-- inbound_messages, how many change side between each routine's old rule and the shared one.
--
-- The case table below is ALSO read by scripts/checks/detectors_stop_escalating_what_is_not_a_fault.test.mjs (6g),
-- which replays the canonical fn_is_machine_sender over it offline: one table, two readers. Keep one case per line
-- in the shape  jsonb_build_array('<From header>', <machine true|false>),
do $probe$
declare
  f text[] := '{}';
  v_rows text[] := '{}';
  v jsonb; v_prev int; v_now int; v_over interval;
  v_from text; v_machine boolean; v_fn boolean; v_a boolean; v_b boolean; v_has_fn boolean;
  v_old_a int; v_old_b int; v_total int;
  yn constant text[] := array['person', 'MACHINE'];
  v_cases jsonb := jsonb_build_array(
    -- machines
    jsonb_build_array('noreply@probe-never-sent.com', true),
    jsonb_build_array('no-reply@probe-never-sent.com', true),
    jsonb_build_array('no_reply@probe-never-sent.com', true),
    jsonb_build_array('NoReply@PROBE-NEVER-SENT.COM', true),                                  -- uppercase
    jsonb_build_array('MAILER-DAEMON@mx.probe-never-sent.com', true),                         -- uppercase
    jsonb_build_array('postmaster@probe-never-sent.com', true),
    jsonb_build_array('bounce@probe-never-sent.com', true),
    jsonb_build_array('bounces+abc123=probe-never-sent.com@lists.probe-never-sent.com', true),
    jsonb_build_array('ops-bounces@lists.probe-never-sent.com', true),
    jsonb_build_array('Billing <Do-Not-Reply@probe-never-sent.com>', true),
    jsonb_build_array('LinkedIn <security-noreply@probe-never-sent.com>', true),              -- the #1684 miss
    jsonb_build_array('noreply.alerts@probe-never-sent.com', true),
    jsonb_build_array('no-reply2@probe-never-sent.com', true),
    jsonb_build_array('alerts_no_reply+bounce@probe-never-sent.com', true),
    jsonb_build_array('account-do-not-reply@probe-never-sent.com', true),
    jsonb_build_array('"Bob" <noreply@probe-never-sent.com>', true),                          -- the bracket decides
    jsonb_build_array('"a@b" <noreply@probe-never-sent.com>', true),                          -- quoted @, machine inside <>
    jsonb_build_array('<noreply@probe-never-sent.com> <bob@probe-never-sent.com>', true),     -- multiple <>: the first decides
    jsonb_build_array('Alerts <noreply@probe-never-sent.com', true),                         -- unclosed <
    jsonb_build_array('bounce-12345-abc@probe-never-sent.com', true),                         -- VERP
    jsonb_build_array('team-bounces@lists.probe-never-sent.com', true),
    jsonb_build_array('postmaster+abuse@probe-never-sent.com', true),
    jsonb_build_array('no.reply@probe-never-sent.com', true),
    jsonb_build_array('do.not.reply@probe-never-sent.com', true),
    jsonb_build_array('SRS0=ab12=cd=probe-never-sent.com=noreply@probe-never-sent.com', true),     -- SRS
    jsonb_build_array('msprvs1=19abc=bounces-1234@probe-never-sent.com', true),               -- BATV
    -- people
    jsonb_build_array('Bounce Fitness <info@probe-never-sent.com>', false),                   -- the word is in the display name
    jsonb_build_array('Postmaster General <pm@probe-never-sent.com>', false),
    jsonb_build_array('bounce.fitness@probe-never-sent.com', false),                          -- review of #1691: the word
    jsonb_build_array('bounce-house@probe-never-sent.com', false),                            -- is a person's own name
    jsonb_build_array('bounce_kids@probe-never-sent.com', false),
    jsonb_build_array('bounce2024@probe-never-sent.com', false),
    jsonb_build_array('postmaster.general@probe-never-sent.com', false),
    jsonb_build_array('postmaster-ali@probe-never-sent.com', false),
    jsonb_build_array('john_bounce@probe-never-sent.com', false),
    jsonb_build_array('Alice <alice.noreply.fan@probe-never-sent.com>', false),               -- a dot does not open the word
    jsonb_build_array('noreplying@probe-never-sent.com', false),                              -- a longer word
    jsonb_build_array('donotreplyteam@probe-never-sent.com', false),
    jsonb_build_array('bounced.cheque@probe-never-sent.com', false),
    jsonb_build_array('alice+noreply@probe-never-sent.com', false),                           -- a plus does not open the word
    jsonb_build_array('noreen@probe-never-sent.com', false),
    jsonb_build_array('info@noreply-studio.probe-never-sent.com', false),                     -- the word is in the domain
    jsonb_build_array('bruno.reply@probe-never-sent.com', false),
    jsonb_build_array('"noreply@spoof.probe-never-sent.com" <bob@probe-never-sent.com>', false),     -- quoted @
    jsonb_build_array('"Mailer-Daemon@x.probe-never-sent.com" <carol.ops@probe-never-sent.com>', false),
    jsonb_build_array('"Support <noreply@spoof.probe-never-sent.com>" <bob@probe-never-sent.com>', false), -- quoted < (review miss 1)
    jsonb_build_array('"noreply@spoof.probe-never-sent.com" bob@probe-never-sent.com', false),       -- quoted @, bare (review miss 2)
    jsonb_build_array('Bob <bob@probe-never-sent.com> <noreply@probe-never-sent.com>', false),     -- multiple <>: the first decides
    jsonb_build_array('Bob <bob@probe-never-sent.com', false),                                -- unclosed <
    jsonb_build_array('BOB@PROBE-NEVER-SENT.COM', false),                                     -- uppercase
    jsonb_build_array('', false));                                                            -- no address
begin
  begin
    v_has_fn := to_regprocedure('public.fn_is_machine_sender(text)') is not null;

    -- the ACL and shape of the shared rule, and of the two callers
    if v_has_fn then
      if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_is_machine_sender') <> 1 then
        f := f || text 'fn_is_machine_sender has more than one overload'; end if;
      if (select provolatile from pg_proc where oid = 'public.fn_is_machine_sender(text)'::regprocedure) <> 'i' then
        f := f || text 'fn_is_machine_sender is not immutable'; end if;
      if not exists (select 1 from pg_proc where oid = 'public.fn_is_machine_sender(text)'::regprocedure
                        and array_to_string(proconfig, ',') like '%search_path=%') then
        f := f || text 'fn_is_machine_sender has no pinned search_path'; end if;
      if has_function_privilege('anon', 'public.fn_is_machine_sender(text)', 'execute')
         or has_function_privilege('authenticated', 'public.fn_is_machine_sender(text)', 'execute') then
        f := f || text 'fn_is_machine_sender is callable by anon/authenticated'; end if;
      if not has_function_privilege('service_role', 'public.fn_is_machine_sender(text)', 'execute') then
        f := f || text 'fn_is_machine_sender is not callable by service_role'; end if;
      if (select prosrc from pg_proc where oid = 'public.fn_support_reply_watch_tick()'::regprocedure) not like '%fn_is_machine_sender(m.from_email)%' then
        f := f || text '(a) fn_support_reply_watch_tick does not call fn_is_machine_sender'; end if;
      if (select prosrc from pg_proc where oid = 'public.fn_support_email_is_a_customer_contact(text,text,text,text,boolean)'::regprocedure) not like '%fn_is_machine_sender(p_from)%' then
        f := f || text '(b) fn_support_email_is_a_customer_contact does not call fn_is_machine_sender'; end if;
    else
      f := f || text 'fn_is_machine_sender(text) does not exist';
    end if;
    if has_function_privilege('anon', 'public.fn_support_reply_watch_tick()', 'execute')
       or has_function_privilege('authenticated', 'public.fn_support_reply_watch_tick()', 'execute')
       or has_function_privilege('anon', 'public.fn_support_email_is_a_customer_contact(text,text,text,text,boolean)', 'execute')
       or has_function_privilege('authenticated', 'public.fn_support_email_is_a_customer_contact(text,text,text,text,boolean)', 'execute') then
      f := f || text 'a caller (a) or (b) is callable by anon/authenticated'; end if;

    -- the table: one sender at a time, (a) measured by the tick's own over_sla count (never its 20-id list)
    v := public.fn_support_reply_watch_tick();
    v_prev := coalesce((v->'email'->>'over_sla')::int, 0);
    v_over := make_interval(hours => ceil(coalesce((v->>'sla_hours')::numeric, 24))::int + 1);   -- just past the SLA
    for i in 0 .. jsonb_array_length(v_cases) - 1 loop
      v_from := v_cases->i->>0; v_machine := (v_cases->i->>1)::boolean;
      v_fn := null;
      if v_has_fn then execute 'select public.fn_is_machine_sender($1)' into v_fn using v_from; end if;
      insert into public.inbound_messages (from_email, to_email, subject, body, created_at)
      values (v_from, 'zz.support.watch.probe@probe-never-sent.com', 'ZZ DEMO machine sender probe', 'probe', now() - v_over);
      v := public.fn_support_reply_watch_tick();
      v_now := coalesce((v->'email'->>'over_sla')::int, 0);
      v_a := (v_now = v_prev);                 -- not counted as a customer waiting = treated as a machine
      if v_now not in (v_prev, v_prev + 1) then f := f || ('(a) over_sla moved by ' || (v_now - v_prev) || ' for one message'); end if;
      v_prev := v_now;
      v_b := not public.fn_support_email_is_a_customer_contact(v_from, 'zz.support.watch.probe@probe-never-sent.com', null, 'probe', false);
      v_rows := v_rows || format('%s %-7s | fn %-7s | (a) %-7s | (b) %-7s | %s',
        lpad((i + 1)::text, 2, '0'), yn[v_machine::int + 1],
        coalesce(yn[v_fn::int + 1], 'absent') || case when v_fn is distinct from v_machine then '!' else '' end,
        yn[v_a::int + 1] || case when v_a <> v_machine then '!' else '' end,
        yn[v_b::int + 1] || case when v_b <> v_machine then '!' else '' end, v_from);
      if v_fn is distinct from v_machine and v_has_fn then f := f || format('fn wrong on %s', v_from); end if;
      if v_a <> v_machine then f := f || format('(a) wrong on %s', v_from); end if;
      if v_b <> v_machine then f := f || format('(b) wrong on %s', v_from); end if;
    end loop;

    -- step 5: stored inbound email that changes side, old rule of each routine vs the shared rule (read only;
    -- the probe's own rows are excluded by their subject)
    select count(*) into v_total from public.inbound_messages where coalesce(subject, '') <> 'ZZ DEMO machine sender probe';
    if v_has_fn then
      execute $q$
        select count(*) filter (where old_a is distinct from now_m), count(*) filter (where old_b is distinct from now_m)
          from (select coalesce(substring(m.from_email from '<([^<>\s"]+)@'), substring(m.from_email from '([^<>\s"]+)@'), '')
                         ~* '(^|[-_])(no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon)([-_+.0-9]|$)' as old_a,
                       coalesce(m.from_email, '') ~* '^[^@]*(mailer-daemon|postmaster|no-?reply|do-?not-?reply|bounces?)[^@]*@' as old_b,
                       public.fn_is_machine_sender(m.from_email) as now_m
                  from public.inbound_messages m
                 where coalesce(m.subject, '') <> 'ZZ DEMO machine sender probe') z $q$
        into v_old_a, v_old_b;
    end if;
  exception when others then
    f := f || ('PROBE ERROR ' || sqlstate || ': ' || sqlerrm);
  end;

  -- the verdict comes FIRST: the management API cuts an error message at about 2 KB (review of #1691), so whatever
  -- is cut must be the table, never the verdict
  raise exception 'CHK<<%>>',
    case when cardinality(f) = 0
         then 'PROBE OK: fn_is_machine_sender is one immutable overload with a pinned search_path, closed to anon and authenticated; (a) and (b) both call it and agree with it on every case; everything rolled back by this raise'
         else 'PROBE FAILED: ' || array_to_string(f, '; ') end || E'\n'
    || format('cases: %s; stored inbound_messages: %s; change side (a) old->shared: %s; (b) old->shared: %s',
              jsonb_array_length(v_cases), v_total, coalesce(v_old_a::text, 'n/a'), coalesce(v_old_b::text, 'n/a'))
    || E'\n' || array_to_string(v_rows, E'\n');
end $probe$;
