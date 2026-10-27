-- PROBE: the first-reply watch exempts machine senders and its close note says why it closed (27 Oct 2026).
-- Assigned: customer_support.
--
-- No DDL. Run AFTER support_reply_watch_exempts_machine_senders_and_says_why_it_closed.sql is applied (or in
-- the same transaction, ahead of it, ending in a raise so both roll back). Returns ONE verdict row:
-- 'PROBE OK …' or 'PROBE FAILED: <reasons>'. Against the body live on 27 Oct 2026 it returns PROBE FAILED.
--
-- Every write is inside a block its own raise rolls back, then asserted gone. Fixture senders are on
-- probe-never-sent.com: the watch skips @example.invalid as a demo address (fn_is_demo_email), so the
-- fixtures must be a domain it counts, and the watch sends nothing; the rows never commit either way.
-- The one real row it reads and must not disturb is it_engineer_finding 'support_reply_sla:email': its
-- closed_at and close_note are captured before and compared after.
create temp table if not exists zz_support_watch_probe (verdict text) on commit drop;
do $probe$
declare
  f text[] := '{}';
  v jsonb; v_prev int; v_now int; v_e0 int; v_id bigint; v_aged bigint; v_replied bigint;
  v_addr text; v_counted boolean; v_note text; v_left int; v_e2e text := '';
  v_real_closed timestamptz; v_real_note text; v_has_note_fn boolean; v_over interval;
  v_cases jsonb := jsonb_build_array(
    -- [sender, counted as a customer waiting?]
    jsonb_build_array('LinkedIn <security-noreply@probe-never-sent.com>', false),   -- the measured miss, 23 Sep
    jsonb_build_array('MAILER-DAEMON@probe-never-sent.com', false),
    jsonb_build_array('alerts_no_reply+bounce@probe-never-sent.com', false),
    jsonb_build_array('account-do-not-reply@probe-never-sent.com', false),
    jsonb_build_array('notifications-donotreply@probe-never-sent.com', false),
    jsonb_build_array('noreply@probe-never-sent.com', false),                       -- the old rule, kept
    jsonb_build_array('Alice <alice.noreply.fan@probe-never-sent.com>', true),       -- a person: dot-separated name
    jsonb_build_array('alice+noreply@probe-never-sent.com', true),                   -- a person's own sub-address
    jsonb_build_array('noreen@probe-never-sent.com', true),
    jsonb_build_array('bruno.reply@probe-never-sent.com', true));
begin
  select closed_at, close_note into v_real_closed, v_real_note
    from public.it_engineer_finding where issue_key = 'support_reply_sla:email';

  -- ── structure ──
  v_has_note_fn := to_regprocedure('public.fn_support_reply_watch_close_note(text,jsonb,numeric)') is not null;
  if not v_has_note_fn then
    f := f || text 'fn_support_reply_watch_close_note(text,jsonb,numeric) does not exist: the close note cannot say what cleared the messages';
  elsif has_function_privilege('anon', to_regprocedure('public.fn_support_reply_watch_close_note(text,jsonb,numeric)'), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.fn_support_reply_watch_close_note(text,jsonb,numeric)'), 'execute')
     or not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.fn_support_reply_watch_close_note(text,jsonb,numeric)')
                     and array_to_string(p.proconfig, ',') like '%search_path%') then
    f := f || text 'fn_support_reply_watch_close_note is callable by anon/authenticated or has no pinned search_path';
  end if;
  if has_function_privilege('anon', 'public.fn_support_reply_watch_tick()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_support_reply_watch_tick()', 'execute') then
    f := f || text 'fn_support_reply_watch_tick is callable by anon/authenticated'; end if;

  begin
    -- ── 1. who is a customer waiting: one sender at a time, measured by the tick's own over_sla count ──
    v := public.fn_support_reply_watch_tick();
    v_e0 := coalesce((v->'email'->>'over_sla')::int, 0);
    v_over := make_interval(hours => ceil(coalesce((v->>'sla_hours')::numeric, 24))::int + 1);   -- just past the live SLA
    v_prev := v_e0;
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
    delete from public.inbound_messages where from_email like '%@probe-never-sent.com%';

    -- ── 2. the close note, case by case ──
    insert into public.inbound_messages (from_email, to_email, subject, body, created_at)
    values ('zz.aged.customer@probe-never-sent.com', 'zz.support.watch.probe@probe-never-sent.com', 'ZZ DEMO support watch probe', 'probe', now() - interval '31 days')
    returning id into v_aged;
    insert into public.inbound_messages (from_email, to_email, subject, body, created_at, replied_at)
    values ('zz.replied.customer@probe-never-sent.com', 'zz.support.watch.probe@probe-never-sent.com', 'ZZ DEMO support watch probe', 'probe', now() - interval '3 days', now() - interval '2 days')
    returning id into v_replied;
    if v_has_note_fn then
      v_note := public.fn_support_reply_watch_close_note('email', jsonb_build_object('ids', jsonb_build_array(v_aged), 'waiting', 1), 24);
      if v_note like '%every one%' or v_note not like '%aged out%' or v_note not like '%NOT because they were answered%' then
        f := f || ('a message that aged out unanswered was not said to have aged out: ' || v_note); end if;
      v_note := public.fn_support_reply_watch_close_note('email', jsonb_build_object('ids', jsonb_build_array(v_replied), 'waiting', 1), 24);
      if v_note not like '%every one of the 1 waiting message(s) got a first reply%' then
        f := f || ('a channel cleared by a reply did not say so: ' || v_note); end if;
      v_note := public.fn_support_reply_watch_close_note('email', jsonb_build_object('ids', jsonb_build_array(v_aged, v_replied), 'waiting', 5), 24);
      if v_note like '%every one%' or v_note not like '%1 got a first reply%' or v_note not like '%1 aged out%' or v_note not like '%other 3%' then
        f := f || ('a mixed close (1 replied, 1 aged, 3 unlisted) was not stated as such: ' || v_note); end if;
      v_note := public.fn_support_reply_watch_close_note('email', jsonb_build_object('ids', jsonb_build_array(v_replied), 'waiting', 3), 24);
      if v_note like '%every one%' then
        f := f || ('replies were claimed for messages it never listed: ' || v_note); end if;
      v_note := public.fn_support_reply_watch_close_note('email', '{}'::jsonb, 24);
      if v_note like '%got a first reply%' or v_note not like '%not known%' then
        f := f || ('a close with no recorded list claimed an outcome: ' || v_note); end if;
    end if;

    -- ── 3. end to end, the 23 Oct shape: a listed message ages out and the finding closes ──
    -- Only possible while no real email is waiting (the channel must be clear for the close branch to run).
    if v_e0 = 0 then
      perform public.fn_it_engineer_finding_upsert('support_reply_sla:email', 'ZZ DEMO probe: 1 email message waiting',
        'customer_support first-reply watch (fn_support_reply_watch_tick) -> email', 'customer_facing', 1,
        jsonb_build_object('channel', 'email', 'waiting', 1, 'ids', jsonb_build_array(v_aged)), '{}'::text[], '{}'::text[], 'customer_support');
      v := public.fn_support_reply_watch_tick();
      select close_note into v_note from public.it_engineer_finding where issue_key = 'support_reply_sla:email' and closed_at is not null;
      if v_note is null then
        f := f || text 'the email finding did not close once its only message aged out';
      elsif v_note like '%has a first reply%' or v_note like '%every one%' or v_note not like '%aged out%' then
        f := f || ('the close note claims replies that never happened: "' || v_note || '"');
      end if;
    else
      v_e2e := ' (end-to-end close not exercised: ' || v_e0 || ' real email(s) waiting)';
    end if;

    raise exception 'zz_support_watch_probe_done';
  exception when others then
    if sqlerrm <> 'zz_support_watch_probe_done' then f := f || ('the rehearsal raised: ' || sqlerrm); end if;
  end;

  -- ── nothing left behind ──
  select count(*) into v_left from public.inbound_messages where from_email like '%@probe-never-sent.com%';
  if v_left <> 0 then f := f || (v_left || ' probe message(s) survived the rollback'); end if;
  if exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:email'
              and (closed_at is distinct from v_real_closed or close_note is distinct from v_real_note)) then
    f := f || text 'the real support_reply_sla:email finding was changed'; end if;

  insert into zz_support_watch_probe values (case when cardinality(f) = 0
    then 'PROBE OK: security-noreply, MAILER-DAEMON, no_reply, do-not-reply and donotreply senders are exempt anywhere in the local part; alice.noreply.fan, alice+noreply, noreen and bruno.reply are still counted; the close note says answered, aged out or not listed and never claims a reply that did not happen; nothing left behind' || v_e2e
    else 'PROBE FAILED: ' || array_to_string(f, '; ') end);
end $probe$;
select verdict from zz_support_watch_probe;
