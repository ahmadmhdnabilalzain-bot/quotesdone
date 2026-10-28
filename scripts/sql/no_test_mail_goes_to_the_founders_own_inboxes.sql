-- NO TEST MAIL GOES TO THE FOUNDER'S OWN INBOXES (it_engineer, 27 Oct 2026).
--
-- Assigned: it_engineer. The founder, 27 Oct 2026 ~22:50Z, verbatim: "stop doing tests on my email. thats extremely
-- useless". GlockApps decides deliverability now (ledger 1312: invitations resume only at >= 80% Outlook inbox in a
-- GlockApps test of supplier@; ledger 1344: the it_engineer runs those tests through the GlockApps API).
--
-- MEASURED, read-only, 27 Oct 2026 22:52Z (public.notifications, last 30 days, every row addressed to one of his
-- mailboxes, grouped by type and kind):
--   * THE MORNING SEED. fn_invite_placement_due queued, on every open sending day from 04:30 UTC, one
--     supplier_invite_seed to ahmadmhdnabilalzain@gmail.com and one to management@quotesdone.com (13 rows, the last
--     at 04:31Z on 27 Oct). Its caller is resilience_ping's itintegrations step (every 15 min) and the it_engineer
--     'inbox_placement' action, both through _shared/inbox_placement.ts placementTick. No pg_cron row: cron.job (71
--     jobs) has none for it. It is idle today only because invite_enabled is false (fn_invite_placement_day_closed);
--     resuming the invitations would have restarted it.
--   * THE WARM-UP / SEED SENDS. 6 rows of type supplier_invite_seed, kind invite_m365_seed, 27 Oct 15:07-16:12Z, to
--     ahmadmhdnabilalzain@gmail.com (2), management@doratajewelries.com, djzaino@outlook.com, bookings@djzaino.com
--     and fati.labib@icloud.com: day 0 of the compressed warm-up (docs/reports/QuotesDone Campaign/
--     SUPPLIER_WARMUP_PLAN_27_OCT.md). Written by a session, not by a schedule: no cron job, no seat_duty, no
--     resilience_step and no scheduled task sends warm-up mail (cron.job, seat_duty, resilience_step and the
--     account's scheduled tasks read on 27 Oct). The same rows on 18 Oct and 5 Oct went to the same mailboxes.
--   * scripts/invitation_inbox_check.mjs --send-seed allowed his three inboxes (FOUNDER_INBOXES); that list is
--     emptied of them in the same pull request.
--
-- WHAT THIS CHANGES
--   1. His words go into public.founder_instruction first, status 'standing'.
--   2. fn_invite_placement_due sends nothing, on any day, and says why. The reader (placementTick) gets 'idle'.
--   3. fn_invite_placement_gate stops waiting for a seed that will never come. Without this, the first open day after
--      a resume would answer 'fail:no_check' for ever and file a finding blaming the itintegrations step: a hidden
--      permanent block. It now answers 'fail:seed_retired' at once, and on an open day (invite_enabled and the go
--      both on) files ONE finding a day (deliverability:inbox_placement, verdict seed_retired) naming the remedy. It stays
--      FAIL-CLOSED on purpose: the gate that replaces it is the GlockApps verdict (#1649, deliverability_test), and
--      resuming the invitations must also replace this gate with that verdict. The resume steps in the warm-up plan
--      say so.
--   4. A trigger, a01_notifications_no_test_mail_to_the_founder, REFUSES (raises) any supplier_invite_seed row, or
--      any row of kind invite_m365_seed or supplier_invite_seed, addressed (to or cc) to one of his own inboxes, by
--      insert or by update. That is the warm-up path and any session's hand-written seed: a probe must be incapable
--      of reaching him, not careful. It fires before a10_notifications_founder_mail_policy (BEFORE triggers run in
--      name order), so the policy can never route or deliver one.
--   5. founder_mail_policy 'supplier_invite_seed' is no longer allowed to email him (its history trigger keeps the
--      old row).
--
-- WHAT IT DOES NOT CHANGE
--   * The GlockApps seeds queued tonight (notifications 114414-114525, kind invite_m365_seed, GlockApps addresses):
--     not his inboxes, untouched, and the trigger lets them through.
--   * Business mail to him: founder_brief, the daily supplier list, the accountant's reports, alerts. They are not
--     supplier_invite_seed rows and never reach this trigger's WHEN clause.
--   * invite_enabled, supplier_outreach_golive, wa_supplier_invite_golive: not read for writing, not written.
--   * invite_placement_check and its history (the 27 Oct row carries the GlockApps note): kept as a record.
--   * _shared/inbox_placement.ts keeps its read-only reader; with nothing queued it only ever sees 'idle'.
--
-- Prevented by: scripts/checks/no_test_mail_goes_to_the_founders_own_inboxes.test.mjs, which replays this file and
-- no_test_mail_goes_to_the_founders_own_inboxes_probe.sql in ONE aborted transaction.

-- ── 0. HIS WORDS FIRST ─────────────────────────────────────────────────────────────────────────────────────────────
insert into public.founder_instruction (said_at, instruction, subject, status, note)
select '2026-10-27 22:50+00', 'stop doing tests on my email. thats extremely useless',
       'no test email to the founder''s own inboxes', 'standing',
       'Standing rule. No test, seed, placement or warm-up mail to any of his own mailboxes '
       || '(management@quotesdone.com, ahmadmhdnabilalzain@gmail.com, management@doratajewelries.com, djzaino@outlook.com, '
       || 'bookings@djzaino.com, fati.labib@icloud.com). GlockApps seeds decide deliverability (ledger 1312, 1344). '
       || 'Business mail to him (founder_brief, daily lists, accountant reports, alerts) is not a test and is unaffected. '
       || 'Built by scripts/sql/no_test_mail_goes_to_the_founders_own_inboxes.sql.'
where not exists (select 1 from public.founder_instruction f
                   where f.instruction = 'stop doing tests on my email. thats extremely useless');

-- ── 1. WHO HE IS, AS AN ADDRESS ────────────────────────────────────────────────────────────────────────────────────
-- Exact mailboxes, never a domain: a colleague at quotesdone.com is a real person, not him. A +tag is the same
-- mailbox everywhere, and Gmail ignores dots in the local part, so both are folded before comparing. The founder_email
-- and admin_emails secrets are read too, so a mailbox he adds there is covered without a new file.
create or replace function public.fn_is_founder_own_inbox(p_addr text)
returns boolean language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_list text[]; v text;
begin
  if p_addr is null or btrim(p_addr) = '' then return false; end if;
  select array_agg(public.fn_mailbox_fold(a)) into v_list
    from (select unnest(array['management@quotesdone.com', 'ahmadmhdnabilalzain@gmail.com',
                              'management@doratajewelries.com', 'djzaino@outlook.com', 'bookings@djzaino.com',
                              'fati.labib@icloud.com']) a
          union all
          select btrim(x) from public.app_secrets s, regexp_split_to_table(coalesce(s.value, ''), ',') x
           where s.key in ('founder_email', 'admin_emails') and btrim(x) like '%@%') l;
  v := public.fn_mailbox_fold(p_addr);
  return v = any(v_list);
end $fn$;

create or replace function public.fn_mailbox_fold(p_addr text)
returns text language plpgsql immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare e text := lower(btrim(coalesce(p_addr, ''))); l text; d text;
begin
  -- "Name <a@b>" is reduced to the address inside the brackets.
  if e ~ '<[^<>]+>' then e := btrim(substring(e from '<([^<>]+)>')); end if;
  if position('@' in e) = 0 then return e; end if;
  l := split_part(e, '@', 1); d := split_part(e, '@', 2);
  l := regexp_replace(l, '\+.*$', '');
  if d in ('gmail.com', 'googlemail.com') then l := replace(l, '.', ''); d := 'gmail.com'; end if;
  return l || '@' || d;
end $fn$;

revoke execute on function public.fn_is_founder_own_inbox(text) from public, anon, authenticated;
revoke execute on function public.fn_mailbox_fold(text) from public, anon, authenticated;

-- ── 2. A SEED ADDRESSED TO HIM IS REFUSED ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_notifications_no_test_mail_to_the_founder()
returns trigger language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_hit text;
begin
  select a into v_hit
    from unnest(array[NEW.to_email] || coalesce(NEW.cc_emails, '{}'::text[])) a
   where public.fn_is_founder_own_inbox(a)
   limit 1;
  if v_hit is not null then
    raise exception 'no_test_mail_to_the_founder: a % (kind %) may not be addressed to the founder''s own inbox %; '
      'founder instruction of 27 Oct 2026, "stop doing tests on my email". GlockApps seeds decide deliverability '
      '(ledger 1312, 1344).', NEW.type, coalesce(NEW.kind, '-'), v_hit
      using errcode = 'check_violation';
  end if;
  return NEW;
end $fn$;

revoke execute on function public.fn_notifications_no_test_mail_to_the_founder() from public, anon, authenticated;

drop trigger if exists a01_notifications_no_test_mail_to_the_founder on public.notifications;
create trigger a01_notifications_no_test_mail_to_the_founder
  before insert or update of to_email, cc_emails, type, kind on public.notifications
  for each row
  when (new.type = 'supplier_invite_seed' or new.kind in ('invite_m365_seed', 'supplier_invite_seed'))
  execute function public.fn_notifications_no_test_mail_to_the_founder();

-- ── 3. THE MORNING SEED IS RETIRED ─────────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE keeps the existing ACL (revoked in the_invitation_batch_waits_for_the_mornings_seed_to_land_in_
-- both_inboxes.sql), so no grant is reopened here.
create or replace function public.fn_invite_placement_due(p_now timestamp with time zone default now())
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- Nothing is queued, read or settled: the seed went to his own inboxes (founder, 27 Oct 2026).
  return jsonb_build_object('action', 'idle', 'dubai_day', (p_now at time zone 'Asia/Dubai')::date,
    'reason', 'retired: no test mail to the founder''s own inboxes (27 Oct 2026); GlockApps decides');
end $fn$;

-- ── 4. THE GATE SAYS SO INSTEAD OF WAITING FOR EVER ────────────────────────────────────────────────────────────────
create or replace function public.fn_invite_placement_gate(p_day date default null::date, p_now timestamp with time zone default now())
returns text language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := coalesce(p_day, (p_now at time zone 'Asia/Dubai')::date);
begin
  -- FAIL CLOSED, BY NAME. The morning seed that used to open this gate is retired, so it can never pass. The gate
  -- that replaces it is the GlockApps verdict (ledger 1312: Outlook >= 80% inbox; #1649 files it). Resuming the
  -- invitations means replacing this routine with a reader of that verdict, in the same change that sets
  -- invite_enabled back to true. While the campaign is held (fn_invite_placement_day_closed answers) nothing is filed;
  -- on an open day the existing relay files ONE finding per day and verdict (deliverability:inbox_placement).
  if public.fn_invite_placement_day_closed(p_now) is null then
    perform public.fn_invite_placement_finding(v_day, 'seed_retired',
      'the placement gate still waits for the morning seed, retired on 27 Oct 2026 (no test mail to '
      || 'the founder''s own inboxes); replace fn_invite_placement_gate with a reader of the GlockApps verdict (ledger 1312, #1649)',
      jsonb_build_object('checked_at', p_now,
                         'remedy', 'replace fn_invite_placement_gate with a reader of the GlockApps verdict (ledger 1312, #1649)'));
  end if;
  return 'fail:seed_retired';
end $fn$;

-- ── 5. THE FOUNDER-MAIL POLICY STOPS ALLOWING THE SEED ─────────────────────────────────────────────────────────────
update public.founder_mail_policy
   set allowed_to_email = false,
       reason = 'Retired 27 Oct 2026: the founder, "stop doing tests on my email. thats extremely useless". '
                || 'A supplier_invite_seed to his own inboxes is refused by a01_notifications_no_test_mail_to_the_founder '
                || '(scripts/sql/no_test_mail_goes_to_the_founders_own_inboxes.sql); GlockApps decides deliverability.'
 where kind = 'supplier_invite_seed' and allowed_to_email;
