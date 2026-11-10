-- THE CEO APPLIES ITS SAFETY-SIDE GROWTH POWERS WITHOUT WAITING FOR A SWITCH.     seat: ceo · 10 Nov 2026 · ledger 1438, 1455, 1609
-- Assigned: ceo
--
-- Founder, ledger 1609 (10 Nov 2026): "Any decision that could harm the company (e.g. 100 invitations a day that would get
-- the e-mail domain banned) needs proper reasoning and must respect the safety limits", and "no decision goes to him".
-- Ledger 1455: "I can't decide for the CEO and take responsibility if the email got blocked. The cap, you are more aware
-- about it than me." Ledger 1438: "The plan goes to the CEO and the CEO acts."
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026 ~20:10Z):
--   * app_secrets.ceo_growth_act_golive = 'false' since 2 Nov. ceo_growth_action holds 101 rows and every decision of 2-10
--     Nov reads applied = false. Each day from 2 Nov the CEO decided to halve the invitation cap on the bounce brake
--     ("brake: 4 bounced of 35 in 7 days against a limit of 0.05"), to send only to checked addresses ("unchecked leads
--     bounced 9 of 35") and, on 10 Nov, to close the supplier mailbox ("bounces 4 of 35 are over twice the limit").
--     None of it happened: invite_daily_cap is still 20, invite_reachable_only is still false.
--   * fn_invite_send_health: 11 bounced of 97 sent in 30 days (11.3 %), 3 of 40 in 7 days, 0 complaints.
--   * Meanwhile the CEO note the founder received on 5, 6, 8 and 9 Nov said "sending slows down and bad addresses are
--     removed before anything else goes out" (notifications 129419, 129423, 129431, 129448). The brake that would have
--     done that was the one held behind the switch.
--   A switch that holds back a decision to send LESS is a safety limit pointing the wrong way: the only thing it can stop
--   is the brake.
--
-- WHAT THIS FILE CHANGES
--   1. fn_ceo_growth_power_is_safe(action, reading, restore_cap), pure: a decision is safety-side when it can only lower
--      risk or give back what the CEO itself took. Safety-side: a cap cut; a cap raise no higher than the cap the CEO cut
--      from in the last 60 days (a give-back, never past the founder's schedule, which fn_ceo_growth_act still clamps);
--      only checked addresses; closing the supplier mailbox; re-opening it on the decide rule's own terms (7 days after
--      the CEO's own close, placement open, checked addresses only, no complaint, no brake); closing WhatsApp; the trade
--      order inside the pool the gates already allow; a directive to a seat (an internal order with a done test).
--      NOT safety-side, still behind ceo_growth_act_golive: raising the ceiling (ledger 1455's +10 step), a cap raise past
--      what the CEO took, sending to unchecked addresses again, opening WhatsApp.
--   2. fn_ceo_growth_act applies a decision when the switch is on OR the decision is safety-side, counts the safety-side
--      ones in its run row, and always lets the review roll back a raise (every rollback lowers).
--   3. fn_ceo_growth_decide: the brake halves to a floor of 5 a day, not 1. At 2 a day the 7-day window holds 10 weekday
--      sends, under the 15 a rate needs (bounce_rate_7d is null below 15), so neither a brake nor a clean week could ever
--      move the cap again. Once safety-side cuts apply by themselves that trap would be reached in three days.
--
-- WHAT THIS DOES NOT CHANGE: the switch itself (it stays as the founder's sessions left it); the sender's own brakes in
-- enqueue_supplier_invites, fn_invite_same_day_brake and the invite_restart probation, which still stop the campaign on
-- their own readings; the placement gate (ledger 1312); ledger 1456 (no ads: nothing here can spend); ledger 1231's
-- schedule, which remains the ceiling every cap is clamped to; WhatsApp's opt-in, template and HIGH-reading conditions.
--
-- Prevented by: scripts/checks/the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.test.mjs
--   (static: every lever is written under the per-decision test, the ceiling stays behind the switch; replay with a token:
--   the classifier on every decision kind, and the brake floor).
-- Rehearsed rolled back: node scripts/ci/rehearse_sql.mjs <this file> <this file's _probe.sql>
-- Apply at merge: node scripts/apply_sql.mjs scripts/sql/the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.sql --apply --ddl --seat ceo

-- 1. THE CLASSIFIER ---------------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_growth_power_is_safe(p_action jsonb, p_reading jsonb, p_restore_cap integer)
returns boolean language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case p_action->>'power'
    when 'cap' then
      case when (p_action->>'to') !~ '^[0-9]+$' or coalesce(p_reading->>'cur_cap', '') !~ '^[0-9]+$' then false
           when (p_action->>'to')::int < (p_reading->>'cur_cap')::int then true               -- a cut
           when p_restore_cap is not null and (p_action->>'to')::int <= p_restore_cap then true -- a give-back of its own cut
           else false end
    when 'reachable' then coalesce(p_action->>'to', '') = 'true'                              -- checked addresses only
    when 'channel' then
      case when coalesce(p_action->>'to', '') = 'close' then true
           when p_action->>'subject' = 'email_supplier_mailbox' and p_action->>'to' = 'open'
                and coalesce(p_reading->>'own_pause_days_ago', '') ~ '^[0-9]+$' then true        -- undoing its own close only
           else false end
    when 'trade' then true        -- order inside the pool the gates already allow; no volume, no new address
    when 'directive' then true    -- an internal order with a done test; it sends nothing
    else false                    -- 'ceiling' and anything new stay behind ceo_growth_act_golive
  end
$fn$;
revoke execute on function public.fn_ceo_growth_power_is_safe(jsonb, jsonb, integer) from public, anon, authenticated;

-- 2. THE DECISION: the brake floor ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ceo_growth_decide(r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  a jsonb := '[]'::jsonb;
  v_max numeric := (r->>'max_bounce')::numeric;
  v_rate numeric := (r->>'bounce_rate_7d')::numeric;       -- null under 15 sends: not a rate
  v_cur int := (r->>'cur_cap')::int; v_founder int := (r->>'founder_cap')::int;
  v_brake boolean := coalesce((r->>'complained_48h')::int, 0) >= 1 or coalesce(v_rate > v_max, false);
  v_healthy boolean := v_rate is not null and v_rate < 0.02 and coalesce((r->>'complained_7d')::int, 0) = 0;
  v_enabled boolean := (r->>'invite_enabled')::boolean;
  v_reach boolean := (r->>'reachable_only')::boolean;
  v_un_sent int := coalesce((r->>'unchecked_sent')::int, 0);
  v_un_rate numeric := case when v_un_sent >= 10 then (r->>'unchecked_bounced')::numeric / v_un_sent end;
  v_room int := greatest(0, 5 - coalesce((r->>'trade_live')::int, 0));
  v_resume boolean := false; t text;
begin
  -- CAP. Above the founder's schedule always comes down; a brake halves; only clean mail raises, one step, never past the schedule.
  if v_cur > v_founder then
    a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', v_founder, 'review_days', 3,
      'reason', format('ledger 1455: the cap %s is above the ceiling %s', v_cur, v_founder));
  elsif v_brake and v_cur > 5 then
    -- 10 Nov 2026: the brake halves to a floor of 5, never 1. At 2 a day the 7-day window holds 10 weekday sends, under the 15
    -- a rate needs, so v_rate reads null: no brake can fire and no clean week can raise. The cap would be stuck for good.
    a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', greatest(5, v_cur / 2), 'review_days', 3,
      'reason', format('brake: %s bounced of %s in 7 days against a limit of %s, %s complaints in 48 hours', r->>'bounced_7d', r->>'sent_7d', v_max, r->>'complained_48h'));
  elsif v_healthy and v_enabled and v_cur < v_founder then
    a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', least(v_founder, v_cur + 10), 'review_days', 3,
      'reason', format('clean: %s bounced of %s in 7 days, no complaint; the ceiling allows %s', r->>'bounced_7d', r->>'sent_7d', v_founder));
  elsif not v_brake and v_enabled and v_cur >= v_founder and coalesce((r->>'sent_14d')::int, 0) >= 100
        and (r->>'bounced_14d')::numeric / nullif((r->>'sent_14d')::numeric, 0) < 0.01 and coalesce((r->>'complained_7d')::int, 0) = 0
        and coalesce((r->>'open_classes')::int, 0) > 0 and coalesce((r->>'checked_pool_open')::int, 0) >= v_cur * 10
        and coalesce((r->>'ceiling_days_since')::int, 999) >= 7 and not coalesce((r->>'ceiling_failed_recently')::boolean, false) then
    -- LEDGER 1455: on measured health alone, in small steps
    a := a || jsonb_build_object('power', 'ceiling', 'subject', 'invite_ceo_ceiling', 'to', v_founder + 10, 'review_days', 3,
      'reason', format('14 clean days: %s bounced of %s, no complaint, ten days of checked leads', r->>'bounced_14d', r->>'sent_14d'));
  end if;

  -- REACHABILITY. Unchecked addresses stop when their own measured rate is over the limit, and return only when it is not.
  if not v_reach and coalesce(v_un_rate > v_max, false) then
    a := a || jsonb_build_object('power', 'reachable', 'subject', 'invite_reachable_only', 'to', true, 'review_days', 7,
      'reason', format('unchecked leads bounced %s of %s; only checked addresses go until the list is cleaned', r->>'unchecked_bounced', v_un_sent));
  elsif v_reach and coalesce((r->>'checked_pool_open')::int, 0) < v_cur * 5 and coalesce(v_un_rate <= v_max, false) then
    a := a || jsonb_build_object('power', 'reachable', 'subject', 'invite_reachable_only', 'to', false, 'review_days', 7,
      'reason', format('fewer than five days of checked leads remain (%s) and unchecked leads now bounce within the limit', r->>'checked_pool_open'));
  end if;

  -- TRADES. Inside the queue's recruitment tier, the trades with the widest reachable pool go first.
  for t in select value from jsonb_array_elements_text(coalesce(r->'trade_candidates', '[]'::jsonb)) limit v_room loop
    a := a || jsonb_build_object('power', 'trade', 'subject', t, 'to', 'first', 'review_days', 14,
      'reason', format('%s is marked for recruitment and has one of the widest reachable pools', t));
  end loop;

  -- EMAIL. The CEO's own close may be lifted: 7 days on, placement open, only checked addresses, no complaint, and health moved since any earlier reopen.
  v_resume := not v_enabled and (r->>'own_pause_days_ago')::int >= 7 and coalesce((r->>'open_classes')::int, 0) > 0
              and v_reach and coalesce((r->>'complained_7d')::int, 0) = 0 and not coalesce(v_rate > v_max, false)
              and not coalesce((r->>'resume_held_same_health')::boolean, false);
  if v_resume then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'email_supplier_mailbox', 'to', 'open', 'review_days', 7,
      'reason', format('the CEO closed this %s days ago, the window is clean, only checked addresses go', r->>'own_pause_days_ago'));
    if v_cur > 10 then
      a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', 10, 'review_days', 3, 'reason', 'a resume restarts low: the domain cooled during the pause');
    end if;
  elsif v_enabled and coalesce((r->>'sent_7d')::int, 0) >= 30 and coalesce(v_rate > 2 * v_max, false) then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'email_supplier_mailbox', 'to', 'close', 'review_days', 7,
      'reason', format('bounces %s of %s are over twice the limit: ledger 1449, the mailbox is not risked', r->>'bounced_7d', r->>'sent_7d'));
  end if;

  -- WHATSAPP. Open on opt-ins, an approved template, a good reading and no brake, each measured. Close the moment one fails.
  if not (r->>'wa_golive')::boolean and v_enabled and (r->>'wa_opt_ins')::int > 0 and (r->>'wa_template_approved')::boolean
     and (r->>'wa_reading_ok')::boolean and not (r->>'wa_brake')::boolean then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'whatsapp_opt_in', 'to', 'open', 'review_days', 7,
      'reason', format('%s opt-ins, template approved, sender reads HIGH, no brake (ledger 1373)', r->>'wa_opt_ins'));
  elsif (r->>'wa_golive')::boolean and ((r->>'wa_brake')::boolean or not (r->>'wa_reading_ok')::boolean) then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'whatsapp_opt_in', 'to', 'close', 'review_days', 7,
      'reason', 'the WhatsApp brake is open or the sender no longer reads HIGH');
  end if;

  -- DIRECTIVES. Each carries a done test the routine reads; a directive repeats until the test is true.
  if coalesce(v_un_rate > v_max, false) or coalesce(v_rate > v_max, false) then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'bounce_within_limit', 'seat', 'it_engineer', 'days', 7,
      'instruction', 'Bring invitation bounces within the limit: run the free list checks (syntax, typo domains, MX, not_found) over the eligible pool, and name what a paid check would add.',
      'done_when', 'the 7-day invitation bounce rate reads within invite_max_bounce_rate',
      'done_sql', $q$coalesce((public.fn_ceo_growth_reading(now(), true)->>'bounce_rate_7d')::numeric <= (public.fn_ceo_growth_reading(now(), true)->>'max_bounce')::numeric, false)$q$,
      'reason', format('7-day %s of %s; unchecked all-time %s of %s', r->>'bounced_7d', r->>'sent_7d', r->>'unchecked_bounced', v_un_sent));
  end if;
  if coalesce((r->>'started_stuck')::int, 0) > 0 then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'started_not_submitted', 'seat', 'sales_engineer', 'days', 3,
      'instruction', 'A supplier started registration and stopped more than 3 days ago: chase each one to submission.',
      'done_when', 'no real supplier has been started and unsubmitted for over 3 days',
      'done_sql', $q$(public.fn_ceo_growth_reading(now(), true)->>'started_stuck')::int = 0$q$,
      'reason', format('%s started and stopped', r->>'started_stuck'));
  end if;
  if coalesce((r->>'replied_unanswered')::int, 0) > 0 then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'reply_unanswered', 'seat', 'sales_engineer', 'days', 2,
      'instruction', 'An invited supplier replied and has not been answered: answer each one.',
      'done_when', 'no invited supplier''s reply has waited over a day in 30 days',
      'done_sql', $q$(public.fn_ceo_growth_reading(now(), true)->>'replied_unanswered')::int = 0$q$,
      'reason', format('%s replies unanswered', r->>'replied_unanswered'));
  end if;
  if (r->>'wa_opt_ins')::int = 0 then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'whatsapp_opt_ins', 'seat', 'sales_engineer', 'days', 14,
      'instruction', 'Ask the consent question (fn_wa_consent_question) of each supplier who is already in conversation with us, and record each yes with fn_supplier_whatsapp_optin_record. Never message a number to ask it.',
      'done_when', 'at least one real opt-in is on record',
      'done_sql', $q$(public.fn_ceo_growth_reading(now(), true)->>'wa_opt_ins')::int > 0$q$,
      'reason', 'WhatsApp has no opt-in, so it has nobody it may message');
  end if;
  return a;
end $fn$;

-- 3. THE ACT: per-decision application ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ceo_growth_act(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai'; v_today date := v_local::date;
  v_apply boolean := coalesce((select value from public.app_secrets where key = 'ceo_growth_act_golive'), '') = 'true';
  v_read jsonb; v_goal jsonb; v_channels jsonb; v_actions jsonb; d jsonb; v_reviewed int; v_written int := 0; v_applied int := 0;
  v_before text; v_after text; v_founder int; v_dedupe text; v_round int; v_dir bigint; v_ok boolean;
  v_safe boolean; v_safe_n int := 0; v_restore int;
begin
  if v_local::time < time '06:00' then return jsonb_build_object('ok', true, 'ran', false, 'reason', 'before 06:00 Dubai'); end if;
  if exists (select 1 from public.ceo_growth_action where dedupe_key = 'run:' || v_today) then
    return jsonb_build_object('ok', true, 'ran', false, 'reason', 'today''s decision exists');
  end if;

  perform public.fn_ceo_supplier_funnel_refresh(date '2026-01-01');   -- whole history: a late bounce or a backfill changes an old day, and totals sum it
  v_channels := public.fn_ceo_supplier_channel_measure();
  v_read := public.fn_ceo_growth_reading(p_at);
  v_goal := public.fn_ceo_supplier_goal_status(p_at);
  -- A review only ever undoes a raise (a ceiling, a cap step, a WhatsApp open, a trade that drew nothing), so it always applies.
  v_reviewed := public.fn_ceo_growth_review(p_at, v_read, true);
  v_actions := public.fn_ceo_growth_decide(v_read);
  v_founder := (v_read->>'founder_cap')::int;
  -- The highest cap the CEO itself cut from in the last 60 days: a later clean week may give that back, never more.
  select max(x.before_value::int) into v_restore from public.ceo_growth_action x
   where x.power = 'cap' and x.applied and x.decided_on > v_today - 60
     and x.before_value ~ '^[0-9]+$' and x.after_value ~ '^[0-9]+$' and x.after_value::int < x.before_value::int;

  for d in select value from jsonb_array_elements(v_actions) loop
    v_safe := public.fn_ceo_growth_power_is_safe(d, v_read, v_restore);
    v_ok := v_apply or v_safe; v_before := null; v_after := d->>'to'; v_dir := null;
    case d->>'power'
    when 'cap' then
      v_before := v_read->>'cur_cap';
      v_after := least((d->>'to')::int, v_founder)::text;     -- the ceiling, whatever the decision said
      if v_ok then update public.app_secrets set value = v_after where key = 'invite_daily_cap'; end if;
    when 'ceiling' then
      v_before := v_read->>'founder_cap';
      v_after := least((d->>'to')::int, v_founder + 10)::text;     -- one small step, whatever the decision said
      if v_apply then
        update public.app_secrets set value = v_after where key = 'invite_ceo_ceiling';
        update public.app_secrets set value = jsonb_set(value::jsonb, '{ceiling_cap}', to_jsonb(v_after::int))::text where key = 'invite_warmup';   -- the ramp reads both
      end if;
    when 'reachable' then
      v_before := v_read->>'reachable_only';
      if v_ok then update public.app_secrets set value = v_after where key = 'invite_reachable_only'; end if;
    when 'trade' then
      if v_ok then insert into public.ceo_invite_trade_priority (trade, reason) values (d->>'subject', d->>'reason') on conflict do nothing; end if;
    when 'channel' then
      if d->>'subject' = 'email_supplier_mailbox' then
        v_before := v_read->>'invite_enabled';
        if v_ok and d->>'to' = 'open' then
          update public.app_secrets set value = 'true' where key = 'invite_enabled';
        elsif v_ok then
          perform public.fn_invite_campaign_pause('ceo_growth', d->>'reason', jsonb_build_object('reading', v_read), jsonb_build_object('paused', true));
        end if;
      else
        v_before := v_read->>'wa_golive';
        if v_ok then update public.app_secrets set value = case when d->>'to' = 'open' then 'true' else 'false' end where key = 'wa_supplier_invite_golive'; end if;
      end if;
    when 'directive' then
      -- REPEATS UNTIL CLOSED: an open directive is left to run; once it is closed unmet the next round goes out under a new ref.
      if v_ok and not exists (select 1 from public.ceo_directive c where c.source_kind = 'target_miss' and c.source_ref like 'supplier_growth:' || (d->>'subject') || ':%' and c.status = 'open') then
        select count(*) + 1 into v_round from public.ceo_directive c where c.source_kind = 'target_miss' and c.source_ref like 'supplier_growth:' || (d->>'subject') || ':%';
        v_dir := public.fn_ceo_directive_issue(d->>'seat', 'target_miss', 'supplier_growth:' || (d->>'subject') || ':' || v_round,
                   d->>'instruction', d->>'done_when', d->>'done_sql', p_at + make_interval(days => (d->>'days')::int), jsonb_build_object('reason', d->>'reason', 'round', v_round));
      end if;
      v_ok := v_dir is not null;
      v_after := coalesce(v_dir::text, 'no new round');
    end case;

    v_dedupe := (d->>'power') || ':' || (d->>'subject') || ':' || v_today;
    insert into public.ceo_growth_action (decided_on, power, subject, before_value, after_value, reason, applied, baseline, review_on, verdict, dedupe_key)
    values (v_today, d->>'power', d->>'subject', v_before, v_after, d->>'reason', v_ok, v_read - 'trade_candidates',
            case when v_ok and d ? 'review_days' then v_today + (d->>'review_days')::int end,
            case when d->>'power' = 'directive' and v_ok then 'recorded' when v_ok then 'pending' else 'not_applied' end, v_dedupe)
    on conflict (dedupe_key) do nothing;
    v_written := v_written + 1; v_applied := v_applied + v_ok::int; v_safe_n := v_safe_n + (v_ok and not v_apply)::int;
    perform public.fn_ceo_plan_log('supplier_growth', 'supplier_growth:' || v_dedupe,
      format('%s %s: %s -> %s. %s%s', d->>'power', d->>'subject', coalesce(v_before, '-'), v_after, d->>'reason', case when v_ok then '' else ' (not applied)' end),
      jsonb_build_object('action', d, 'applied', v_ok, 'reading', v_read - 'trade_candidates'));
  end loop;

  -- the run itself is a row, so a day with nothing to change still proves the CEO looked
  insert into public.ceo_growth_action (decided_on, power, subject, reason, applied, baseline, effect, verdict, dedupe_key)
  values (v_today, 'run', 'daily', format('%s decisions, %s applied (%s of them safety-side with the switch off), %s reviewed; switch %s', v_written, v_applied, v_safe_n, v_reviewed, case when v_apply then 'on' else 'off' end),
          v_apply, v_read - 'trade_candidates', jsonb_build_object('goal', v_goal, 'channels', v_channels), 'recorded', 'run:' || v_today);
  return jsonb_build_object('ok', true, 'ran', true, 'switch_on', v_apply, 'decisions', v_written, 'applied', v_applied, 'safety_side', v_safe_n, 'reviewed', v_reviewed,
                            'registered', v_goal->'registered', 'cap_the_target_needs_per_day', v_goal->'cap_the_target_needs_per_day');
end $fn$;
