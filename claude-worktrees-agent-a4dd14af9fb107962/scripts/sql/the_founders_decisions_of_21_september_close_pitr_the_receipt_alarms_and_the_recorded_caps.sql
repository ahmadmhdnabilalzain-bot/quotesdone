-- THE FOUNDER'S DECISIONS OF 21 SEPTEMBER CLOSE PITR, THE RECEIPT ALARMS AND THE RECORDED CAPS.
--
-- Assigned: it_engineer (with the accountant's settle routine). 21 Sep 2026. Founder instruction 585.
--
-- ══ MEASURED, 21 Sep 2026 ~17:45 UTC, htdblwldjkcgjvmqkbeh (read-only) ══════════════════════════
-- Founder instruction 585 (said 21 Sep): "no need for the point in time recovery. receipts will be
-- shared later. its an ongoing routine so at any time i can share it doesnt matter since the account
-- reads the email." Open it_engineer_finding rows this settles, by exact issue_key:
--   duty:db_backup:pitr                                  PITR off. #776's ingest holds it until
--        company_policy_decision carries supabase_pitr_addon:declined|approved — no row exists yet.
--   acct:expenses:cadence_gaps (seen 125), acct:expenses:never_billed (125),
--   acct:expenses:renewal_receipt (14)                  re-raised by fn_accountant_duty_settle every
--        accountant tick as founder-facing IT findings. The founder says a missing receipt is not an
--        alarm: he forwards receipts when he forwards them, and the accountant reads the mailbox.
--   duty:usage_resend:cap_unknown:resend_emails_month   #784 recorded cap_resend_emails_month = 50000
--   duty:usage_resend:cap_unknown:resend_emails_day     #784 removed the NULL daily row (Pro has none)
--   duty:renewal:domain:quotesdone.ae:date_unknown      #784 recorded it_expiry 2027-06-07 (Tasjeel)
--        The usage duty last ran 16:15Z, before #784 was applied, so these three are still open.
-- NOT closed: duty:usage_vercel:cap_unknown:vercel_charges_month, duty:usage_twilio:cap_unknown:
--   twilio_balance — the founder's budgets, set on his dashboard (NULL on purpose in #784).
--
-- ══ WHAT THIS FILE CHANGES ═════════════════════════════════════════════════════════════════════
-- 1. company_policy_decision: supabase_pitr_addon:declined and expenses_receipts_are_an_ongoing_routine,
--    both decided_by founder, in his words.
-- 2. fn_accountant_duty_settle: while expenses_receipts_are_an_ongoing_routine stands, the expenses
--    duty's missing-receipt items (cadence_gaps, never_billed, renewal_receipt) are NOT raised as
--    it_engineer_finding rows (which alert the founder). They are returned as `waiting` in the duty's
--    result — written to agent_runs every accountant tick — so the accountant still tracks each one;
--    any open finding for them is closed with the waiting note. Every other item, and every other
--    duty, is raised exactly as before. Removing the decision row restores the old behaviour.
-- 3. Closes the findings above by exact key, each guarded by the live fact that justifies it.
--
-- NOT CHANGED: the expenses duty's own detection, the accountant's mailbox reading, the alert tick.
-- RECURRENCE: the probe fails if the gate is missing from the live body or a waiting item can still
-- open a finding; fn_it_engineer_finding_upsert reopens any other key whose cause returns.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founders_decisions_of_21_september_close_pitr_the_receipt_alarms_and_the_recorded_caps.sql --apply --ddl

-- ── 1. the founder's decisions ──
insert into public.company_policy_decision (decision_key, decided_on, decided_by, decision_text, applies_to, never_ask_again)
values
  ('supabase_pitr_addon:declined', date '2026-09-21', 'founder',
   'Founder instruction 585, 21 Sep 2026: "no need for the point in time recovery." The paid PITR add-on is declined; daily backups and the Dropbox copies stand.',
   array['it_engineer'], true),
  ('expenses_receipts_are_an_ongoing_routine', date '2026-09-21', 'founder',
   'Founder instruction 585, 21 Sep 2026: "receipts will be shared later. its an ongoing routine so at any time i can share it doesnt matter since the account reads the email." A missing receipt is a waiting item the accountant tracks, never an alarm to the founder.',
   array['accountant', 'it_engineer'], true)
on conflict do nothing;

-- ── 2. the accountant's settle, with the waiting gate ──
create or replace function public.fn_accountant_duty_settle(p_duty text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text;
        v_waiting jsonb := '[]'::jsonb; v_receipts_wait boolean;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_accountant_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  -- Founder instruction 585 (21 Sep 2026): receipts arrive when he forwards them; a missing one is
  -- the accountant's waiting item, not a founder alarm. Read from the decision register, so the rule
  -- is a reviewable row and lifting it is deleting that row.
  v_receipts_wait := p_duty = 'expenses' and exists (select 1 from public.company_policy_decision d
                       where d.decision_key = 'expenses_receipts_are_an_ongoing_routine');
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_accountant_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    if coalesce(x->>'owner_seat', '') not in ('accountant', 'sales_engineer', 'customer_support', 'ceo') then
      raise exception 'fn_accountant_duty_settle: item % names owner seat %, which is not a seat the loop can hand to', x->>'item', x->>'owner_seat';
    end if;
    v_key := 'acct:' || p_duty || ':' || (x->>'item');
    if v_receipts_wait and (x->>'item') in ('cadence_gaps', 'never_billed', 'renewal_receipt') then
      v_waiting := v_waiting || jsonb_build_object('item', x->>'item', 'title', x->>'title', 'evidence', x->'evidence');
      if exists (select 1 from public.it_engineer_finding f where f.issue_key = v_key and f.closed_at is null) then
        perform public.fn_it_engineer_finding_close(v_key,
          'Waiting, not an alarm (founder instruction 585, 21 Sep 2026): receipts are an ongoing routine the '
          || 'founder forwards to the expenses mailbox; the accountant tracks this item in its duty result.');
      end if;
      continue;
    end if;
    v_keys := v_keys || v_key;
    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'Accountant duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', coalesce(x->>'subject', 'accountant'),
        'raised_by_seat', 'accountant', 'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'accountant.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'acct:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the accountant''s ' || p_duty || ' duty re-checked and no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0), 'closed', n_closed,
                            'waiting', v_waiting);
end $fn$;
revoke execute on function public.fn_accountant_duty_settle(text, jsonb) from public, anon, authenticated;

-- ── 3. close by exact key, each guarded by its live fact ──
select public.fn_it_engineer_finding_close('duty:db_backup:pitr',
  'Founder decision (instruction 585, 21 Sep 2026): point-in-time recovery declined; recorded as company_policy_decision supabase_pitr_addon:declined.')
 where exists (select 1 from public.company_policy_decision where decision_key = 'supabase_pitr_addon:declined')
   and exists (select 1 from public.it_engineer_finding where issue_key = 'duty:db_backup:pitr' and closed_at is null);

select public.fn_it_engineer_finding_close(k,
  'Waiting, not an alarm (founder instruction 585, 21 Sep 2026): receipts are an ongoing routine the founder forwards to the expenses mailbox; '
  || 'the accountant tracks this item in its expenses duty result (`waiting`), recorded as company_policy_decision expenses_receipts_are_an_ongoing_routine.')
  from unnest(array['acct:expenses:cadence_gaps', 'acct:expenses:never_billed', 'acct:expenses:renewal_receipt']) k
 where exists (select 1 from public.company_policy_decision where decision_key = 'expenses_receipts_are_an_ongoing_routine')
   and exists (select 1 from public.it_engineer_finding f where f.issue_key = k and f.closed_at is null);

select public.fn_it_engineer_finding_close('duty:usage_resend:cap_unknown:resend_emails_month',
  'Cap recorded by #784: cap_resend_emails_month = 50000 (Resend Pro, receipt #2771-8471); 138 used this month.')
 where (select value from public.it_threshold where key = 'cap_resend_emails_month') = 50000
   and exists (select 1 from public.it_engineer_finding where issue_key = 'duty:usage_resend:cap_unknown:resend_emails_month' and closed_at is null);

select public.fn_it_engineer_finding_close('duty:usage_resend:cap_unknown:resend_emails_day',
  'Resolved by #784: Resend Pro has no daily email limit, so the NULL cap_resend_emails_day row was removed.')
 where not exists (select 1 from public.it_threshold where key = 'cap_resend_emails_day')
   and exists (select 1 from public.it_engineer_finding where issue_key = 'duty:usage_resend:cap_unknown:resend_emails_day' and closed_at is null);

select public.fn_it_engineer_finding_close('duty:renewal:domain:quotesdone.ae:date_unknown',
  'Recorded by #784: domain:quotesdone.ae expires 2027-06-07 (Tasjeel invoice TJ420134); aeDA publishes no RDAP expiry.')
 where (select expires_on from public.it_expiry where item = 'domain:quotesdone.ae') = date '2027-06-07'
   and exists (select 1 from public.it_engineer_finding where issue_key = 'duty:renewal:domain:quotesdone.ae:date_unknown' and closed_at is null);

-- ── PROBE ── a verdict ROW, never a raise.
with src as (select pg_get_functiondef('public.fn_accountant_duty_settle(text,jsonb)'::regprocedure) d),
chk as (
  select
    (select count(*) from public.company_policy_decision
      where decision_key in ('supabase_pitr_addon:declined', 'expenses_receipts_are_an_ongoing_routine')) decisions,
    (select d like '%expenses_receipts_are_an_ongoing_routine%' and d like '%''waiting'', v_waiting%' from src) gate_live,
    (select count(*) from public.it_engineer_finding where closed_at is null and issue_key in (
       'duty:db_backup:pitr', 'acct:expenses:cadence_gaps', 'acct:expenses:never_billed', 'acct:expenses:renewal_receipt',
       'duty:usage_resend:cap_unknown:resend_emails_month', 'duty:usage_resend:cap_unknown:resend_emails_day',
       'duty:renewal:domain:quotesdone.ae:date_unknown')) still_open,
    (select count(*) from public.it_engineer_finding where closed_at is null and issue_key in (
       'duty:usage_vercel:cap_unknown:vercel_charges_month', 'duty:usage_twilio:cap_unknown:twilio_balance')) founder_budgets_open)
select case when decisions = 2 and gate_live and still_open = 0
            then 'PROBE OK: both founder decisions recorded; the expenses waiting gate is live; 7 findings closed by exact key; '
                 || founder_budgets_open || ' founder-budget findings (Vercel, Twilio) left open by design'
            else 'PROBE FAILED: decisions=' || decisions || ' gate_live=' || coalesce(gate_live::text, 'null')
                 || ' still_open=' || still_open end as verdict
  from chk;
