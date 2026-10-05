-- An integration the founder holds no account for is never his decision.
-- Assigned: it_engineer
--
-- MEASURED 5 Oct 2026: the IT digest (notification 84149) asked the founder a DECISION on
-- duty:integration:web_search, "an external connection is down that only its account holder can restore".
-- web_search was the keyless search-engine HTML scrape: no account, no key, and every datacenter call now gets a
-- bot-check (HTTP 202) or a connection reset. Its finding already carried evidence.notify = false (the registry
-- said so), but fn_customer_support_sends_the_it_digest matched the class row 'duty:integration%'
-- (to_founder = true) and never read the flag.
--
-- WHAT THIS CHANGES
--   1. fn_customer_support_sends_the_it_digest: a duty:integration:% finding is a founder line ONLY when the
--      watch marked it notify = true. integration_watch.ts (founderMayBeAsked, same PR) sets notify = false for
--      every keyless endpoint and every registry opt-out; account-backed connections are unchanged (measured
--      over the registry: no other entry changes).
--   2. The CEO's open it.finding handoff 130592 on web_search is closed through fn_it_attach_learning.
--      The finding itself was closed at 16:00 UTC the same day; the scrape is removed in the same PR (think.ts
--      webSearch returns no hits, the registry entry is 'covered'), so it cannot reopen.
--
-- WHAT THIS DOES NOT CHANGE: the 'duty:integration%' class row stays (a refused key on an account he holds is
-- still his line); fn_it_credential_founder_required and ruling 1090 stand as they are.
--
-- Prevented by: supabase/functions/_shared/integration_watch.test.ts (founderMayBeAsked) and the probe below.
--   node scripts/apply_sql.mjs scripts/sql/an_integration_the_founder_holds_no_account_for_is_never_his_decision.sql --apply --ddl

-- == 1. THE DIGEST READS THE WATCH'S FLAG ==========================================================
CREATE OR REPLACE FUNCTION public.fn_customer_support_sends_the_it_digest(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_hour  constant time := time '19:00';                         -- the founder's fixed local time
  v_stub  boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_local timestamp := p_now at time zone 'Asia/Dubai';
  v_key   text := 'it_daily_digest:' || to_char(p_now at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  x record; f public.it_engineer_finding; v_why text; v_his boolean; v_items jsonb := '[]'::jsonb;
  v_event text; v_detail text; v_res jsonb; v_fan jsonb := '[]'::jsonb; v_before bigint;
  n_dec int := 0; n_flt int := 0; n_int int := 0; n_fixed int := 0; n_wait int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('fn_customer_support_sends_the_it_digest'));
  if v_local::time < c_hour then
    return jsonb_build_object('sent', false, 'reason', 'the IT digest leaves at 19:00 Dubai', 'digest_key', v_key);
  end if;
  if exists (select 1 from public.founder_alerts where dedupe_key = v_key) then
    return jsonb_build_object('sent', false, 'reason', 'today''s IT digest was already decided', 'digest_key', v_key);
  end if;

  for x in select a.id, a.detail, a.evidence from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'pending'
              and a.detail->>'type' = 'delivery.request' and a.detail->>'recipient_role' = 'founder'
              and a.detail->>'kind' = 'it_new_bug' and a.evidence->>'digest' = 'pending'
            order by a.id loop
    -- Anything that is not "a new bug nobody could fix" (today: the CEO-silence reports) is the CEO's.
    if coalesce(x.detail->>'dedupe_key', '') !~ '^it_new_bug:' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'instruction 642: kept internal; the CEO is asked every tick until it answers',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    select * into f from public.it_engineer_finding where issue_key = regexp_replace(x.detail->>'dedupe_key', '^it_new_bug:', '');
    if not found or f.closed_at is not null then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'fixed',
        'why', 'closed before the digest: ' || coalesce(f.close_note, 'no finding row'),
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_fixed := n_fixed + 1; continue;
    end if;
    -- FOUNDER RULING 1090 (30 Sep 2026): a credential only he can renew is never a digest line.
    if public.fn_it_credential_founder_required(f.issue_key, f.title, f.evidence) then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 1090: a credential only the founder can renew is recorded by the IT engineer, never sent to him',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    -- 5 OCT 2026 (notifications#84149): the watch marks a failing integration notify=false when no account the
    -- founder holds can restore it (a keyless endpoint, or a registry opt-out). The 'duty:integration%' class
    -- asked him anyway, so the keyless search scrape reached him as a DECISION. It stays the IT engineer's.
    if f.issue_key like 'duty:integration:%' and f.evidence->>'notify' is distinct from 'true' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'the integration watch marked it notify=false: no account the founder holds can restore it; the IT engineer owns it',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    -- His ruling that something is NOT his wins over any pattern that would ask him.
    select c.why, c.to_founder into v_why, v_his from public.it_founder_decision_class c where f.issue_key like c.issue_key_like
     order by c.to_founder, length(c.issue_key_like) desc limit 1;
    if found and not v_his then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', v_why, 'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; v_why := null; continue;
    end if;
    -- FOUNDER RULING 4 OCT 2026: the digest carries ONLY decisions only he can make. A fault, however
    -- old, is the seats' to solve; it stays an open finding on the OS and is never emailed.
    if not found then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 4 Oct 2026: not a decision only the founder can make; the finding stays with the '
               || replace(coalesce(f.evidence->>'owner_seat', 'it_engineer'), '_', ' ') || ' on the OS',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'key', f.issue_key,
      'title', regexp_replace(left(f.title, 140), '[.\s]+$', ''), 'why', v_why);
    n_dec := n_dec + 1;
  end loop;

  if jsonb_array_length(v_items) = 0 then
    if not v_stub then
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      values ('info', 'IT daily digest: nothing needs the founder today',
              jsonb_build_object('fixed', n_fixed, 'internal', n_int, 'waiting', n_wait)::text, 'os', v_key);
    end if;
    return jsonb_build_object('sent', false, 'reason', 'nothing needs him today', 'digest_key', v_key,
                              'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'stubbed', v_stub);
  end if;

  -- One sentence per decision. No line claims work is under way: nothing here is a fault report.
  select string_agg('- DECISION: ' || (i->>'title') || '. Only you can decide this: ' || (i->>'why')
                    || '. The CEO keeps it open until you answer (reference ' || (i->>'key') || ').',
                    E'\n' order by (i->>'id')::bigint)
    into v_detail from jsonb_array_elements(v_items) i;
  v_event := 'IT today: ' || n_dec || ' decision' || case when n_dec > 1 then 's' else '' end || ' for you';
  v_detail := 'The one IT message of the day. It carries only decisions only you can make; every fault stays with '
           || 'the seats on the OS.' || E'\n\n' || v_detail;

  if v_stub then
    v_res := jsonb_build_object('stubbed', true);               -- A TEST NEVER REACHES HIM
  else
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_detail, p_level => 'normal',
                                      p_kind => 'it_daily_digest', p_dedupe_key => v_key, p_owner_agent => 'customer_support');
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
  end if;
  -- Each item told is completed with the digest's notification ids; the delivery watch takes it from there.
  for x in select (i->>'id')::bigint id from jsonb_array_elements(v_items) i loop
    perform public.fn_seat_handoff_complete(x.id, (select (a.evidence - 'waiting') from public.agent_actions a where a.id = x.id)
      || jsonb_build_object('digest', 'sent', 'digest_key', v_key, 'notify', v_res, 'notification_ids', v_fan, 'notification_id', v_fan->0)
      || case when v_stub then jsonb_build_object('stubbed', true) else '{}'::jsonb end);
  end loop;

  return jsonb_build_object('sent', true, 'digest_key', v_key, 'event', v_event, 'detail', v_detail,
                            'decisions', n_dec, 'faults', n_flt, 'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $function$
;

-- == 2. THE OPEN CEO HANDOFF ON THE KEYLESS SCRAPE =================================================
-- Handoff 130592 is a new-bug incident: it closes only through fn_it_attach_learning (cause, fix, regression
-- check, and the reason it is not a playbook class), which closes it as its originator once the finding is closed.
select public.fn_it_attach_learning(a.id,
  'web_search was the keyless search-engine HTML scrape; every datacenter call is answered with a bot-check (HTTP 202) or a connection reset, so it cannot work from the edge by design',
  'scrape removed: think.ts webSearch returns no hits and research degrades to the knowledge base; registry web_search is covered (nothing to probe); the digest keeps notify=false integrations internal',
  'supabase/functions/_shared/integration_watch.test.ts (founderMayBeAsked) and the probe in scripts/sql/an_integration_the_founder_holds_no_account_for_is_never_his_decision.sql',
  null,
  'a removed integration has nothing left to fail; a keyed search provider, when one is held, is wired in think.ts webSearch',
  'it_engineer')
  from public.agent_actions a
 where a.id = 130592 and a.status = 'pending' and a.detail->>'type' = 'it.finding'
   and a.title like '%duty:integration:web_search%';

-- == PROBE =========================================================================================
-- Stubbed digest (app.qd_stub_founder_notify) on 2099 keys; every seeded row is ZZ DEMO; the sub-block
-- rolls back only itself and reports through a verdict row.
create temp table if not exists _qd_probe (verdict text) on commit drop;
do $probe$
declare v_keyless jsonb; v_keyed jsonb; v_out text;
begin
  begin
    perform set_config('app.qd_stub_founder_notify', 'on', true);
    perform public.fn_it_engineer_finding_upsert('duty:integration:zz_demo_keyless', 'ZZ DEMO keyless endpoint down',
      'probe', 'internal', 1, jsonb_build_object('owner_seat', 'it_engineer', 'demo', true, 'notify', false), '{}'::text[], '{}'::text[], 'it_engineer.probe');
    insert into public.agent_actions (agent, kind, status, title, detail, evidence)
    values ('customer_support', 'handoff', 'pending', 'ZZ DEMO keyless digest probe',
            jsonb_build_object('type', 'delivery.request', 'from', 'it_engineer', 'recipient_role', 'founder', 'kind', 'it_new_bug',
                               'dedupe_key', 'it_new_bug:duty:integration:zz_demo_keyless', 'demo', true, 'subject_table', 'zz_demo', 'subject_id', 'keyless'),
            jsonb_build_object('digest', 'pending'));
    v_keyless := public.fn_customer_support_sends_the_it_digest(timestamptz '2099-02-01 20:00:00+04');
    -- positive control: the same shape on an account he holds (notify = true) is still his line
    perform public.fn_it_engineer_finding_upsert('duty:integration:zz_demo_keyed', 'ZZ DEMO keyed account refused',
      'probe', 'internal', 1, jsonb_build_object('owner_seat', 'it_engineer', 'demo', true, 'notify', true), '{}'::text[], '{}'::text[], 'it_engineer.probe');
    insert into public.agent_actions (agent, kind, status, title, detail, evidence)
    values ('customer_support', 'handoff', 'pending', 'ZZ DEMO keyed digest probe',
            jsonb_build_object('type', 'delivery.request', 'from', 'it_engineer', 'recipient_role', 'founder', 'kind', 'it_new_bug',
                               'dedupe_key', 'it_new_bug:duty:integration:zz_demo_keyed', 'demo', true, 'subject_table', 'zz_demo', 'subject_id', 'keyed'),
            jsonb_build_object('digest', 'pending'));
    v_keyed := public.fn_customer_support_sends_the_it_digest(timestamptz '2099-02-02 20:00:00+04');
    v_out := case
      when coalesce((v_keyless->>'decisions')::int, 0) <> 0 then 'PROBE FAILED: a notify=false integration reached the founder: ' || v_keyless::text
      when coalesce((v_keyed->>'decisions')::int, 0) <> 1 then 'PROBE FAILED: the notify=true control did not produce exactly 1 line: ' || v_keyed::text
      else 'PROBE OK: notify=false integration kept internal (0 founder lines); notify=true control -> 1 line' end;
    raise exception 'QD_PROBE_ROLLBACK';
  exception when others then
    if sqlerrm <> 'QD_PROBE_ROLLBACK' then v_out := 'PROBE FAILED: ' || left(sqlerrm, 400); end if;
  end;
  insert into _qd_probe values (v_out);
end $probe$;
select verdict from _qd_probe;
