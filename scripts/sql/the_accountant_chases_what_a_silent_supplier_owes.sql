-- THE ACCOUNTANT CHASES WHAT A SILENT SUPPLIER OWES, ON THE TIMELINE UAE LAW SETS, UNTIL IT IS PAID,
-- DISPUTED OR FILED.
--
-- Assigned: accountant (duty 2 of the eight, founder 14 Sep 2026: "yea add them all"). The supplier's
-- words are the sales_engineer's; customer_support sends them in the supplier's registered language.
--
-- The founder, 14 Sep 2026: "you need to check as per UAE law the deadline for that and accordingly set
-- it. once the deadline is over, the accountant need to issue a proper legal document that i can take to
-- dubai police or court and complain officially. all as per UAE law exactly, i am not gonna hire any
-- lawyer so make sure the form and the wordings is done correctly".
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * The charge itself is built: fn_accountant_raise_nonresponse_charge raises it once per refunded
--     reveal (the exact amount refunded, processing included, + AED 250 + 9% a year from the due date,
--     all from pricing_config and decision_policy), blocks matching, and the sales engineer tells the
--     supplier in English or Arabic. fn_supplier_dues_accrue_interest keeps the interest current.
--   * supplier_dues already carries reminders, last_reminder_at, legal_stage, legal_escalated_at,
--     demand_letter_path and case_file_path. NOTHING WRITES THEM: no reminder, no aging, no escalation,
--     no demand. After the first notice a charge was never mentioned again.
--
-- WHAT THIS BUILDS: the collection loop, every day and every date configuration:
--   reminders        at the days after the due date in supplier_charge_reminder_after_due_days, with
--                    the wording in supplier_charge_reminder_template (fn_sales_engineer_writes_money_notice)
--   final demand     at supplier_charge_final_demand_after_due_days, wording supplier_charge_final_demand_template
--   filing pack due  supplier_charge_final_demand_notice_days after the demand: a finding owned by the CEO,
--                    open until the founder's filing outcome is recorded (fn_accountant_record_filing_outcome)
--   escalation       past supplier_charge_escalate_ceo_after_due_days, a finding owned by the CEO
--   aging            fn_accountant_dues_aging, in the monthly close
-- A due the supplier disputed and the recomputation did not confirm (charge.dispute_answer with
-- figures_match false) is held from every notice and goes to the CEO instead. Payment (stripe_webhook
-- marks the due paid) or cancellation closes every finding on the next run.
--
-- WHAT THIS DOES NOT DO — AND WHY THE TIMELINE IS HELD TODAY. The dates and the wording of the demand come
-- from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md, which a separate build is writing from the law (the
-- payment-order route, the prior notice it requires, limitation, interest). Until decision_policy
-- supplier_charge_recovery_basis reads confirmed = true, with the document's articles cited, NO reminder
-- and NO demand is sent: a due that would need one is a finding for the CEO instead. The values below are
-- placeholders so the routine can be proved; they are not advice and are replaced from the document.
-- The filing pack itself (the documents for Dubai Courts or the police) is rendered by that build; this
-- file moves the due to 'filing_pack_due' and keeps it open.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_chases_what_a_silent_supplier_owes.sql --apply --ddl

-- ── 1. THE TIMELINE IS CONFIGURATION, AND IT IS NOT YET CONFIRMED ────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('supplier_charge_recovery_basis', '{"confirmed": false, "source": "docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md", "articles": []}'::jsonb,
   'Whether the supplier-charge recovery timeline and wording below are set from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md. While confirmed is false no reminder or demand is sent.'),
  ('supplier_charge_reminder_after_due_days', '[0, 7, 14]'::jsonb,
   'PLACEHOLDER until docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md sets it: days after the charge''s due date on which a reminder is sent.'),
  ('supplier_charge_final_demand_after_due_days', '30'::jsonb,
   'PLACEHOLDER until docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md sets it: days after the due date on which the formal final demand is sent.'),
  ('supplier_charge_final_demand_notice_days', '15'::jsonb,
   'PLACEHOLDER until docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md sets it: the notice period the final demand gives before the filing pack is due.'),
  ('supplier_charge_escalate_ceo_after_due_days', '30'::jsonb,
   'Days after the due date at which an unpaid supplier charge is a finding owned by the CEO.')
on conflict (key) do nothing;

-- ── 2. AGING ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_dues_aging(p_as_of date default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with d as (
    select coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date) - due_date days,
           coalesce(total_claim, amount_due + coalesce(admin_fee, 0) + coalesce(interest_amount, 0)) owed, legal_stage
      from public.supplier_dues
     where paid_at is null and coalesce(status, '') not in ('paid', 'settled', 'waived', 'cancelled'))
  select jsonb_build_object(
    'not_yet_due', jsonb_build_object('n', count(*) filter (where days < 0), 'aed', coalesce(sum(owed) filter (where days < 0), 0)),
    'd0_30',  jsonb_build_object('n', count(*) filter (where days between 0 and 30),  'aed', coalesce(sum(owed) filter (where days between 0 and 30), 0)),
    'd31_60', jsonb_build_object('n', count(*) filter (where days between 31 and 60), 'aed', coalesce(sum(owed) filter (where days between 31 and 60), 0)),
    'd61_90', jsonb_build_object('n', count(*) filter (where days between 61 and 90), 'aed', coalesce(sum(owed) filter (where days between 61 and 90), 0)),
    'over_90', jsonb_build_object('n', count(*) filter (where days > 90), 'aed', coalesce(sum(owed) filter (where days > 90), 0)),
    'in_legal_stage', count(*) filter (where legal_stage is not null),
    'total_aed', coalesce(sum(owed), 0))
  from d;
$fn$;
revoke execute on function public.fn_accountant_dues_aging(date) from public, anon, authenticated;

-- ── 3. THE FOUNDER RECORDS WHAT HAPPENED WITH THE FILING ─────────────────────────────────────────
create or replace function public.fn_accountant_record_filing_outcome(p_due_id bigint, p_outcome text, p_reference text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_outcome not in ('filed', 'paid_after_demand', 'settled', 'withdrawn', 'judgment') then
    raise exception 'a filing outcome is one of filed, paid_after_demand, settled, withdrawn, judgment (got %)', p_outcome;
  end if;
  update public.supplier_dues
     set legal_stage = 'outcome:' || p_outcome || coalesce(' ' || nullif(btrim(p_reference), ''), ''),
         status = case when p_outcome in ('paid_after_demand', 'settled') then 'settled'
                       when p_outcome = 'withdrawn' then 'waived' else status end
   where id = p_due_id and legal_stage in ('filing_pack_due', 'filing_pack_sent');
  if not found then return jsonb_build_object('ok', false, 'reason', 'due ' || p_due_id || ' is not waiting for a filing outcome'); end if;
  return jsonb_build_object('ok', true, 'due_id', p_due_id, 'outcome', p_outcome);
end $fn$;
revoke execute on function public.fn_accountant_record_filing_outcome(bigint, text, text) from public, anon, authenticated;

-- ── 4. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_collections_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_basis boolean := coalesce((select (value->>'confirmed')::boolean from public.decision_policy where key = 'supplier_charge_recovery_basis'), false);
  v_offs int[] := public.fn_policy_int_array('supplier_charge_reminder_after_due_days');
  v_fd int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_after_due_days');
  v_notice int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_notice_days');
  v_esc int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_escalate_ceo_after_due_days');
  d record; v jsonb; v_days int; v_i int; v_items jsonb := '[]'::jsonb; v_payload jsonb; v_disputed boolean;
  n_rem int := 0; n_fd int := 0; n_file int := 0; v_accrued int;
begin
  if array_length(v_offs, 1) is null or v_fd is null or v_notice is null or v_esc is null then
    raise exception 'fn_accountant_collections_tick: the supplier_charge_* timeline is missing from decision_policy';
  end if;
  v_accrued := public.fn_supplier_dues_accrue_interest(v_as_of);

  for d in select s.*, l.company_name, coalesce(l.is_demo, false) demo from public.supplier_dues s join public.leads l on l.id = s.supplier_id
            where s.paid_at is null and coalesce(s.status, '') not in ('paid', 'settled', 'waived', 'cancelled')
              and coalesce(s.legal_stage, '') not like 'outcome:%'
            order by s.id loop
    v_days := v_as_of - d.due_date;
    v := public.fn_accountant_nonresponse_charge(d.transaction_id, v_as_of);
    v_payload := coalesce(v, '{}'::jsonb) || jsonb_build_object('due_id', d.id, 'supplier_id', d.supplier_id,
      'transaction_id', d.transaction_id, 'quote_id', d.quote_id, 'days_overdue', greatest(v_days, 0),
      'interest_pct', round(coalesce((v->>'interest_apr')::numeric, 0) * 100, 2), 'due_date', d.due_date,
      'total_aed', coalesce(d.total_claim, d.amount_due));
    v_disputed := exists (select 1 from public.agent_actions a
                           where a.kind = 'handoff' and a.detail->>'type' = 'charge.dispute_answer'
                             and (a.detail->>'due_id')::bigint = d.id and (a.detail->>'figures_match')::boolean is false);

    if v_disputed then
      v_items := v_items || jsonb_build_object('item', 'disputed:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', coalesce(d.company_name, 'A supplier') || ' disputed charge #' || d.id || ' and the recomputation did not confirm it; notices are held until the CEO decides',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload);
    elsif not v_basis then
      if v_days >= v_offs[1] then
        v_items := v_items || jsonb_build_object('item', 'held_basis:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'Charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ', AED ' || coalesce(d.total_claim, d.amount_due)
                   || ') is ' || v_days || ' day(s) past due and no reminder can go: the UAE recovery timeline and wording are not yet configured',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('needs', 'decision_policy supplier_charge_recovery_basis confirmed = true, from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md'));
      end if;
    else
      -- The next reminder, once its day is reached.
      v_i := coalesce(d.reminders, 0) + 1;
      if v_i <= array_length(v_offs, 1) and v_days >= v_offs[v_i] and d.legal_stage is null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_reminder', 'supplier_dues',
          d.id || ':reminder:' || v_i, v_payload || jsonb_build_object('notice', 'charge_reminder', 'reminder_no', v_i));
        update public.supplier_dues set reminders = v_i, last_reminder_at = now() where id = d.id;
        n_rem := n_rem + 1;
      end if;
      -- The formal final demand.
      if v_days >= v_fd and d.legal_stage is null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.final_demand', 'supplier_dues',
          d.id || ':final_demand', v_payload || jsonb_build_object('notice', 'final_demand',
            'pay_by', (now() at time zone 'Asia/Dubai')::date + v_notice));
        update public.supplier_dues set legal_stage = 'final_demand_sent', legal_escalated_at = now() where id = d.id;
        n_fd := n_fd + 1;
      elsif d.legal_stage = 'final_demand_sent' and now() >= d.legal_escalated_at + make_interval(days => v_notice) then
        update public.supplier_dues set legal_stage = 'filing_pack_due' where id = d.id;
        d.legal_stage := 'filing_pack_due';
        n_file := n_file + 1;
      end if;
    end if;

    if d.legal_stage in ('filing_pack_due', 'filing_pack_sent') then
      v_items := v_items || jsonb_build_object('item', 'filing:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ', AED '
                 || coalesce(d.total_claim, d.amount_due) || ') has expired unpaid: the filing pack is '
                 || case d.legal_stage when 'filing_pack_due' then 'due to the founder' else 'with the founder' end
                 || ', and this stays open until he records the outcome',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
        'evidence', v_payload || jsonb_build_object('legal_stage', d.legal_stage, 'case_file_path', d.case_file_path,
                                                   'record_outcome', 'select public.fn_accountant_record_filing_outcome(' || d.id || ', ''filed'', ''<reference>'')'));
    end if;
    if v_days >= v_esc then
      v_items := v_items || jsonb_build_object('item', 'overdue:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', coalesce(d.company_name, 'A supplier') || ' owes AED ' || coalesce(d.total_claim, d.amount_due) || ' on charge #' || d.id
                 || ', ' || v_days || ' days past due, after ' || coalesce(d.reminders, 0) || ' reminder(s)',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload);
    end if;
  end loop;

  return jsonb_build_object('as_of', v_as_of, 'basis_confirmed', v_basis, 'interest_updated', v_accrued,
    'reminders', n_rem, 'final_demands', n_fd, 'filing_packs_due', n_file, 'aging', public.fn_accountant_dues_aging(v_as_of),
    'findings', public.fn_accountant_duty_settle('collections', v_items));
end $fn$;
revoke execute on function public.fn_accountant_collections_tick(date) from public, anon, authenticated;
