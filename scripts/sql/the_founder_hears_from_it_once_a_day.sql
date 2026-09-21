-- THE FOUNDER HEARS FROM IT ONCE A DAY, AND ONLY ABOUT WHAT NEEDS HIM.
--
-- Assigned: it_engineer (the policy, the register). The digest routine is customer_support's (it is the
-- only seat that sends). Founder instruction 642, 22 Sep 2026: tired of one to three IT emails a day.
-- Also records founder rule 641 (Meta and social wired to no agent until the marketing seat exists).
--
-- MEASURED BEFORE WRITING (22 Sep 2026, production):
--   * 14 days of public.notifications type founder_alert, status sent: it_new_bug 83 emails + 29 WhatsApp,
--     platform_down 4 + 4, backup_failed_after_retry 1 + 2. Every IT email he got that was not an outage
--     was kind it_new_bug, and every it_new_bug left through ONE routine,
--     fn_customer_support_sends_the_it_digest (the_founder_gets_one_it_digest_per_tick.sql), at most once
--     an hour, at level 'high', so each one also went to WhatsApp.
--   * What it carried, by the audit's reading of the 88 emails: ~55 alarms that fired while nothing was
--     wrong, ~25 real faults, ~6 decisions only he could make. Two writers feed it: fn_ceo_it_escalation_decide
--     ("new problem the IT engineer could not fix", sent the moment the CEO decided, however young the
--     fault) and fn_it_ceo_silence_watch ("the CEO has not answered an IT report" -- internal by nature).
--
-- WHAT THIS CHANGES
--   1. ONE DIGEST A DAY, at 19:00 Dubai. fn_customer_support_sends_the_it_digest(p_now) now runs its
--      decision once per Dubai day, on the first IT tick at or after 19:00, and the email carries ONLY:
--        (a) DECISIONS ONLY HE CAN MAKE: a finding whose issue_key matches public.it_founder_decision_class,
--            the register created here, derived against his answers (instructions >= 585): a refused
--            credential, an account owner nobody recognised. What he has answered or ruled not his
--            (caps and subscriptions 639, PITR and receipts 585, the campaign go 636) is registered
--            to_founder = false and never reaches him, not even as a day-old fault;
--        (b) FAULTS OPEN MORE THAN 24 HOURS THAT THE COMPANY COULD NOT FIX: held because the owning seat
--            and the CEO could not fix it, still open in it_engineer_finding, and started over 24 h ago.
--      Each is ONE plain sentence with what the company is doing about it. Everything else held is
--      completed and NOT sent: a fault that closed before the digest ("fixed before the digest"), and the
--      CEO-silence reports ("kept internal": the CEO keeps being asked every tick, as before). A fault
--      younger than 24 hours stays held and is judged again at tomorrow's digest. Nothing qualifying,
--      no email -- the day is marked checked so it is not re-judged every 15 minutes until midnight.
--      Level 'normal', so it is EMAIL ONLY: WhatsApp is kept for the emergency class.
--   2. THE EMERGENCY CLASS, NARROWLY, IN ONE PLACE: public.founder_mail_policy. Of the kinds the
--      it_engineer owns, exactly these may reach him immediately: platform_down and uptime_alert
--      (production down), backup_failed_after_retry (two days with no restorable backup: the data-loss
--      class), security_critical (a breach). Plus it_daily_digest itself. it_new_bug and
--      it_engineer_handover are set NOT allowed, so a per-issue IT send from anywhere -- a routine or a
--      direct insert -- is routed by fn_notify_founder / a10_notifications_founder_mail_policy instead of
--      reaching him. Checked by scripts/checks/the_founder_hears_from_it_once_a_day.test.mjs.
--   3. Rule 641 recorded once, in public.company_policy_decision 'meta_and_social_held_for_marketing'.
--
-- WHAT THIS DOES NOT CHANGE: the CEO still receives every IT report (support_ceo_report, the CEO's
-- deciders, fn_it_ceo_silence_watch asking every tick); the per-issue it.finding loop, re-verification
-- and closing; the IT daily line to the CEO at 19:00 (fn_it_daily_line); fn_notify_founder; the other
-- seats' founder kinds (money, reports, the brief -- PR #809 owns the brief). The Meta code changes are in
-- supabase/functions/_shared/it_duty_readings.ts and the_accountant_runs_its_duties_every_hour.sql.
-- CEILING: a decision class is recognised only by its issue_key; a duty that raises a new kind of
-- founder decision must add its pattern to it_founder_decision_class, or it arrives as a fault after 24 h.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_hears_from_it_once_a_day.sql --apply --ddl

-- ── 1. THE REGISTER: WHAT IS HIS TO DECIDE, AND WHAT HE HAS RULED IS NOT ─────────────────────────
-- to_founder true:  a decision only he can make -> a DECISION line in the digest.
-- to_founder false: he has answered it or ruled it is not his -> never sent, not even as a day-old
--                   fault; completed internal, citing his instruction. A declined decision is never re-asked.
create table if not exists public.it_founder_decision_class (
  issue_key_like text primary key,          -- a LIKE pattern over it_engineer_finding.issue_key
  to_founder     boolean not null,
  why            text not null,             -- to_founder: the sentence he reads; otherwise his ruling, cited
  recorded_at    timestamptz not null default now()
);
alter table public.it_founder_decision_class enable row level security;
drop policy if exists it_founder_decision_class_service_role_only on public.it_founder_decision_class;
create policy it_founder_decision_class_service_role_only on public.it_founder_decision_class
  as permissive for all to public using (false) with check (false);
revoke all on public.it_founder_decision_class from anon, authenticated;

-- Derived 22 Sep 2026 from what he was asked 14-21 Sep (it_engineer_finding) AGAINST his answers
-- (public.founder_instruction >= 585). Still his and undecided: a refused credential (only the account
-- holder re-issues it) and an account owner nobody recognises (he confirmed two on 15 Sep; a new one is a
-- security question only he can answer). Everything else he was asked is answered or ruled not his.
insert into public.it_founder_decision_class (issue_key_like, to_founder, why) values
  ('duty:credential:%',          true,  'a provider refused the company''s credential and only the account holder can issue a new one'),
  ('duty:access:%',              true,  'an account has an owner nobody recognises and only you can say whether it is yours'),
  -- 639: "Do not ask about Vercel caps or subscriptions; that is on him and he adds when reached.
  --       Twilio balance: only raise it if it is actually a blocker." A cap or floor nobody recorded is not
  --       a blocker; a balance that stops sends fails the sends, and that arrives as its own fault.
  ('duty:usage_%:cap_unknown:%', false, 'instruction 639: caps and subscriptions are his, added when reached; not asked'),
  ('duty:renewal:%',             false, 'instruction 639: subscriptions are his; the accountant tracks renewals, he is not asked'),
  -- 585: "no need for the point in time recovery ... receipts will be shared later ... ongoing routine".
  ('duty:db_backup:pitr',        false, 'instruction 585: point-in-time recovery declined'),
  ('acct:expenses:%',            false, 'instruction 585: receipts are an ongoing routine the accountant reads; not an alarm to him'),
  -- 636: "The campaign is not going now. He will say exactly when. Do not ask about it and do not remind him."
  ('%campaign%',                 false, 'instruction 636: the campaign go is his to give unasked; never asked or reminded'),
  ('%invitation%',               false, 'instruction 636: the invitation campaign go is his to give unasked; never asked or reminded')
on conflict (issue_key_like) do update set to_founder = excluded.to_founder, why = excluded.why;

-- ── 2. THE EMERGENCY CLASS AND THE DIGEST'S OWN KIND ─────────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at) values
  ('it_daily_digest', true, 'Founder instruction 642, 22 Sep 2026: ONE IT email a day at 19:00 Dubai, carrying only decisions only he can make and faults open more than 24 hours the company could not fix (the_founder_hears_from_it_once_a_day.sql). Email only.', 'it_engineer', now())
on conflict (kind) do update set allowed_to_email = true, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();

update public.founder_mail_policy
   set allowed_to_email = false, updated_at = now(),
       reason = 'Superseded by founder instruction 642 (22 Sep 2026): no per-issue IT email. A new bug nobody could fix reaches him in the daily IT digest (kind it_daily_digest) once it has been open 24 hours; until then it stays with the seats and the CEO.'
 where kind in ('it_new_bug', 'it_engineer_handover');

update public.founder_mail_policy
   set updated_at = now(),
       reason = 'EMERGENCY (instruction 642): sent at once, email and WhatsApp. ' ||
                case kind when 'platform_down' then 'The scheduler or the site is down: production down.'
                          when 'uptime_alert' then 'The site is down: production down.'
                          when 'backup_failed_after_retry' then 'Two days with no restorable backup: the data-loss class.'
                          when 'security_critical' then 'Customer data exposed or a secret leaked: a security breach.' end
 where kind in ('platform_down', 'uptime_alert', 'backup_failed_after_retry', 'security_critical')
   and reason not like 'EMERGENCY (instruction 642)%';

-- ── 3. RULE 641, RECORDED ONCE ───────────────────────────────────────────────────────────────────
insert into public.company_policy_decision (decision_key, decided_on, decided_by, decision_text, applies_to, never_ask_again)
values ('meta_and_social_held_for_marketing', date '2026-09-22', 'founder',
        'Founder rule 641: Meta, ads and social are wired to no agent until the marketing seat exists. HELD FOR MARKETING, stored and unreferenced: app_secrets meta_access_token, meta_ad_account_id, postiz_api_key, postiz_publish_key, postiz_integrations; routines fn_ads_manage and fn_accountant_ad_spend_tick. The IT expiry duty no longer sends the Meta token to Meta; the accountant''s hourly duties no longer run the ad-spend tick. Guarded by scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs.',
        array['it_engineer', 'accountant', 'ceo', 'customer_support', 'sales_engineer'], true)
on conflict (decision_key) do update set decision_text = excluded.decision_text, applies_to = excluded.applies_to;

-- ── 4. THE DIGEST ────────────────────────────────────────────────────────────────────────────────
-- The signature changes (interval floor -> the instant it judges), so the old one is dropped. CREATE grants
-- EXECUTE to PUBLIC; the revoke below closes it on the exact new signature.
drop function if exists public.fn_customer_support_sends_the_it_digest(interval);
create or replace function public.fn_customer_support_sends_the_it_digest(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
    -- His ruling that something is NOT his wins over any pattern that would ask him.
    select c.why, c.to_founder into v_why, v_his from public.it_founder_decision_class c where f.issue_key like c.issue_key_like
     order by c.to_founder, length(c.issue_key_like) desc limit 1;
    if found and not v_his then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', v_why, 'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; v_why := null; continue;
    end if;
    if not found then v_why := null; end if;
    if v_why is null and f.started_at > p_now - interval '24 hours' then
      n_wait := n_wait + 1; continue;                          -- still young: judged again tomorrow
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'decision', v_why is not null, 'key', f.issue_key,
      'family', case when regexp_replace(f.issue_key, ':[^:]*$', '') ~ ':' then regexp_replace(f.issue_key, ':[^:]*$', '') else f.issue_key end,
      'title', regexp_replace(left(f.title, 140), '[.\s]+$', ''), 'since', f.started_at,
      'owner', coalesce(f.evidence->>'owner_seat', 'it_engineer'), 'why', v_why);
    if v_why is not null then n_dec := n_dec + 1; else n_flt := n_flt + 1; end if;
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

  -- One sentence per decision; faults of one family raised together are one sentence with their count.
  select string_agg(line, E'\n' order by decision desc, first_id)
    into v_detail
    from (select bool_or((i->>'decision')::boolean) decision, min((i->>'id')::bigint) first_id,
                 case when bool_or((i->>'decision')::boolean) then
                   '- DECISION: ' || min(i->>'title') || '. Only you can decide this: ' || min(i->>'why')
                   || '. The CEO keeps it open until you answer (reference ' || min(i->>'key') || ').'
                 else
                   '- ' || case when count(*) > 1 then count(*) || ' problems of one kind, e.g. ' else '' end
                   || min(i->>'title') || ', open since '
                   || to_char(min((i->>'since')::timestamptz) at time zone 'Asia/Dubai', 'DD Mon') || '. Nothing inside the company fixed it; the '
                   || replace(min(i->>'owner'), '_', ' ') || ' has it, the engineers are making the code or configuration change, and the IT engineer re-checks it every 15 minutes and closes it when it is gone (reference '
                   || case when count(*) > 1 then min(i->>'family') || ':...' else min(i->>'key') end || ').'
                 end line
            from jsonb_array_elements(v_items) i
           group by case when (i->>'decision')::boolean then i->>'key' else i->>'family' end) g;
  v_event := 'IT today: ' || case when n_dec > 0 then n_dec || ' decision' || case when n_dec > 1 then 's' else '' end || ' for you' else '' end
             || case when n_dec > 0 and n_flt > 0 then ', ' else '' end
             || case when n_flt > 0 then n_flt || ' fault' || case when n_flt > 1 then 's' else '' end || ' open more than a day' else '' end;
  v_detail := 'The one IT message of the day. It carries only what needs you: decisions only you can make, and faults '
           || 'the company could not fix that have been open more than 24 hours. Everything else stays with the CEO and the seats.'
           || E'\n\n' || v_detail;

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
end $fn$;
revoke execute on function public.fn_customer_support_sends_the_it_digest(timestamptz) from public, anon, authenticated;

-- ── 5. VERDICT (read only). The behaviour -- held, too early, decision, old fault, young fault, fixed,
-- internal, nothing to the founder -- is rehearsed rolled back by
-- scripts/checks/the_founder_hears_from_it_once_a_day.test.mjs, which never commits a row.
with f as (
  select unnest(array[
    case when to_regprocedure('public.fn_customer_support_sends_the_it_digest(timestamptz)') is null then 'the daily digest routine is missing' end,
    case when to_regprocedure('public.fn_customer_support_sends_the_it_digest(interval)') is not null then 'the hourly digest overload still exists' end,
    case when has_function_privilege('anon', 'public.fn_customer_support_sends_the_it_digest(timestamptz)', 'execute')
           or has_function_privilege('authenticated', 'public.fn_customer_support_sends_the_it_digest(timestamptz)', 'execute')
         then 'the digest is callable by anon or authenticated' end,
    case when (select array_agg(kind order by kind) from public.founder_mail_policy where owner_role = 'it_engineer' and allowed_to_email)
              is distinct from array['backup_failed_after_retry', 'it_daily_digest', 'platform_down', 'security_critical', 'uptime_alert']
         then 'the it_engineer kinds allowed to reach the founder are not exactly the emergency class plus the digest' end,
    case when (select count(*) filter (where to_founder) from public.it_founder_decision_class) <> 2
              or (select count(*) filter (where not to_founder) from public.it_founder_decision_class) < 6
         then 'the founder decision register is not seeded as derived' end,
    case when exists (select 1 from public.it_founder_decision_class where to_founder
                       and issue_key_like ~* '(cap_unknown|pitr|campaign|invitation|subscription|renewal|expenses)')
         then 'the register would ask him something he has answered or ruled is not his' end,
    case when not exists (select 1 from public.company_policy_decision where decision_key = 'meta_and_social_held_for_marketing')
         then 'rule 641 is not recorded' end
  ]) why)
select case when count(why) = 0 then 'PROBE OK: one IT digest a day at 19:00 Dubai; emergency class = platform_down, uptime_alert, backup_failed_after_retry, security_critical'
            else 'PROBE FAILED: ' || string_agg(why, '; ') end as verdict
  from f;
