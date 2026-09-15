-- A REVERSED SUPPLIER CHARGE IS NEVER OWED (15 Sep 2026, agent: accountant).
--
-- THE DEFECT, read from production on 15 Sep 2026. supplier_dues.status has no CHECK constraint. The
-- values its writers use are 'pending' (the column default), 'due', 'legal' (fn_ban_overdue_dues),
-- 'paid', 'settled', 'waived', 'cancelled' and 'reversed' (test_money_never_reaches_the_books.sql set
-- #272 reversed as a fictitious charge on 14 Sep). Every routine that picked the OWED dues spelled its
-- own closed list, and not one of them listed 'reversed':
--
--   fn_accountant_collections_tick     reminders, the final demand, the filing pack, CEO "owes AED" items
--   fn_supplier_dues_accrue_interest   9% interest written onto the row
--   fn_ban_overdue_dues                bans the supplier, escalates to legal, pages the founder (crit)
--   fn_accountant_record_court_step    would record a court filing against a reversed charge
--   fn_accountant_dues_aging           receivable aging (the tick's own report)
--   fn_accountant_month_close_figures  open receivable in the month close the CEO signs
--   fn_accountant_recovery_position    open claims / open AED, via v_accountant_recovery_ledger.stage
--   fn_finance_forecast                ar_in           (closed list was only 'paid','waived')
--   fn_ws_finance                      overdue_commissions (only 'paid','settled'; a NULL status fell out)
--   fn_ws_supplier_360                 commission_owed     (only 'paid','settled'; a NULL status fell out)
--   fn_ops_dashboard                   pending_fees        (only <> 'paid')
--   view finance_kpis                  ar_outstanding, ar_overdue (only 'paid','waived')
--
-- Measured the same day: supplier_dues holds one row, #272, status 'reversed', paid_at null, and the
-- old collections predicate counts it as open (1 of 1). The tick skips it today only because its lead
-- no longer exists (inner join); aging, month close, accrual and the forecast do not join leads. The
-- duties never ran before PR #714 (resilience_ping's calls were refused with 401), so this became live
-- with that deploy.
--
-- THE FIX, at the root: ONE predicate, public.fn_supplier_due_is_owed(status, paid_at), and every
-- routine above asks it instead of spelling a list. 'void' is in it too: gl_journal uses 'void' for a
-- reversed entry, and a due marked the same way must not be chased either. legal_stage is NOT part of
-- the predicate: a due in court is still owed; the tick keeps its own "not an outcome yet" condition.
--
-- The routine bodies below are the LIVE definitions read back on 15 Sep 2026 (prosrc keeps the body
-- verbatim), each changed only at the selection named above. scripts/checks/a_reversed_supplier_charge_is_never_owed.test.mjs
-- fails if a dues routine stops asking the predicate. Probe: a_reversed_supplier_charge_is_never_owed_probe.sql.

-- ── 1. THE ONE DEFINITION OF "OWED" ───────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_due_is_owed(p_status text, p_paid_at timestamptz)
returns boolean language sql immutable parallel safe
set search_path to 'public', 'pg_temp'
as $fn$
  select p_paid_at is null
     and coalesce(p_status, '') not in ('paid', 'settled', 'waived', 'cancelled', 'reversed', 'void')
$fn$;
comment on function public.fn_supplier_due_is_owed(text, timestamptz) is
  'The one definition of an owed supplier charge: unpaid, and not paid, settled, waived, cancelled, reversed or void. Every routine that reminds, demands, accrues or counts a supplier due as receivable asks this.';
-- CREATE grants EXECUTE to PUBLIC. The readers are SECURITY DEFINER (they run as the owner) and the two
-- views are granted to service_role only, so service_role is the one grant needed.
revoke execute on function public.fn_supplier_due_is_owed(text, timestamptz) from public, anon, authenticated;
grant execute on function public.fn_supplier_due_is_owed(text, timestamptz) to service_role;

-- ── 2. THE RECOVERY LEDGER NAMES A CLOSED CHARGE BY ITS STATUS, AND SAYS WHETHER IT IS OWED ──────
-- Was: when status in ('settled','waived','cancelled') then status, so a reversed charge fell through
-- to 'notice_sent' and fn_accountant_recovery_position counted it as an open claim. `owed` is appended
-- as the last column (CREATE OR REPLACE VIEW may only add columns at the end).
create or replace view public.v_accountant_recovery_ledger with (security_invoker = true) as
  with p as (
    select (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_notice_days') notice_days,
           (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_legal_minimum_notice_days') min_notice_days,
           (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_payment_order_serve_months') serve_months,
           (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_grievance_days') grievance_days,
           (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_years') limitation_years)
  select d.id as due_id, d.supplier_id, l.company_name as supplier, coalesce(l.is_demo, false) as demo, d.transaction_id,
         d.amount_due as refund_aed, d.admin_fee as admin_fee_aed, d.interest_amount as interest_aed,
         coalesce(d.total_claim, d.amount_due + coalesce(d.admin_fee, 0) + coalesce(d.interest_amount, 0)) as claim_aed,
         d.due_date,
         case when d.paid_at is not null or coalesce(d.status, '') = 'paid' then 'paid'
              when not public.fn_supplier_due_is_owed(d.status, d.paid_at) then d.status
              when d.grievance_filed_on is not null then 'grievance_filed'
              when d.payment_order_served_on is not null then 'order_served'
              when d.payment_order_issued_on is not null then 'order_issued'
              when d.payment_order_filed_on is not null or coalesce(d.legal_stage, '') like 'outcome:filed%' then 'filed'
              when d.legal_stage is not null then d.legal_stage
              when coalesce(d.reminders, 0) > 0 then 'reminded'
              else 'notice_sent' end as stage,
         d.reminders, d.last_reminder_at,
         case when d.legal_stage is not null then d.legal_escalated_at end as demand_sent_at,
         -- The demand gives notice_days to pay; CPL Art 144(1) requires at least min_notice_days. The order
         -- is sought only after the period the demand itself promised.
         case when d.legal_stage is not null
              then (d.legal_escalated_at at time zone 'Asia/Dubai')::date + greatest(p.notice_days, p.min_notice_days) end as payment_order_earliest_on,
         d.payment_order_filed_on, d.payment_order_issued_on,
         (d.payment_order_issued_on + make_interval(months => p.serve_months))::date as serve_order_by,
         d.payment_order_served_on,
         d.payment_order_served_on + p.grievance_days as grievance_until,
         d.grievance_filed_on,
         (d.due_date + make_interval(years => p.limitation_years))::date as limitation_on,
         d.court_reference, d.demand_letter_path, d.case_file_path, d.paid_at,
         'docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md; the documents are rendered by supabase/functions/_shared/supplier_charge_documents.ts'::text as legal_pack,
         '9% a year simple interest on the refund plus the AED 250 fee, from the due date, never compounded (CTL Arts 73, 86, 88; Supplier Agreement clauses 31 and 33)'::text as interest_rule,
         public.fn_supplier_due_is_owed(d.status, d.paid_at) as owed
    from public.supplier_dues d
    left join public.leads l on l.id = d.supplier_id
    cross join p;
comment on view public.v_accountant_recovery_ledger is
  'Every supplier-charge claim from notice to payment or court: the amounts (refund, AED 250, 9% simple interest), the stage, and every UAE deadline worked out from decision_policy (CPL 42/2022 Arts 144, 146, 147; CTL Art 92). owed is public.fn_supplier_due_is_owed. The legal pack is docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md.';
revoke all on public.v_accountant_recovery_ledger from anon, authenticated;

-- ── 3. EVERY READER ASKS THE PREDICATE (live bodies; one selection changed in each) ──────────────
-- fn_accountant_collections_tick(date)
CREATE OR REPLACE FUNCTION public.fn_accountant_collections_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_ver int; v_limit_on date; v_route jsonb;
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
            where public.fn_supplier_due_is_owed(s.status, s.paid_at)
              and coalesce(s.legal_stage, '') not like 'outcome:%'
            order by s.id loop
    v_days := v_as_of - d.due_date;
    v := public.fn_accountant_nonresponse_charge(d.transaction_id, v_as_of);
    v_payload := coalesce(v, '{}'::jsonb) || jsonb_build_object('agreement_version', coalesce(d.agreement_version, ''), 'due_id', d.id, 'supplier_id', d.supplier_id,
      'transaction_id', d.transaction_id, 'quote_id', d.quote_id, 'days_overdue', greatest(v_days, 0),
      'interest_pct', round(coalesce((v->>'interest_apr')::numeric, 0) * 100, 2), 'due_date', d.due_date,
      'total_aed', coalesce(d.total_claim, d.amount_due));
    -- 14 SEP 2026 (Supplier Agreement v12): every notice carries the clause 21 wording and the WhatsApp basis of
    -- the version THIS supplier accepted, for the templates ({{notice_clause_en}}, {{notice_clause_ar}},
    -- {{whatsapp_basis}}). The number itself is chosen at the outbox by a06 (fn_supplier_notice_route), never here.
    v_route := public.fn_supplier_notice_route(d.supplier_id, null);
    v_payload := v_payload || jsonb_build_object('notice_clause_en', coalesce(v_route->>'clause_en', ''),
      'notice_clause_ar', coalesce(v_route->>'clause_ar', ''), 'whatsapp_basis', coalesce(v_route->'whatsapp'->>'basis', ''));
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
      -- THE DEMAND NEEDS v11 OR LATER (clause 21 makes WhatsApp and SMS notice, clause 22 makes Arabic govern).
      -- A v11 supplier is not held for v12: v11 covers the notice, which goes to the registered mobile. A
      -- supplier below v11 is held for the CEO until it accepts the current version. Unreadable is older.
      v_ver := (v_route->>'version_no')::int;
      if v_days >= v_fd and d.legal_stage is null and coalesce(v_ver, 0) < v_min_ver then
        v_items := v_items || jsonb_build_object('item', 'demand_held_version:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is held: the supplier accepted '
                   || coalesce(d.agreement_version, 'no version') || ' (' || coalesce(v_route->>'clause_en', 'no clause 21 on record')
                   || '), and a demand needs Supplier Agreement v' || v_min_ver || ' or later (WhatsApp/SMS notice, Arabic governing text)',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('accepted_version', d.agreement_version, 'required_version', 'v' || v_min_ver,
            'remedy', 'the supplier accepts the current version on the next portal sign-in; the demand goes on the next run after that'));
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
end $function$;

-- fn_supplier_dues_accrue_interest(date)
CREATE OR REPLACE FUNCTION public.fn_supplier_dues_accrue_interest(p_as_of date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; v jsonb; n int := 0;
begin
  for x in select id, transaction_id from public.supplier_dues
            where public.fn_supplier_due_is_owed(status, paid_at) and transaction_id is not null loop
    v := public.fn_accountant_nonresponse_charge(x.transaction_id, p_as_of);
    continue when not coalesce((v->>'ok')::boolean, false);
    update public.supplier_dues
       set interest_amount = (v->>'interest_aed')::numeric, total_claim = amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric
     where id = x.id
       and (interest_amount is distinct from (v->>'interest_aed')::numeric
            or total_claim is distinct from amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric);
    if found then n := n + 1; end if;
  end loop;
  return n;
end $function$;

-- fn_accountant_dues_aging(date)
CREATE OR REPLACE FUNCTION public.fn_accountant_dues_aging(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (
    select coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date) - due_date days,
           coalesce(total_claim, amount_due + coalesce(admin_fee, 0) + coalesce(interest_amount, 0)) owed, legal_stage
      from public.supplier_dues
     where public.fn_supplier_due_is_owed(status, paid_at))
  select jsonb_build_object(
    'not_yet_due', jsonb_build_object('n', count(*) filter (where days < 0), 'aed', coalesce(sum(owed) filter (where days < 0), 0)),
    'd0_30',  jsonb_build_object('n', count(*) filter (where days between 0 and 30),  'aed', coalesce(sum(owed) filter (where days between 0 and 30), 0)),
    'd31_60', jsonb_build_object('n', count(*) filter (where days between 31 and 60), 'aed', coalesce(sum(owed) filter (where days between 31 and 60), 0)),
    'd61_90', jsonb_build_object('n', count(*) filter (where days between 61 and 90), 'aed', coalesce(sum(owed) filter (where days between 61 and 90), 0)),
    'over_90', jsonb_build_object('n', count(*) filter (where days > 90), 'aed', coalesce(sum(owed) filter (where days > 90), 0)),
    'in_legal_stage', count(*) filter (where legal_stage is not null),
    'total_aed', coalesce(sum(owed), 0))
  from d;
$function$;

-- fn_accountant_month_close_figures(date)
CREATE OR REPLACE FUNCTION public.fn_accountant_month_close_figures(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_fx numeric;
  v_from timestamptz; v_to timestamptz; v_pnl jsonb; v_rev numeric; v_exp numeric; v_aging jsonb; v_out jsonb;
begin
  v_e := (v_m + interval '1 month' - interval '1 day')::date;
  v_from := v_m::timestamp at time zone 'Asia/Dubai'; v_to := (v_e + 1)::timestamp at time zone 'Asia/Dubai';
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);

  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'amount_aed', amt) order by code), '[]'::jsonb),
         coalesce(sum(amt) filter (where type = 'revenue'), 0), coalesce(sum(amt) filter (where type = 'expense'), 0)
    into v_pnl, v_rev, v_exp
    from (select a.code, a.name, a.type,
                 round(sum(case when a.type = 'revenue' then l.credit - l.debit else l.debit - l.credit end), 2) amt
            from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id join public.gl_accounts a on a.code = l.account_code
           where j.status = 'posted' and j.entry_date between v_m and v_e and a.type in ('revenue', 'expense')
           group by a.code, a.name, a.type) z;

  select jsonb_build_object(
      'current', count(*) filter (where d <= 0), 'd1_30', count(*) filter (where d between 1 and 30),
      'd31_60', count(*) filter (where d between 31 and 60), 'd61_90', count(*) filter (where d between 61 and 90),
      'over_90', count(*) filter (where d > 90), 'open_aed', coalesce(sum(owed), 0))
    into v_aging
    from (select v_e - due_date d, coalesce(total_claim, amount_due + coalesce(admin_fee, 0) + coalesce(interest_amount, 0)) owed
            from public.supplier_dues
           where public.fn_supplier_due_is_owed(status, paid_at)) z;

  v_out := jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_e, 'timezone', 'Asia/Dubai',
    'profit_and_loss', jsonb_build_object('accounts', v_pnl, 'revenue_aed', v_rev, 'expenses_aed', v_exp,
                                          'net_result_aed', v_rev - v_exp,
                                          'basis', 'Posted journals dated in the month, revenue and expense accounts. Drafts are not in it.'),
    'cash_in', jsonb_build_object(
      'reveals_aed', (select coalesce(sum(coalesce(total_charged, reveal_fee)), 0) from public.transactions t
                       left join public.customers c on c.id = t.customer_id
                      where t.fee_status = 'paid' and t.revealed_at >= v_from and t.revealed_at < v_to and not coalesce(c.is_demo, false)),
      'supplier_charges_aed', (select coalesce(sum(coalesce(total_claim, amount_due)), 0) from public.supplier_dues
                                where paid_at >= v_from and paid_at < v_to),
      'subscriptions_paid', (select count(*) from public.leads where registration_paid_at >= v_from and registration_paid_at < v_to
                               and not coalesce(is_demo, false))),
    'cash_out', jsonb_build_object(
      'refunds_aed', (select coalesce(sum(amount_fils), 0) / 100.0 from public.refunds where status = 'succeeded'
                       and settled_at >= v_from and settled_at < v_to),
      'expenses_aed', (select coalesce(round(sum(amount * case upper(currency) when 'USD' then v_fx else 1 end)
                                             filter (where upper(currency) in ('AED', 'USD')), 2), 0)
                         from public.expense_entries where charged_on between v_m and v_e),
      'expenses_unconverted', (select count(*) from public.expense_entries where charged_on between v_m and v_e
                                 and upper(currency) not in ('AED', 'USD'))),
    'held_for_possible_refunds', public.fn_accountant_refund_reserve(),
    'bank_reconciliation', jsonb_build_object(
      'payouts', (select count(*) from public.stripe_payout where livemode and arrival_date between v_m and v_e),
      'payouts_aed', (select coalesce(sum(amount_fils), 0) / 100.0 from public.stripe_payout where livemode and arrival_date between v_m and v_e),
      'matched', (select count(*) from public.stripe_payout where livemode and arrival_date between v_m and v_e and bank_line_id is not null),
      'unmatched', (select count(*) from public.stripe_payout where livemode and status = 'paid' and arrival_date between v_m and v_e and bank_line_id is null),
      'statement_lines', (select count(*) from public.bank_statement_line where account <> 'zz_demo' and value_date between v_m and v_e),
      'open_findings', (select count(*) from public.it_engineer_finding where issue_key like 'acct:bank:%' and closed_at is null)),
    'bank_drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'disputes', jsonb_build_object('open', (select count(*) from public.stripe_dispute where livemode and closed_at is null),
                                   'closed_in_month', (select coalesce(jsonb_object_agg(outcome, n), '{}'::jsonb) from (
                                      select outcome, count(*) n from public.stripe_dispute where livemode and closed_at >= v_from and closed_at < v_to
                                       group by outcome) z)),
    'collections_aging', v_aging,
    'charge_audit_open_differences', (select count(*) from public.charge_audit where livemode and abs(diff_aed) >= 0.01 and resolved_at is null),
    'subscriptions', public.fn_accountant_subscription_position(),
    'vat', public.fn_accountant_vat_threshold_check(false),
    'weekly_figures_over_the_month', public.fn_accountant_weekly_report_figures(v_m, v_e),
    'measured_at', now());
  -- 14 Sep 2026, the five further duties ("add all for accountant and IT"): the CEO's monthly report of cash,
  -- runway, ad spend, recovery and renewals rides on the close rather than being a second report.
  return v_out || jsonb_build_object(
    'cash_position', public.fn_accountant_cash_position(v_m, (v_out#>>'{cash_out,expenses_aed}')::numeric),
    'ad_spend', public.fn_accountant_ad_spend_figures(v_m),
    'supplier_charge_recovery', public.fn_accountant_recovery_position(),
    'renewals', public.fn_accountant_renewal_position());
end $function$;

-- fn_ban_overdue_dues()
CREATE OR REPLACE FUNCTION public.fn_ban_overdue_dues()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_days int; v_n int := 0; v_admin text;
begin
  v_days  := coalesce((select num_value from public.gl_settings where key='clawback_ban_days'), 90)::int;
  v_admin := coalesce((select split_part(value,',',1) from public.app_secrets where key='admin_emails'),'management@quotesdone.com');

  for r in
    select d.id, d.supplier_id, d.amount_due, d.admin_fee, d.interest_amount, d.due_date,
           l.company_name, coalesce(l.claimed_by,l.email) as email,
           l.accepted_terms_at, l.accepted_terms_version, l.signed_terms_path, l.banned
    from public.supplier_dues d
    join public.leads l on l.id = d.supplier_id
    where public.fn_supplier_due_is_owed(d.status, d.paid_at)
      and coalesce(d.amount_due,0) > 0
      and d.due_date is not null
      and current_date >= (d.due_date::date + v_days)
      and d.legal_escalated_at is null
  loop
    update public.supplier_dues
       set status = 'legal', legal_stage = 'pending_case', legal_escalated_at = now()
     where id = r.id;

    update public.leads
       set banned = true,
           banned_reason = 'Unpaid refund clawback of AED ' ||
                           round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
                           ' more than ' || v_days || ' days past due (due ' || r.due_date::date || ').',
           matching_blocked = true,
           matching_block_reason = 'Banned: unpaid refund clawback escalated to legal'
     where id = r.supplier_id;

    insert into public.founder_alerts(level, event, detail, channel)
    values ('crit', 'supplier_banned_legal',
      coalesce(r.company_name,'Supplier #'||r.supplier_id) || ' has been banned and due #' || r.id ||
      ' escalated to legal: AED ' || round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
      ' unpaid for over ' || v_days || ' days. ' ||
      case when r.accepted_terms_at is null
           then '*** NO SIGNED TERMS ON RECORD - the supplier agreement cannot be produced as evidence, so a filing may not be supportable. Verify before instructing the legal agent. ***'
           else 'Terms accepted ' || r.accepted_terms_at::date || ' (version ' || coalesce(r.accepted_terms_version,'?') || ') - available as supporting evidence.'
      end, 'system');

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$function$;

-- fn_accountant_record_court_step(bigint,text,date,text)
CREATE OR REPLACE FUNCTION public.fn_accountant_record_court_step(p_due_id bigint, p_step text, p_on date, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.supplier_dues; r record; v_today date := (now() at time zone 'Asia/Dubai')::date; v_warn text[] := '{}';
begin
  if p_step not in ('filed', 'order_issued', 'order_served', 'grievance_filed', 'recovered', 'withdrawn') then
    raise exception 'a court step is one of filed, order_issued, order_served, grievance_filed, recovered, withdrawn (got %)', p_step;
  end if;
  if p_on is null or p_on > v_today then raise exception 'a court step is recorded on the day it happened, not before it (got %)', p_on; end if;
  select * into d from public.supplier_dues where id = p_due_id for update;
  if not found then raise exception 'no supplier due %', p_due_id; end if;
  if not public.fn_supplier_due_is_owed(d.status, d.paid_at) then
    raise exception 'due % is closed (%); nothing more is recorded against it', p_due_id, coalesce(d.status, 'paid');
  end if;
  select * into r from public.v_accountant_recovery_ledger where due_id = p_due_id;

  if p_step = 'filed' then
    if d.legal_escalated_at is null then
      raise exception 'due % has had no formal demand: CPL 42/2022 Art 144(1) requires the notice for payment before a payment order', p_due_id;
    end if;
    if p_on < r.payment_order_earliest_on then
      v_warn := v_warn || ('filed on ' || p_on || ', before ' || r.payment_order_earliest_on || ' when the demand''s period ran out');
    end if;
    if d.legal_stage in ('filing_pack_due', 'filing_pack_sent') then
      perform public.fn_accountant_record_filing_outcome(p_due_id, 'filed', p_reference);
    end if;
    update public.supplier_dues set payment_order_filed_on = p_on,
           court_reference = coalesce(nullif(btrim(p_reference), ''), court_reference) where id = p_due_id;
  elsif p_step = 'order_issued' then
    if d.payment_order_filed_on is null or p_on < d.payment_order_filed_on then
      raise exception 'due %: record the filing first, on or before the day the order was issued', p_due_id;
    end if;
    update public.supplier_dues set payment_order_issued_on = p_on,
           court_reference = coalesce(nullif(btrim(p_reference), ''), court_reference) where id = p_due_id;
  elsif p_step = 'order_served' then
    if d.payment_order_issued_on is null or p_on < d.payment_order_issued_on then
      raise exception 'due %: record the issued order first, on or before the day it was served', p_due_id;
    end if;
    if p_on > r.serve_order_by then
      v_warn := v_warn || ('served on ' || p_on || ', after ' || r.serve_order_by || ': under CPL Art 146(2) the order is void');
    end if;
    update public.supplier_dues set payment_order_served_on = p_on where id = p_due_id;
  elsif p_step = 'grievance_filed' then
    if d.payment_order_served_on is null or p_on < d.payment_order_served_on then
      raise exception 'due %: record the service first; a grievance runs from service (CPL Art 147(1))', p_due_id;
    end if;
    if p_on > r.grievance_until then
      v_warn := v_warn || ('grievance filed on ' || p_on || ', after the 15 days that ended ' || r.grievance_until);
    end if;
    update public.supplier_dues set grievance_filed_on = p_on where id = p_due_id;
  elsif p_step = 'recovered' then
    update public.supplier_dues set status = 'settled', paid_at = p_on::timestamp at time zone 'Asia/Dubai',
           payment_ref = coalesce(nullif(btrim(p_reference), ''), payment_ref) where id = p_due_id;
  else
    update public.supplier_dues set status = 'waived' where id = p_due_id;
  end if;
  return jsonb_build_object('ok', true, 'due_id', p_due_id, 'step', p_step, 'on', p_on, 'warnings', to_jsonb(v_warn));
end $function$;

-- fn_accountant_recovery_position()
CREATE OR REPLACE FUNCTION public.fn_accountant_recovery_position()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'open_claims', count(*) filter (where owed),
    'open_aed', coalesce(sum(claim_aed) filter (where owed), 0),
    'in_court', count(*) filter (where stage in ('filed', 'order_issued', 'order_served', 'grievance_filed')),
    'by_stage', coalesce((select jsonb_object_agg(stage, n) from (select stage, count(*) n from public.v_accountant_recovery_ledger
                                                                   where not demo group by stage) s), '{}'::jsonb),
    'recovered_aed', coalesce(sum(claim_aed) filter (where stage in ('paid', 'settled')), 0),
    'basis', 'public.v_accountant_recovery_ledger, ZZ DEMO suppliers excluded. claim_aed is the refund, the AED 250 fee and the 9% simple interest accrued by fn_supplier_dues_accrue_interest.')
  from public.v_accountant_recovery_ledger where not demo;
$function$;

-- fn_finance_forecast()
CREATE OR REPLACE FUNCTION public.fn_finance_forecast()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select (select coalesce(sum(balance),0) from gl_account_balances where code in ('1000','1050')) as cash,
           (select coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0)
              from gl_journal_lines l join gl_journal j on j.id=l.journal_id and j.status='posted'
              join gl_accounts ga on ga.code=l.account_code where j.entry_date>=current_date-30) as rev30,
           (select coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
              from gl_journal_lines l join gl_journal j on j.id=l.journal_id and j.status='posted'
              join gl_accounts ga on ga.code=l.account_code where j.entry_date>=current_date-30) as exp30
  ),
  hz as (
    select h,
      (select coalesce(sum(amount_due),0) from supplier_dues where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date_30,reveal_date+30) <= current_date + h) as ar_in,
      (select coalesce(sum(balance_due),0) from ap_open_bills where coalesce(due_date, bill_date) <= current_date + h) as ap_out
    from (values (30),(60),(90)) v(h)
  )
  select jsonb_build_object(
    'as_of', now(),
    'cash_now', (select cash from base),
    'assumptions', jsonb_build_object('revenue_run_rate_30d',(select rev30 from base),'expense_run_rate_30d',(select exp30 from base)),
    'horizons', (select jsonb_agg(jsonb_build_object(
        'days', h,
        'expected_inflows', round(ar_in + (select rev30 from base)*(h/30.0), 2),
        'expected_outflows', round(ap_out + (select exp30 from base)*(h/30.0), 2),
        'projected_cash', round((select cash from base) + ar_in + (select rev30 from base)*(h/30.0) - ap_out - (select exp30 from base)*(h/30.0), 2),
        'revenue_forecast', round((select rev30 from base)*(h/30.0), 2)
      ) order by h) from hz)
  );
$function$;

-- fn_ws_finance()
CREATE OR REPLACE FUNCTION public.fn_ws_finance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  cash_total numeric(18,2); rev_total numeric(18,2); exp_total numeric(18,2);
  rev30 numeric(18,2); exp30 numeric(18,2); monthly_burn numeric(18,2); runway numeric(18,1);
  j jsonb;
begin
  select coalesce(sum(balance),0) into cash_total from public.gl_account_balances where code in ('1000','1050');
  select coalesce(sum(balance),0) into rev_total from public.gl_account_balances where type='revenue';
  select coalesce(sum(balance),0) into exp_total from public.gl_account_balances where type='expense';

  -- 30-day run-rate (posted activity)
  select
    coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0),
    coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
    into rev30, exp30
  from public.gl_journal_lines l
  join public.gl_journal j2 on j2.id=l.journal_id and j2.status='posted'
  join public.gl_accounts ga on ga.code=l.account_code
  where j2.entry_date >= current_date - 30;

  monthly_burn := exp30 - rev30;                       -- net cash burn (positive = burning)
  runway := case when monthly_burn > 0 and cash_total > 0 then round(cash_total/monthly_burn,1) else null end;

  j := jsonb_build_object(
    'as_of', now(),
    'cash', jsonb_build_object(
      'total', cash_total,
      'accounts', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'balance',balance) order by code)
                   from public.gl_account_balances where code in ('1000','1050','1100','1110','1150','1500','1600')),'[]'::jsonb)
    ),
    'pnl', jsonb_build_object(
      'revenue', rev_total, 'expenses', exp_total, 'net_income', rev_total-exp_total,
      'margin_pct', case when rev_total>0 then round(100.0*(rev_total-exp_total)/rev_total,1) else null end
    ),
    'run_rate', jsonb_build_object(
      'revenue_30d', rev30, 'expense_30d', exp30, 'net_30d', rev30-exp30,
      'arr_estimate', round(rev30*12,2), 'monthly_burn', monthly_burn,
      'runway_months', runway
    ),
    'monetization', jsonb_build_object(
      'reveal_fees', (select coalesce(balance,0) from public.gl_account_balances where code='4000'),
      'commissions', (select coalesce(balance,0) from public.gl_account_balances where code='4100'),
      'registration', (select coalesce(balance,0) from public.gl_account_balances where code='4200'),
      'stripe_fees', (select coalesce(balance,0) from public.gl_account_balances where code='6100')
    ),
    'revenue_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='revenue' and balance<>0),'[]'::jsonb),
    'expense_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='expense' and balance<>0),'[]'::jsonb),
    'receivables', jsonb_build_object(
      'commission_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1110'),
      'trade_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1100'),
      'overdue_commissions', (select coalesce(sum(amount_due),0) from public.supplier_dues
                              where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date,reveal_date) < current_date)
    ),
    'payables', jsonb_build_object(
      'ap_open', (select coalesce(sum(total-amount_paid),0) from public.ap_bills where status in ('open','partial')),
      'aging', coalesce((select jsonb_agg(to_jsonb(a)) from public.ap_aging a),'[]'::jsonb)
    ),
    'cashflow', coalesce((
      select jsonb_agg(x order by x->>'month')
      from (
        select jsonb_build_object(
          'month', to_char(date_trunc('month',j3.entry_date),'YYYY-MM'),
          'inflow', sum(l.debit), 'outflow', sum(l.credit), 'net', sum(l.debit-l.credit)
        ) x
        from public.gl_journal_lines l
        join public.gl_journal j3 on j3.id=l.journal_id and j3.status='posted'
        where l.account_code in ('1000','1050')
          and j3.entry_date >= (date_trunc('month',current_date) - interval '5 months')
        group by date_trunc('month',j3.entry_date)
      ) s
    ),'[]'::jsonb),
    'budgets', coalesce((select jsonb_agg(to_jsonb(b)) from public.budget_vs_actual_summary b),'[]'::jsonb)
  );
  j := j || jsonb_build_object('ai', jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.finance_kpis k),
    'forecast', public.fn_finance_forecast(),
    'health', (select (kpis->>'health')::numeric from public.finance_kpi_snapshots order by snapshot_date desc limit 1),
    'open_alerts', (select count(*) from public.agent_actions where agent='finance_ai' and status in ('pending','needs_review')),
    'alerts', coalesce((select jsonb_agg(jsonb_build_object('signal',detail->>'signal','risk',risk,'title',title,'reco',recommendation))
        from public.agent_actions where agent='finance_ai' and status in ('pending','needs_review')),'[]'::jsonb),
    'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'health'),'cash',(kpis->>'cash')) order by snapshot_date)
        from (select snapshot_date,kpis from public.finance_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
  ));
  return j;
end $function$;

-- fn_ws_supplier_360(bigint)
CREATE OR REPLACE FUNCTION public.fn_ws_supplier_360(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare l public.leads%rowtype; j jsonb; docs jsonb := '[]'::jsonb;
begin
  select * into l from public.leads where id=p_id;
  if l.id is null then return jsonb_build_object('error','supplier not found'); end if;

  -- documents from path fields
  if l.license_doc_path is not null then docs:=docs||jsonb_build_object('type','Trade licence','name',coalesce(l.license_doc_name,'licence'),'path',l.license_doc_path); end if;
  if l.iban_doc_path is not null then docs:=docs||jsonb_build_object('type','Bank/IBAN','name',coalesce(l.iban_doc_name,'iban'),'path',l.iban_doc_path); end if;
  if l.egr_doc_path is not null then docs:=docs||jsonb_build_object('type','Establishment card','name',coalesce(l.egr_doc_name,'egr'),'path',l.egr_doc_path); end if;
  if l.insurance_doc_path is not null then docs:=docs||jsonb_build_object('type','Insurance','name','insurance','path',l.insurance_doc_path); end if;
  if l.vat_doc_path is not null then docs:=docs||jsonb_build_object('type','VAT certificate','name','vat','path',l.vat_doc_path); end if;
  if l.company_profile_doc_path is not null then docs:=docs||jsonb_build_object('type','Company profile','name','profile','path',l.company_profile_doc_path); end if;
  if l.signed_terms_path is not null then docs:=docs||jsonb_build_object('type','Signed terms','name','terms','path',l.signed_terms_path); end if;
  if l.catalog_doc_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Catalogue','name','catalogue','path',x))
                              from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
  end if;

  j := jsonb_build_object(
    'profile', jsonb_build_object(
      'id', l.id, 'company_name', l.company_name, 'sector', l.sector, 'sub_type', l.sub_type,
      'emirate', l.emirate, 'city', l.city, 'phone', coalesce(l.phone_e164,l.phone), 'email', l.email,
      'website', l.website, 'contact_name', l.contact_name, 'founded_year', l.founded_year,
      'company_size', l.company_size, 'employee_count', l.employee_count, 'business_role', l.business_role,
      'lifecycle_stage', l.lifecycle_stage, 'claimed', l.claimed
    ),
    'status', jsonb_build_object(
      'approval_status', l.approval_status, 'verified', l.verified, 'verification_status', l.verification_status,
      'registration_status', l.registration_status, 'matching_blocked', l.matching_blocked,
      'matching_block_reason', l.matching_block_reason, 'banned', l.banned, 'banned_reason', l.banned_reason,
      'chat_strikes', l.chat_strikes
    ),
    'ai', jsonb_build_object(
      'capability_summary', l.capability_summary, 'capability_score', l.capability_score,
      'review_notes', l.ai_review_notes, 'review_flags', l.ai_review_flags, 'reviewed_at', l.ai_reviewed_at,
      'twin', coalesce((select to_jsonb(tw) from public.supplier_twin tw where tw.supplier_id=p_id),'{}'::jsonb)
    ),
    'compliance', jsonb_build_object(
      'trade_license_no', l.trade_license_no, 'license_authority', l.license_authority,
      'license_expiry', l.license_expiry, 'trn', l.trn, 'vat_number', l.vat_number,
      'insurance_expiry', l.insurance_expiry, 'iso_certifications', l.iso_certifications,
      'certifications', l.certifications, 'accepted_terms_at', l.accepted_terms_at,
      'registration_expires_at', l.registration_expires_at,
      'license_expiring', (l.license_expiry is not null and l.license_expiry < current_date + 30),
      'insurance_expiring', (l.insurance_expiry is not null and l.insurance_expiry < current_date + 30)
    ),
    'capabilities', jsonb_build_object(
      'brands_carried', l.brands_carried, 'machinery', l.machinery, 'engineers_count', l.engineers_count,
      'team_size', l.team_size, 'warehouse_area', l.warehouse_area, 'service_emirates', l.service_emirates,
      'manufacturer_authorizations', l.manufacturer_authorizations, 'client_references', l.client_references,
      'products', l.products, 'services', l.services,
      'detail', coalesce((select to_jsonb(c) from public.supplier_capabilities c where c.supplier_id=p_id),'{}'::jsonb)
    ),
    'performance', coalesce((select jsonb_build_object(
        'matched',pf.matched,'quoted',pf.quoted,'won',pf.won,'quote_rate',pf.quote_rate,
        'win_rate',pf.win_rate,'perf_score',pf.perf_score,'rating',pf.rating,'review_count',pf.review_count)
        from public.supplier_perf pf where pf.supplier_id=p_id),'{}'::jsonb)
      || jsonb_build_object('rv_reveals',l.rv_reveals,'rv_responded',l.rv_responded,'rv_response_rate',l.rv_response_rate,
                            'app_rating',l.app_rating,'app_reviews',l.app_reviews),
    'reputation', coalesce((select to_jsonb(rp) - 'supplier_id' - 'company_name' from public.supplier_reputation rp where rp.supplier_id=p_id),'{}'::jsonb),
    'financials', (
      select jsonb_build_object(
        'deals_count', count(*) filter (where t.id is not null),
        'deal_value_total', coalesce(sum(t.quote_amount),0),
        'reveal_fees_generated', coalesce(sum(t.reveal_fee) filter (where t.fee_status='paid'),0)
      ) from public.transactions t where t.supplier_id=p_id
    ) || (
      select jsonb_build_object(
        'commission_total', coalesce(sum(amount_due),0),
        'commission_paid', coalesce(sum(amount_due) filter (where status in ('paid','settled')),0),
        'commission_owed', coalesce(sum(amount_due) filter (where public.fn_supplier_due_is_owed(status, paid_at)),0)
      ) from public.supplier_dues where supplier_id=p_id
    ),
    'documents', docs,
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
                        from (select * from public.quotes where supplier_id=p_id order by created_at desc limit 10) q),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('rating',r.rating,'comment',r.comment,'created_at',r.created_at) order by r.created_at desc)
                        from (select * from public.reviews where supplier_id=p_id order by created_at desc limit 8) r),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',l.created_at,'event','Added to directory') e where l.created_at is not null
        union all select jsonb_build_object('at',l.registration_submitted_at,'event','Registration submitted') where l.registration_submitted_at is not null
        union all select jsonb_build_object('at',l.approved_at,'event','Approved'||coalesce(' by '||l.approval_decided_by,'')) where l.approved_at is not null
        union all select jsonb_build_object('at',l.accepted_terms_at,'event','Accepted terms') where l.accepted_terms_at is not null
      ) tl),
    -- WHY WE DECIDED WHAT WE DECIDED about this supplier. decision_record holds the reasoning behind
    -- past decisions and decision_trace the policies that were applied; neither reached the supplier
    -- view, so "why did we reject Supplier X?" had no answer on the screen that shows X.
    'rejection_reason', coalesce((select jsonb_agg(jsonb_build_object(
        'id', dr.id, 'problem', dr.problem, 'recommendation', dr.recommendation,
        'risks', dr.risks, 'status', dr.status, 'decided_by', dr.decided_by,
        'actual_outcome', dr.actual_outcome, 'at', dr.created_at) order by dr.created_at desc)
      from public.decision_record dr
      where coalesce(l.company_name,'') <> ''
        and (dr.problem ilike '%'||l.company_name||'%' or dr.context ilike '%'||l.company_name||'%')), '[]'::jsonb),
    'decision_trace', coalesce((select jsonb_agg(jsonb_build_object(
        'entity_id', dt.entity_id, 'policy_keys', dt.policy_keys) order by dt.entity_id)
      from public.decision_trace dt where dt.entity_id = p_id::text), '[]'::jsonb)
  );
  return j;
end $function$;

-- fn_ops_dashboard()
CREATE OR REPLACE FUNCTION public.fn_ops_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  active_rfqs int; rfqs_today int; done_today int; ttfq numeric; qpr numeric;
  accept_rate numeric; conv numeric;
  rev_today numeric; rev_month numeric; pending_fees numeric; outstanding_inv int; cash_recv numeric;
  ai_conf numeric; waiting int; onboard_q int; disputes int; escalations int; held int; with_ceo int;
  uptime numeric; queue_size int; failed int; last_backup timestamptz; api_lat numeric;
  health jsonb;
  v_dc uuid[]; v_dl bigint[]; v_di uuid[];
begin
  -- DEMO: the three id sets every business count below leaves out.
  select coalesce(array_agg(id), '{}') into v_dc from customers where is_demo;
  select coalesce(array_agg(id), '{}') into v_dl from leads where is_demo;
  select coalesce(array_agg(id), '{}') into v_di from inquiries where public.fn_inquiry_is_demo(id);

  -- MARKETPLACE
  select count(*) into active_rfqs from inquiries where status not in ('completed','accepted','closed','cancelled') and (id = any (v_di)) is not true;
  select count(*) into rfqs_today from inquiries where created_at::date=current_date and (id = any (v_di)) is not true;
  select count(*) into done_today from inquiries where ((completed_at::date=current_date) or (status in ('completed','accepted') and stage_changed_at::date=current_date)) and (id = any (v_di)) is not true;
  select round(avg(extract(epoch from (fq - ic))/3600.0),1) into ttfq from (
    select i.created_at ic, min(q.created_at) fq from inquiries i join quotes q on q.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true and (q.supplier_id = any (v_dl)) is not true
    group by i.id) z where fq is not null;
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id
    where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true and (q.supplier_id = any (v_dl)) is not true
    group by q.inquiry_id) z;
  select round(avg(nullif(rv_response_rate,0)) ,1) into accept_rate from leads where coalesce(rv_reveals,0)>0 and (id = any (v_dl)) is not true;
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id and (t.supplier_id = any (v_dl)) is not true
   where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true;

  -- REVENUE
  select coalesce(sum(reveal_fee),0) into rev_today from transactions where revealed_at::date=current_date and coalesce(refund_status,'')<>'approved'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  select coalesce(sum(reveal_fee),0) into rev_month from transactions where date_trunc('month',revealed_at)=date_trunc('month',now()) and coalesce(refund_status,'')<>'approved'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  begin select coalesce(sum(amount_due),0) into pending_fees from supplier_dues where public.fn_supplier_due_is_owed(status, paid_at) and (supplier_id = any (v_dl)) is not true; exception when others then pending_fees:=0; end;
  begin select count(*) into outstanding_inv from reveal_invoices ri left join transactions t on t.id=ri.transaction_id where coalesce(t.fee_status,'')<>'paid'
     and (t.customer_id = any (v_dc)) is not true and (t.supplier_id = any (v_dl)) is not true and (t.inquiry_id = any (v_di)) is not true; exception when others then outstanding_inv:=0; end;
  select coalesce(sum(reveal_fee),0) into cash_recv from transactions where coalesce(fee_status,'')='paid'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;

  -- OPERATIONS
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into ai_conf
    from quotes where created_at>=now()-interval '7 days' and (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true;
  select count(*) into waiting from inquiries where status in ('clarify','clarifying','awaiting_customer','needs_info') and (id = any (v_di)) is not true;
  select count(*) into onboard_q from leads where approval_status='pending' and (id = any (v_dl)) is not true;
  select count(*) into disputes from transactions where refund_status='requested'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  -- REFUNDS ARE THE CEO'S. Open = a refunds row still 'requested'. What reaches the founder is only the
  -- CEO's summary when that refund's latest review cycle escalated, plus severe alerts.
  select count(*), count(*) filter (where rv.outcome = 'escalated') into with_ceo, escalations
    from refunds r
    left join lateral (select x.outcome from refund_ceo_review x where x.refund_id = r.id order by x.cycle desc limit 1) rv on true
   where r.status = 'requested'
     and (r.customer_id = any (v_dc)) is not true and (r.supplier_lead_id = any (v_dl)) is not true and (r.inquiry_id = any (v_di)) is not true;
  escalations := escalations
        + (select count(*) from founder_alerts where public.fn_alert_severe(level) and created_at>=now()-interval '24 hours');
  select count(*) into held from agent_actions a left join agent_action_kind_policy p on p.kind=a.kind
   where a.status in ('pending','needs_review') and coalesce(p.policy,'')<>'founder';

  -- INFRASTRUCTURE
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into uptime from health_checks where created_at>=now()-interval '24 hours';
  select count(*) into queue_size from notifications where coalesce(status,'')in('queued','pending','');
  begin select count(*) into failed from agent_runs where status='error' and coalesce(finished_at,started_at)>=now()-interval '24 hours'; exception when others then failed:=0; end;
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  select round(avg(latency_ms),0) into api_lat from health_checks where created_at>=now()-interval '1 hour' and latency_ms is not null;

  return jsonb_build_object(
    'as_of', now(),
    'marketplace', jsonb_build_object('active_rfqs',active_rfqs,'rfqs_today',rfqs_today,'completed_today',done_today,
        'avg_hours_to_first_quote',ttfq,'avg_quotes_per_rfq',qpr,'supplier_acceptance_pct',accept_rate,'conversion_pct',conv),
    'revenue', jsonb_build_object('today_aed',rev_today,'month_aed',rev_month,'pending_fees_aed',pending_fees,
        'outstanding_invoices',outstanding_inv,'cash_received_aed',cash_recv),
    'operations', jsonb_build_object('ai_confidence_pct',ai_conf,'rfqs_waiting_clarification',waiting,
        'onboarding_queue',onboard_q,'disputes',disputes,'escalations',escalations,'refunds_with_ceo',with_ceo,'held_with_roles',held),
    'infrastructure', jsonb_build_object('uptime_pct',uptime,'queue_size',queue_size,'failed_jobs_24h',failed,
        'backup_age_hours', case when last_backup is null then null else round(extract(epoch from (now()-last_backup))/3600.0,1) end,
        'api_latency_ms',api_lat),
    'health_index', coalesce(health->>'index',null));
end $function$;

-- finance_kpis (live definition; the two receivable filters)
create or replace view public.finance_kpis as
 WITH rr AS (
         SELECT COALESCE(sum(
                CASE
                    WHEN (ga.type = 'revenue'::text) THEN (l.credit - l.debit)
                    ELSE (0)::numeric
                END), (0)::numeric) AS rev30,
            COALESCE(sum(
                CASE
                    WHEN (ga.type = 'expense'::text) THEN (l.debit - l.credit)
                    ELSE (0)::numeric
                END), (0)::numeric) AS exp30
           FROM ((gl_journal_lines l
             JOIN gl_journal j ON (((j.id = l.journal_id) AND (j.status = 'posted'::text))))
             JOIN gl_accounts ga ON ((ga.code = l.account_code)))
          WHERE (j.entry_date >= (CURRENT_DATE - 30))
        ), ar AS (
         SELECT COALESCE(sum(supplier_dues.amount_due) FILTER (WHERE public.fn_supplier_due_is_owed(supplier_dues.status, supplier_dues.paid_at)), (0)::numeric) AS ar_outstanding,
            COALESCE(sum(supplier_dues.amount_due) FILTER (WHERE (public.fn_supplier_due_is_owed(supplier_dues.status, supplier_dues.paid_at) AND (supplier_dues.due_date_30 < CURRENT_DATE))), (0)::numeric) AS ar_overdue,
            COALESCE(sum(supplier_dues.amount_due) FILTER (WHERE (supplier_dues.status = 'paid'::text)), (0)::numeric) AS ar_collected
           FROM supplier_dues
        ), ap AS (
         SELECT COALESCE(sum(ap_open_bills.balance_due), (0)::numeric) AS ap_outstanding,
            COALESCE(sum(ap_open_bills.balance_due) FILTER (WHERE (ap_open_bills.days_overdue > 0)), (0)::numeric) AS ap_overdue
           FROM ap_open_bills
        ), bud AS (
         SELECT count(*) FILTER (WHERE ((budget_vs_actual_summary.type = 'expense'::text) AND (budget_vs_actual_summary.pct_of_budget > (110)::numeric))) AS budget_overruns
           FROM budget_vs_actual_summary
        )
 SELECT ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.code = ANY (ARRAY['1000'::text, '1050'::text]))) AS cash,
    ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'revenue'::text)) AS revenue_total,
    ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'expense'::text)) AS expense_total,
    (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'revenue'::text)) - ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'expense'::text))) AS net_income,
        CASE
            WHEN (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'revenue'::text)) > (0)::numeric) THEN round(((100.0 * (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'revenue'::text)) - ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'expense'::text)))) / ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'revenue'::text))), 1)
            ELSE NULL::numeric
        END AS margin_pct,
    rr.rev30 AS revenue_30d,
    rr.exp30 AS expense_30d,
    (rr.exp30 - rr.rev30) AS monthly_burn,
        CASE
            WHEN (((rr.exp30 - rr.rev30) > (0)::numeric) AND (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = ANY (ARRAY['1000'::text, '1050'::text]))) > (0)::numeric)) THEN round((( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = ANY (ARRAY['1000'::text, '1050'::text]))) / (rr.exp30 - rr.rev30)), 1)
            ELSE NULL::numeric
        END AS runway_months,
    ar.ar_outstanding,
    ar.ar_overdue,
    ar.ar_collected,
        CASE
            WHEN ((ar.ar_collected + ar.ar_outstanding) > (0)::numeric) THEN round(((100.0 * ar.ar_collected) / (ar.ar_collected + ar.ar_outstanding)), 1)
            ELSE NULL::numeric
        END AS collection_rate,
    ap.ap_outstanding,
    ap.ap_overdue,
    bud.budget_overruns
   FROM rr,
    ar,
    ap,
    bud;

-- ── 4. fn_ban_overdue_dues WAS CALLABLE BY anon AND authenticated ─────────────────────────────────
-- Measured 15 Sep 2026: its ACL granted EXECUTE to PUBLIC, anon and authenticated. It is SECURITY
-- INVOKER, so RLS bounds what a caller's statements can touch, but a routine that bans suppliers and
-- pages the founder is not a client RPC. CREATE OR REPLACE above preserved that ACL; closed here.
revoke execute on function public.fn_ban_overdue_dues() from public, anon, authenticated;
grant execute on function public.fn_ban_overdue_dues() to service_role;
