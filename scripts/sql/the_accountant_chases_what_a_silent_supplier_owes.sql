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
-- THE TIMELINE IS THE LAW'S, FROM docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md (merged in #643), every row
-- citing its source: reminders at due+4 and due+18; the formal demand at due+32 giving 7 days, never less
-- than the 5 CPL 42/2022 Art 144(1) requires (the routine refuses to run below it); limitation 5 years from
-- the due date (CTL Art 92), warned 180 days ahead; interest 9% simple from the due date, never
-- compounded (CTL Arts 73, 86, 88; clauses 31 and 33).
--
-- WHAT IS STILL HELD, AND WHY. supplier_charge_recovery_basis stays confirmed = false until Supplier
-- Agreement v11 (#649) is applied and merged: v11 makes WhatsApp and SMS formal notice (clause 21) and the
-- Arabic text governing (clause 22), and the demand cites those clauses. While it is false NO reminder and
-- NO demand is sent; a due that would need one is a finding for the CEO. After it is confirmed, a supplier
-- whose accepted_terms_version is older than v11 still gets no demand: it is held for the CEO until they
-- accept v11. This file does not suppress the WhatsApp copy trg_wa_fanout adds, so a demand is never
-- sent to a pre-v11 supplier "by email only"; it is held instead.
-- The filing pack itself (the documents for Dubai Courts or the police) is rendered by the legal build;
-- this file moves the due to 'filing_pack_due' and keeps it open until the founder records the outcome.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_chases_what_a_silent_supplier_owes.sql --apply --ddl

-- ── 1. THE TIMELINE IS CONFIGURATION, AND IT IS NOT YET CONFIRMED ────────────────────────────────
-- 14 SEP 2026: the timeline is docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §4 (merged in #643), each row
-- citing its source. supplier_charge_recovery_basis stays UNCONFIRMED until Supplier Agreement v11 (#649)
-- is applied and merged: v11 is what makes WhatsApp/SMS formal notice (clause 21) and the Arabic text
-- governing (clause 22), and the demand cites v11's clauses.
insert into public.decision_policy (key, value, description) values
  ('supplier_charge_recovery_basis',
   '{"confirmed": false, "source": "docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md", "articles": ["CPL 42/2022 Arts 143-148", "CPL Art 9", "CTL Arts 73, 81, 84, 86, 88, 92", "CTL 25/2025 Art 340(1)", "Supplier Agreement clauses 21, 22, 31, 33, 34"], "waits_for": "Supplier Agreement v11 (#649) applied and merged"}'::jsonb,
   'Whether the supplier-charge recovery timeline and wording are live. The timeline rows are set from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md; confirmed stays false until v11 (#649) is applied, because the demand cites v11''s notice and language clauses. While false, no reminder or demand is sent.'),
  ('supplier_charge_reminder_after_due_days', '[4, 18]'::jsonb,
   'Reminder 1 at due+4 and reminder 2 (asking for payment within 7 days) at due+18, each with a statement of account: docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §4. QuotesDone''s schedule; no statute sets reminder days.'),
  ('supplier_charge_final_demand_after_due_days', '32'::jsonb,
   'The formal demand (notice for payment) goes at due+32: docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §4, served by the clause 21 notice channels (CPL Art 9, CTL Art 81).'),
  ('supplier_charge_final_demand_notice_days', '7'::jsonb,
   'The demand gives 7 days to pay before a payment order is sought. CPL 42/2022 Art 144(1) requires at least 5 (supplier_charge_legal_minimum_notice_days); QuotesDone gives 7 (docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §1, §4).'),
  ('supplier_charge_legal_minimum_notice_days', '5'::jsonb,
   'CPL 42/2022 Art 144(1): the notice for payment must give "at least five [5] days". The collections routine refuses to run with a demand period below this.'),
  ('supplier_charge_limitation_years', '5'::jsonb,
   'CTL Art 92: the claim is time-barred 5 years from the clause 33 due date (docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §3(d)).'),
  ('supplier_charge_limitation_warn_days', '180'::jsonb,
   'An unfiled charge this many days before its CTL Art 92 limitation date is a finding owned by the CEO.'),
  ('supplier_charge_demand_min_agreement_version', '11'::jsonb,
   'The final demand cites Supplier Agreement v11 clauses 21 (WhatsApp and SMS as formal notice) and 22 (the Arabic text governs). A supplier whose accepted_terms_version is older is not sent the demand: it is held for the CEO until the supplier accepts v11 (the portal asks on the next sign-in).'),
  ('supplier_charge_escalate_ceo_after_due_days', '30'::jsonb,
   'Days after the due date at which an unpaid supplier charge is a finding owned by the CEO.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- The interest and due-date rows belong to payments_are_the_accountant_and_the_seats_close_every_refund_together.sql;
-- only their citations are completed here.
update public.decision_policy
   set description = 'The ceiling on the supplier charge''s interest: 9% a year, SIMPLE, on (a)+(b) only, from the due date until paid, never compounded (CTL Arts 73 and 86; Art 88 prohibits compound interest; clause 31 and 33). fn_accountant_nonresponse_charge applies min(pricing_config APR, this).'
 where key = 'supplier_charge_max_lawful_apr';
update public.decision_policy
   set description = 'Days after the clause 33 notice that the supplier''s non-response charge falls due: 7 (Supplier Agreement clause 33). Interest (CTL Art 86) and the CTL Art 92 limitation both run from this date.'
 where key = 'supplier_charge_due_days';

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
  v_min_notice int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_legal_minimum_notice_days');
  v_lim_years int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_years');
  v_lim_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_warn_days');
  v_min_ver int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_demand_min_agreement_version');
  v_ver int; v_limit_on date;
  d record; v jsonb; v_days int; v_i int; v_items jsonb := '[]'::jsonb; v_payload jsonb; v_disputed boolean;
  n_rem int := 0; n_fd int := 0; n_file int := 0; v_accrued int;
begin
  if array_length(v_offs, 1) is null or v_fd is null or v_notice is null or v_esc is null then
    raise exception 'fn_accountant_collections_tick: the supplier_charge_* timeline is missing from decision_policy';
  end if;
  if v_min_notice is null or v_lim_years is null or v_lim_warn is null or v_min_ver is null then
    raise exception 'fn_accountant_collections_tick: the legal minimum, limitation or agreement-version row is missing from decision_policy';
  end if;
  -- CPL 42/2022 Art 144(1): a demand giving fewer than five days is not a notice for payment.
  if v_notice < v_min_notice then
    raise exception 'supplier_charge_final_demand_notice_days is % but CPL Art 144(1) requires at least %; nothing is sent', v_notice, v_min_notice;
  end if;
  v_accrued := public.fn_supplier_dues_accrue_interest(v_as_of);

  for d in select s.*, l.company_name, coalesce(l.is_demo, false) demo, l.accepted_terms_version agreement_version
             from public.supplier_dues s join public.leads l on l.id = s.supplier_id
            where s.paid_at is null and coalesce(s.status, '') not in ('paid', 'settled', 'waived', 'cancelled')
              and coalesce(s.legal_stage, '') not like 'outcome:%'
            order by s.id loop
    v_days := v_as_of - d.due_date;
    v := public.fn_accountant_nonresponse_charge(d.transaction_id, v_as_of);
    v_payload := coalesce(v, '{}'::jsonb) || jsonb_build_object('agreement_version', coalesce(d.agreement_version, ''), 'due_id', d.id, 'supplier_id', d.supplier_id,
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
      -- THE DEMAND CITES v11 (clauses 21 and 22), so a supplier on an older accepted version is not sent it:
      -- the demand is held for the CEO until the supplier accepts v11. A version this cannot read is older.
      v_ver := nullif(regexp_replace(coalesce(d.agreement_version, ''), '[^0-9]', '', 'g'), '')::int;
      if v_days >= v_fd and d.legal_stage is null and coalesce(v_ver, 0) < v_min_ver then
        v_items := v_items || jsonb_build_object('item', 'demand_held_version:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is held: the supplier accepted '
                   || coalesce(d.agreement_version, 'no version') || ', and the demand cites Supplier Agreement v' || v_min_ver
                   || ' (WhatsApp/SMS notice, Arabic governing text)',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('accepted_version', d.agreement_version, 'required_version', 'v' || v_min_ver,
            'remedy', 'the supplier accepts v' || v_min_ver || ' on the next portal sign-in; the demand goes on the next run after that'));
      -- The formal final demand.
      elsif v_days >= v_fd and d.legal_stage is null then
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
    -- CTL Art 92: five years from the due date. An unfiled charge nearing that date is the CEO's.
    v_limit_on := (d.due_date + make_interval(years => v_lim_years))::date;
    if v_as_of >= v_limit_on - v_lim_warn and coalesce(d.legal_stage, '') not like 'outcome:filed%' then
      v_items := v_items || jsonb_build_object('item', 'limitation:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is time-barred on ' || v_limit_on
                 || ' (CTL Art 92, five years from the due date) and has not been filed',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload || jsonb_build_object('limitation_on', v_limit_on));
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
