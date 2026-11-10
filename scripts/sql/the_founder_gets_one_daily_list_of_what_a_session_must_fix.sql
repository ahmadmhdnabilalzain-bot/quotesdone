-- THE FOUNDER GETS ONE DAILY LIST OF WHAT A SESSION MUST FIX, ON THE IT DIGEST HE ALREADY RECEIVES.
-- Seat: it_engineer (the list is the IT engineer's; customer_support sends the 19:00 Dubai IT digest, as before). 10 Nov
-- 2026, founder ruling 1574 ("the IT engineer fixes the glitches it can fix itself instead of sending counts of problems").
-- No new email kind: the list rides on kind it_daily_digest, once a day, and only when it has something on it.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   fn_customer_support_sends_the_it_digest sends the founder only decisions in his three categories, else records
--   "nothing needs the founder today". What only a working session can fix had no place to reach him: a duty failing
--   every run (customer_support.knowledge_request_deadline, 8 runs since 1 Nov, a code defect), a question the model
--   cannot answer by its deadline (316 overdue once the record is settled, 176 of them it_engineer.postmortem; 3 a
--   person's WhatsApp turn), and what a playbook refused to touch (a document backup with no source; 2 model callers no
--   seat owns). The founder starts the sessions, so the list is his to see, as one list, not as one email per item.
--
-- WHAT THIS CHANGES:
--   1. fn_it_session_fix_list(): at most 12 plain lines, in words, no internal key: seat duties failing 3+ runs in a
--      row; safe-fix families parked after two failed runs; what a playbook refused in the last day (grouped); and the
--      parked model questions past their deadline, grouped by seat and surface, a person-facing one first.
--   2. fn_customer_support_sends_the_it_digest (the live body of 10 Nov 2026, pg_get_functiondef): the list is appended
--      under "What a working session must fix", and the digest goes out when it has decisions OR list lines. Decisions
--      are still chosen exactly as before (his three categories); the list never asks him to decide anything.
--   CREATE OR REPLACE keeps the digest's ACL; the new routine is revoked.
--
-- Prevented by: scripts/checks/the_founder_gets_one_daily_list_of_what_a_session_must_fix.test.mjs (static: one kind,
-- no keys in the founder text, decisions unchanged; rolled-back replay: the list today, and the digest it would send).
--   node scripts/apply_sql.mjs scripts/sql/the_founder_gets_one_daily_list_of_what_a_session_must_fix.sql --apply --ddl --seat it_engineer

create or replace function public.fn_it_session_fix_list()
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '[]'::jsonb;
begin
  with words as (
    -- 1. a duty failing run after run is a defect a session fixes
    select 1 as rank, d.failures::int as n,
           'The ' || replace(split_part(d.duty, '.', 2), '_', ' ') || ' duty of the ' || replace(d.owner_seat, '_', ' ') || ' seat has failed '
             || d.failures || ' runs in a row: ' || public.fn_trim_at_word(replace(regexp_replace(coalesce(d.last_error, 'no error recorded'), '\s+', ' ', 'g'), '_', ' '), 140) as line
      from public.seat_duty d where d.enabled and coalesce(d.failures, 0) >= 3
    union all
    -- 2. a safe-fix playbook that stopped after two failed runs
    select 2, 1, 'The ' || replace(f.family, '_', ' ') || ' playbook stopped itself: ' || public.fn_trim_at_word(replace(coalesce(f.parked_reason, 'two failed runs'), '_', ' '), 140)
      from public.it_safe_fix_family f where not f.active and f.parked_at is not null
    union all
    -- 3. what a playbook refused to touch in the last day, by family
    select 3, count(*)::int, 'The ' || replace(r.family, '_', ' ') || ' playbook could not act on ' || count(*) || ' item(s): '
             || public.fn_trim_at_word(replace(coalesce(max(coalesce(r.result->>'why', r.result->'refused'->0->>'why')), 'its guardrail refused'), '_', ' '), 140)
      from public.it_safe_fix_run r where r.outcome = 'refused_by_guardrail' and r.ran_at > now() - interval '26 hours'
     group by r.family
    union all
    -- 4. questions the model could not answer by their deadline, a person-facing one first
    select case when public.fn_held_question_is_person_facing(q.surface) then 0 else 4 end, count(*)::int,
           count(*) || ' question(s) for the ' || replace(a.agent, '_', ' ') || ' seat on ' || replace(replace(coalesce(q.surface, 'an unknown surface'), '_', ' '), '.', ': ')
             || ' were not answered by their deadline'
             || case when public.fn_held_question_is_person_facing(q.surface) then ' (a person is waiting for the answer)' else '' end
      from public.agent_actions a left join public.reasoning_held_question q on q.id = (a.detail->>'held_id')::bigint
     where a.kind = 'held_question' and a.status = 'pending' and a.detail ? 'overdue_at'
     group by a.agent, q.surface, public.fn_held_question_is_person_facing(q.surface))
  select coalesce(jsonb_agg(jsonb_build_object('rank', rn, 'line', line, 'count', n) order by rn), '[]'::jsonb) into v
    from (select line, n, row_number() over (order by rank, n desc, line) rn from words) z where rn <= 12;
  return v;
end $fn$;
revoke execute on function public.fn_it_session_fix_list() from public, anon, authenticated;

create or replace function public.fn_customer_support_sends_the_it_digest(p_now timestamp with time zone default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  c_hour  constant time := time '19:00';                         -- the founder's fixed local time
  v_stub  boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_local timestamp := p_now at time zone 'Asia/Dubai';
  v_key   text := 'it_daily_digest:' || to_char(p_now at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  x record; f public.it_engineer_finding; v_why text; v_his boolean; v_cat text; v_items jsonb := '[]'::jsonb;
  v_event text; v_detail text; v_res jsonb; v_fan jsonb := '[]'::jsonb; v_before bigint;
  n_dec int := 0; n_flt int := 0; n_int int := 0; n_fixed int := 0; n_wait int := 0;
  v_session jsonb := '[]'::jsonb; v_session_text text; n_sess int := 0;
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
    -- 5 OCT 2026 (notifications#84149): a failing integration with no account he holds stays the IT engineer's.
    if f.issue_key like 'duty:integration:%' and f.evidence->>'notify' is distinct from 'true' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'the integration watch marked it notify=false: no account the founder holds can restore it; the IT engineer owns it',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    -- His ruling that something is NOT his wins over any pattern that would ask him. 19 Oct 2026 (ruling 1254):
    -- a class reaches him only when it also names one of his three categories; to_founder alone is not enough.
    select c.why, c.to_founder, c.founder_category into v_why, v_his, v_cat from public.it_founder_decision_class c
     where f.issue_key like c.issue_key_like
     order by c.to_founder, length(c.issue_key_like) desc limit 1;
    if found and (not v_his or coalesce(v_cat, '') not in ('money', 'destructive_production_change', 'fact_only_he_holds')) then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', coalesce(v_why, 'technical: the class names no founder category'),
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; v_why := null; continue;
    end if;
    -- FOUNDER RULING 4 OCT 2026: the digest carries ONLY decisions only he can make.
    if not found then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 4 Oct 2026: not a decision only the founder can make; the finding stays with the '
               || replace(coalesce(f.evidence->>'owner_seat', 'it_engineer'), '_', ' ') || ' on the OS',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'key', f.issue_key, 'category', v_cat,
      'title', public.fn_trim_at_word(regexp_replace(f.title, '[.\s]+$', ''), 160), 'why', v_why);
    n_dec := n_dec + 1;
  end loop;

  -- 10 Nov 2026 (ruling 1574): the ONE daily list of what only a working session can fix rides on this digest, never a
  -- second email: failing duties, stopped playbooks, what a playbook could not act on, questions past their deadline.
  v_session := coalesce(public.fn_it_session_fix_list(), '[]'::jsonb);
  n_sess := jsonb_array_length(v_session);

  if jsonb_array_length(v_items) = 0 and n_sess = 0 then
    if not v_stub then
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      values ('info', 'IT daily digest: nothing needs the founder today',
              jsonb_build_object('fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'session_items', 0)::text, 'os', v_key);
    end if;
    return jsonb_build_object('sent', false, 'reason', 'nothing needs him today', 'digest_key', v_key,
                              'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'stubbed', v_stub);
  end if;

  -- One plain line per decision: what it is, and why only he can act. No internal keys or ids.
  select string_agg('- ' || (i->>'title') || '.' || E'\n  Why this needs you: '
                    || case i->>'category'
                         when 'money' then 'it spends or returns company money.'
                         when 'destructive_production_change' then 'it would remove or overwrite live company data.'
                         else coalesce(nullif(regexp_replace(i->>'why', '[.\s]+$', ''), ''),
                                       'only you hold the account or the fact it needs') || '.'
                       end,
                    E'\n' order by (i->>'id')::bigint)
    into v_detail from jsonb_array_elements(v_items) i;
  -- One plain line per thing a working session must fix (fn_it_session_fix_list writes them in words, no keys).
  select string_agg('- ' || (s->>'line') || '.', E'\n' order by (s->>'rank')::int)
    into v_session_text from jsonb_array_elements(v_session) s;
  v_event := case when n_dec > 0 then 'IT: ' || n_dec || case when n_dec > 1 then ' things only you can decide' else ' thing only you can decide' end
                  else 'IT: what a working session must fix today' end;
  v_detail := case when n_dec > 0
                   then 'Everything else today is being handled by the team; this is only what needs you.' || E'\n\n' || v_detail
                        || E'\n\n' || 'Reply to this email with your answer and the CEO will act on it.'
                   else 'No decision of yours is needed today.' end
           || case when n_sess > 0
                   then E'\n\n' || 'What a working session must fix (the team cannot: each needs a change to code, access or infrastructure):'
                        || E'\n' || v_session_text
                   else '' end;

  if v_stub then
    v_res := jsonb_build_object('stubbed', true);               -- A TEST NEVER REACHES HIM
  else
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_detail, p_level => 'normal',
                                      p_kind => 'it_daily_digest', p_dedupe_key => v_key, p_owner_agent => 'it_engineer');   -- 19 Oct 2026: the IT engineer owns its digest
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
  end if;
  for x in select (i->>'id')::bigint id from jsonb_array_elements(v_items) i loop
    perform public.fn_seat_handoff_complete(x.id, (select (a.evidence - 'waiting') from public.agent_actions a where a.id = x.id)
      || jsonb_build_object('digest', 'sent', 'digest_key', v_key, 'notify', v_res, 'notification_ids', v_fan, 'notification_id', v_fan->0)
      || case when v_stub then jsonb_build_object('stubbed', true) else '{}'::jsonb end);
  end loop;

  return jsonb_build_object('sent', true, 'digest_key', v_key, 'event', v_event, 'detail', v_detail,
                            'decisions', n_dec, 'session_items', n_sess, 'faults', n_flt, 'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $function$;

-- already closed to clients on production (10 Nov 2026); restated so the file says so itself
revoke execute on function public.fn_customer_support_sends_the_it_digest(timestamp with time zone) from public, anon, authenticated;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_it_session_fix_list()'::regprocedure, 'public.fn_customer_support_sends_the_it_digest(timestamptz)'::regprocedure)
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the digest does not read the session list'
     where position('fn_it_session_fix_list' in (select prosrc from pg_proc where oid = 'public.fn_customer_support_sends_the_it_digest(timestamptz)'::regprocedure)) = 0
    union all select 'the list has a line with an internal key: ' || (x->>'line') from jsonb_array_elements(public.fn_it_session_fix_list()) x
     where x->>'line' ~ 'duty:|[a-z]+_[a-z]+_[a-z]+'
  ) z) y;
