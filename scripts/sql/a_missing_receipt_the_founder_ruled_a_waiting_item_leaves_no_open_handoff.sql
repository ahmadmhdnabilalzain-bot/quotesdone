-- A MISSING RECEIPT THE FOUNDER RULED A WAITING ITEM LEAVES NO OPEN HANDOFF.
--
-- Assigned: accountant. 21 Sep 2026. Founder instruction 585 ("receipts will be shared later. its an
-- ongoing routine so at any time i can share it doesnt matter since the account reads the email").
--
-- ══ MEASURED, 21 Sep 2026 ~19:30 UTC, htdblwldjkcgjvmqkbeh (read-only) ══════════════════════════
-- #785 (the_founders_decisions_of_21_september_close_pitr_the_receipt_alarms_and_the_recorded_caps.sql)
-- is live: company_policy_decision expenses_receipts_are_an_ongoing_routine exists, the waiting gate
-- is in fn_accountant_duty_settle, and the three findings acct:expenses:{cadence_gaps,never_billed,
-- renewal_receipt} closed at 18:03:12Z. Their three it.finding handoffs to the accountant did NOT:
--   agent_actions 28945 (cadence_gaps), 28946 (never_billed), 39331 (renewal_receipt) — status
--   'pending', awaiting 'it_engineer re-verification', still counted as the accountant's open work.
-- WHY. fn_it_loop_reverify closes a cleared loop only when its it_incident carries cause, fix and
-- regression_check (the learning gate, trigger z62). All three had been escalated to the CEO as new
-- bugs, so each has an it_incident (132, 133, 227) with cause/fix/regression_check NULL; no it_playbook
-- class matches 'acct:expenses:' so fn_it_learning_from_playbook fills nothing; the loop parks them
-- as 'awaiting_learning' on every tick, for ever. A founder's ruling is not a bug to learn from, and
-- nothing wrote down that it was the reason the finding closed.
--
-- ══ WHAT THIS FILE CHANGES ═════════════════════════════════════════════════════════════════════
-- 1. fn_accountant_duty_settle: in the waiting branch (and only there — the gate from #785 is
--    unchanged), the accountant also writes the learning record of any incident on that key that is
--    still incomplete: cause = the founder's ruling, fix = the waiting gate, regression_check = this
--    file's probe, not_automatable_reason = the receipt arrives when he forwards it. Then the IT
--    engineer's own re-verify closes the handoff as originator, on its next tick — nobody else closes it.
-- 2. The same record is written once now for incidents 132, 133 and 227, so the three loops close on the
--    next fn_it_loop_tick without waiting for an accountant tick.
--
-- NOT CHANGED: fn_it_loop_reverify, the learning gate, the originator-closes rule, the expenses duty's
-- detection. If the founder's decision row is removed, the gate is off and a missing receipt is again
-- a finding whose incident needs a real learning record — this file writes none for it.
-- RECURRENCE: the probe answers PROBE FAILED if any it.finding handoff on a waiting receipt key is
-- still open behind an incomplete learning record while the decision stands, or the gate leaves the
-- live body.
--
--   node scripts/apply_sql.mjs scripts/sql/a_missing_receipt_the_founder_ruled_a_waiting_item_leaves_no_open_handoff.sql --apply --ddl

-- ── 1. the accountant's settle: the waiting branch also records why the loop may close ──
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
      -- 21 Sep 2026: a loop escalated before the ruling holds an incident with no learning record, and
      -- fn_it_loop_reverify parks it for ever. The ruling IS the record; the IT engineer still closes.
      perform public.fn_accountant_receipt_incident_learning(v_key);
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

-- ── 1b. the learning record the founder's ruling supplies ──
-- Only for the three waiting receipt keys, only while the decision row stands, only where the record
-- is incomplete; coalesce keeps anything a person already wrote. Returns the incidents it completed.
create or replace function public.fn_accountant_receipt_incident_learning(p_issue_key text)
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  if p_issue_key not in ('acct:expenses:cadence_gaps', 'acct:expenses:never_billed', 'acct:expenses:renewal_receipt')
     or not exists (select 1 from public.company_policy_decision where decision_key = 'expenses_receipts_are_an_ongoing_routine') then
    return 0;
  end if;
  update public.it_incident i
     set cause = coalesce(nullif(btrim(i.cause), ''),
           'Not a fault: a receipt the founder has not forwarded yet. Founder instruction 585 (21 Sep 2026) rules receipts '
           || 'an ongoing routine he forwards to the expenses mailbox whenever he chooses; the accountant reads the mailbox.'),
         fix = coalesce(nullif(btrim(i.fix), ''),
           'Recorded as company_policy_decision expenses_receipts_are_an_ongoing_routine; fn_accountant_duty_settle returns '
           || 'the item as `waiting` in the expenses duty result and raises no finding while that decision stands.'),
         regression_check = coalesce(nullif(btrim(i.regression_check), ''),
           'scripts/sql/a_missing_receipt_the_founder_ruled_a_waiting_item_leaves_no_open_handoff.sql (probe row)'),
         not_automatable_reason = coalesce(nullif(btrim(i.not_automatable_reason), ''),
           'Nothing to automate: the receipt exists only when the founder forwards it.'),
         recorded_by = coalesce(i.recorded_by, 'accountant (founder decision expenses_receipts_are_an_ongoing_routine)'),
         ended_at = coalesce(i.ended_at, now()),
         updated_at = now()
   where i.issue_key = p_issue_key
     and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = ''
          or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''));
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke execute on function public.fn_accountant_receipt_incident_learning(text) from public, anon, authenticated;

-- ── 2. once, now, for the three loops parked since 18:03Z ──
select public.fn_accountant_receipt_incident_learning(k)
  from unnest(array['acct:expenses:cadence_gaps', 'acct:expenses:never_billed', 'acct:expenses:renewal_receipt']) k;

-- ── PROBE ── a verdict ROW, never a raise.
with src as (select pg_get_functiondef('public.fn_accountant_duty_settle(text,jsonb)'::regprocedure) d),
parked as (
  select h.id from public.agent_actions h
    join public.it_incident i on i.handoff_id = h.id
   where h.kind = 'handoff' and h.detail->>'type' = 'it.finding' and h.status in ('pending', 'failed')
     and h.detail->>'issue_key' in ('acct:expenses:cadence_gaps', 'acct:expenses:never_billed', 'acct:expenses:renewal_receipt')
     and exists (select 1 from public.company_policy_decision where decision_key = 'expenses_receipts_are_an_ongoing_routine')
     and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = ''
          or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = '')))
select case when (select d like '%fn_accountant_receipt_incident_learning(v_key)%' from src)
             and (select count(*) from parked) = 0
            then 'PROBE OK: the waiting gate writes the learning record; no receipt loop is parked behind an incomplete incident'
            else 'PROBE FAILED: gate_live=' || coalesce((select (d like '%fn_accountant_receipt_incident_learning(v_key)%')::text from src), 'null')
                 || ' parked=' || coalesce((select string_agg(id::text, ',') from parked), 'none') end as verdict;
