-- The IT digest reaches the founder only with his kind of decision, written in whole words (19 Oct 2026).
-- Assigned: it_engineer
--
-- MEASURED 19 Oct 2026 on production, after #1446 (a_technical_item_is_never_a_decision_for_the_founder.sql,
-- MANIFEST line 2035) was applied:
--   - it_founder_decision_class: only duty:credential:%, duty:access:% and duty:integration% still say
--     to_founder, all three with founder_category = fact_only_he_holds; the two independence families are false.
--   - 435 pending it_new_bug handoffs, 35 of them on open findings; none of the 35 matches a to_founder class.
--     So with today's data the 19:00 Dubai digest sends nothing. #1446 closed the routing.
--   - What #1446 did not touch is the email itself (notifications 101206): the title was cut with
--     left(title, 140), so the founder read "...or the chosen reviewer fai." and "(or 'u."; every line ended
--     with an internal reference key he cannot use; and the digest trusted to_founder alone, so a class row
--     whose category was later emptied would still mail him.
--
-- WHAT THIS CHANGES
--   1. fn_trim_at_word(text, int): shortens text at the last whole word and adds an ellipsis; never mid-word.
--   2. fn_customer_support_sends_the_it_digest:
--      - an item reaches the email only when its class says to_founder AND names one of his three categories
--        (money, destructive_production_change, fact_only_he_holds); anything else stays with the seats;
--      - each line is the title in whole words plus one plain sentence on why only he can act, with no
--        internal keys or ids; the subject says what it is in words.
--
-- WHAT THIS DOES NOT CHANGE: which findings exist, the 19:00 Dubai send time, ruling 1090 (credentials he must
-- renew are never digest lines), or the integration notify flag (an_integration_the_founder_holds_...sql).
-- Prevented by: scripts/checks/the_it_digest_reaches_the_founder_only_with_his_kind_of_decision.test.mjs

-- == 1. SHORTEN AT A WORD, NEVER INSIDE ONE ===========================================================
create or replace function public.fn_trim_at_word(p_text text, p_max integer)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select case
    when p_text is null or p_max is null or length(p_text) <= p_max then p_text
    else coalesce(nullif(regexp_replace(regexp_replace(left(p_text, p_max + 1), '\s+\S*$', ''), '[\s.,;:(\-]+$', ''), ''),
                  left(p_text, p_max)) || '…'
  end
$function$;
comment on function public.fn_trim_at_word(text, integer) is
  'Shortens text to at most p_max characters at the last whole word, with an ellipsis. Never cuts inside a word.';
revoke execute on function public.fn_trim_at_word(text, integer) from public, anon, authenticated;

-- == 2. THE DIGEST =====================================================================================
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
  x record; f public.it_engineer_finding; v_why text; v_his boolean; v_cat text; v_items jsonb := '[]'::jsonb;
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

  if jsonb_array_length(v_items) = 0 then
    if not v_stub then
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      values ('info', 'IT daily digest: nothing needs the founder today',
              jsonb_build_object('fixed', n_fixed, 'internal', n_int, 'waiting', n_wait)::text, 'os', v_key);
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
  v_event := 'IT: ' || n_dec || case when n_dec > 1 then ' things only you can decide' else ' thing only you can decide' end;
  v_detail := 'Everything else today is being handled by the team; this is only what needs you.' || E'\n\n' || v_detail
           || E'\n\n' || 'Reply to this email with your answer and the CEO will act on it.';

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
                            'decisions', n_dec, 'faults', n_flt, 'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $function$;

-- == PROBE (verdict row; the file defines routines, so it never raises) ===============================
select case
  when public.fn_trim_at_word('or the chosen reviewer failed', 26) <> 'or the chosen reviewer…'
    then 'PROBE FAILED: trim cut inside a word: ' || public.fn_trim_at_word('or the chosen reviewer failed', 26)
  when public.fn_trim_at_word('short', 26) <> 'short' then 'PROBE FAILED: trim changed a short text'
  when (select count(*) from public.it_founder_decision_class where to_founder and coalesce(founder_category, '') not in
         ('money', 'destructive_production_change', 'fact_only_he_holds')) > 0 then 'PROBE FAILED: a founder class without his category'
  else 'PROBE OK' end as verdict;
