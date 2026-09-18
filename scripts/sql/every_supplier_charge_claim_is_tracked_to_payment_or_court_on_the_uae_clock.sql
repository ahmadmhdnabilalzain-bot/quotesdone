-- EVERY SUPPLIER-CHARGE CLAIM IS TRACKED FROM NOTICE TO PAYMENT OR COURT, ON THE UAE CLOCK.
--
-- Assigned: accountant. Founder, 14 Sep 2026: "add all for accountant and IT" — duty 3 of the five further
-- accountant duties: a recovery ledger of every claim (refund + AED 250 + 9% a year simple interest from the
-- due date, never compounded), tracked from notice to payment or court with its UAE deadlines.
--
-- WHAT WAS MEASURED (14 Sep 2026, the repository at #645's head):
--   * The claim and its first half are built. fn_accountant_raise_nonresponse_charge raises the charge and
--     fn_supplier_dues_accrue_interest keeps the 9% simple interest current (_shared/supplier_charge.ts).
--     #645's collections duty (the_accountant_chases_what_a_silent_supplier_owes.sql) sends the reminders,
--     the formal demand (legal_stage 'final_demand_sent', legal_escalated_at), moves the due to
--     'filing_pack_due' when the demand's period runs out, warns on the CTL Art 92 limitation, and takes
--     the founder's filing outcome (fn_accountant_record_filing_outcome).
--   * NOTHING FOLLOWED A CLAIM INTO COURT. Once the founder recorded 'filed', supplier_dues had no column for
--     the payment order, its service or a grievance, so the three deadlines docs/legal/SUPPLIER_CHARGE_
--     RECOVERY_UAE.md §3b sets after filing were watched by nobody: the order is void if not served within
--     3 months (CPL 42/2022 Art 146(2)); the debtor may object within 15 days of service (Art 147(1)); and
--     unobjected, the order is final and is enforced.
--   * There was no single place to read a claim's whole life: notice, demand, filing, order, service,
--     objection, payment, and the limitation date.
--
-- WHAT THIS BUILDS:
--   supplier_dues gains payment_order_filed_on, payment_order_issued_on, payment_order_served_on,
--   grievance_filed_on and court_reference.
--   v_accountant_recovery_ledger    one row per claim with every UAE date worked out from decision_policy
--   fn_accountant_record_court_step what happened in court, recorded by the founder through the accountant
--                                   runtime (action court_step). A fact is never refused for being late:
--                                   a late service or a filing before the demand's period ran out is
--                                   recorded, and is a CEO finding.
--   fn_accountant_recovery_tick     the hourly duty for claims in court, settled through the IT loop
--   fn_accountant_recovery_position the ledger's totals for the CEO's monthly report
--
-- THE LEGAL DOCUMENT PACK IS NOT REBUILT. The ledger names it: docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md
-- (the law, the timeline, the documents) and supabase/functions/_shared/supplier_charge_documents.ts (the
-- renderer), with each claim's demand_letter_path and case_file_path.
--
--   node scripts/apply_sql.mjs scripts/sql/every_supplier_charge_claim_is_tracked_to_payment_or_court_on_the_uae_clock.sql --apply --ddl

alter table public.supplier_dues add column if not exists payment_order_filed_on  date;
alter table public.supplier_dues add column if not exists payment_order_issued_on date;
alter table public.supplier_dues add column if not exists payment_order_served_on date;
alter table public.supplier_dues add column if not exists grievance_filed_on      date;
alter table public.supplier_dues add column if not exists court_reference         text;
comment on column public.supplier_dues.payment_order_filed_on is 'The day the payment-order application was filed (CPL 42/2022 Art 143). Recorded by fn_accountant_record_court_step.';
comment on column public.supplier_dues.payment_order_issued_on is 'The day the judge issued the payment order (CPL Art 144(4): within 3 business days of filing).';
comment on column public.supplier_dues.payment_order_served_on is 'The day the order was served on the supplier (CPL Art 146(2): within 3 months of issue, or the order is void).';
comment on column public.supplier_dues.grievance_filed_on is 'The day the supplier filed a grievance against the order (CPL Art 147(1): within 15 days of service).';

insert into public.decision_policy (key, value, description) values
  ('supplier_charge_payment_order_serve_months', '3'::jsonb,
   'CPL 42/2022 Art 146(2): a payment order not served within 3 months of issue is void (docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §3b, §4).'),
  ('supplier_charge_grievance_days', '15'::jsonb,
   'CPL 42/2022 Art 147(1): the supplier may file a grievance within 15 days of service (docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §3b, §4).'),
  ('supplier_charge_order_decision_days', '5'::jsonb,
   'CPL Art 144(4) gives the judge 3 business days after filing; 5 calendar days after filing with no order recorded is a CEO finding.'),
  ('supplier_charge_serve_warn_days', '14'::jsonb,
   'Days before the CPL Art 146(2) service deadline that an unserved payment order becomes a CEO finding.')
on conflict (key) do nothing;

-- ── 1. THE LEDGER ────────────────────────────────────────────────────────────────────────────────
-- VIEW DEFINITION CUT 18 September 2026. public.v_accountant_recovery_ledger is now owned by
-- scripts/sql/a_reversed_supplier_charge_is_never_owed.sql, which appended a 29th column, `owed`, and sits
-- LAST in MANIFEST (line 1448, after this file at 1410) — so that file, not this one, is what production
-- runs. The older body is CUT rather than left here because CREATE OR REPLACE VIEW may only ADD columns at
-- the end: replaying this file against the live view asked Postgres to remove `owed` and failed with
-- "cannot drop columns from view", which killed the whole accountant fixture batch before a single duty ran
-- (measured 18 Sep 2026, scripts/checks/the_accountant_closes_every_loop_it_opens.test.mjs). This is the
-- same treatment the removed fn_supplier_invite_followups body got in
-- scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql.
--
-- THE COMMENT AND THE REVOKE GO WITH IT (database review, 18 Sep 2026). Keeping them here looked
-- harmless — both are idempotent — but `comment on view` and `revoke on` are plain DDL that need the
-- view to EXIST. On a fresh full-MANIFEST apply this file (line 1410) runs 38 files before the one that
-- now creates the view (line 1448), so the two statements would have failed with "relation
-- public.v_accountant_recovery_ledger does not exist" and taken disaster recovery down with them.
-- a_reversed_supplier_charge_is_never_owed.sql restates both, next to the definition they describe.
-- The plpgsql functions below that READ the view are unaffected: a view named inside a dollar-quoted
-- body is not resolved until the function runs, long after both files have applied.

-- ── 2. WHAT HAPPENED IN COURT ────────────────────────────────────────────────────────────────────
-- Steps: filed, order_issued, order_served, grievance_filed, recovered (paid through the court or the
-- enforcement office), withdrawn. Each needs the step before it; none is refused for being late.
create or replace function public.fn_accountant_record_court_step(p_due_id bigint, p_step text, p_on date, p_reference text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.supplier_dues; r record; v_today date := (now() at time zone 'Asia/Dubai')::date; v_warn text[] := '{}';
begin
  if p_step not in ('filed', 'order_issued', 'order_served', 'grievance_filed', 'recovered', 'withdrawn') then
    raise exception 'a court step is one of filed, order_issued, order_served, grievance_filed, recovered, withdrawn (got %)', p_step;
  end if;
  if p_on is null or p_on > v_today then raise exception 'a court step is recorded on the day it happened, not before it (got %)', p_on; end if;
  select * into d from public.supplier_dues where id = p_due_id for update;
  if not found then raise exception 'no supplier due %', p_due_id; end if;
  if d.paid_at is not null or coalesce(d.status, '') in ('paid', 'settled', 'waived', 'cancelled') then
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
end $fn$;
revoke execute on function public.fn_accountant_record_court_step(bigint, text, date, text) from public, anon, authenticated;

-- ── 3. THE DUTY: EVERY CLAIM IN COURT, AGAINST ITS DEADLINES ─────────────────────────────────────
-- Before filing, #645's collections duty owns the claim (reminders, demand, filing pack, limitation). From
-- filing on, this duty does. Every finding is the CEO's: he and the founder act in court, and each finding
-- closes when the next step, a payment or a withdrawal is recorded.
create or replace function public.fn_accountant_recovery_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_serve_warn_days');
  v_decide int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_order_decision_days');
  r record; v_items jsonb := '[]'::jsonb; v_ev jsonb; n int := 0;
begin
  if v_warn is null or v_decide is null then
    raise exception 'decision_policy supplier_charge_serve_warn_days and supplier_charge_order_decision_days are required';
  end if;
  for r in select * from public.v_accountant_recovery_ledger
            where stage in ('filed', 'order_issued', 'order_served', 'grievance_filed') order by due_id loop
    n := n + 1;
    v_ev := jsonb_build_object('due_id', r.due_id, 'supplier', r.supplier, 'claim_aed', r.claim_aed, 'stage', r.stage,
                               'court_reference', r.court_reference, 'legal_pack', r.legal_pack, 'case_file_path', r.case_file_path);
    if r.payment_order_filed_on is not null and r.payment_order_earliest_on is not null and r.payment_order_filed_on < r.payment_order_earliest_on then
      v_items := v_items || jsonb_build_object('item', 'filed_early:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || r.due_id || ' was filed on ' || r.payment_order_filed_on || ', before the demand''s period ran out on '
                 || r.payment_order_earliest_on || ' (CPL 42/2022 Art 144(1)); the court may refuse the order',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev);
    end if;
    if r.stage = 'filed' and r.payment_order_filed_on is not null and v_as_of > r.payment_order_filed_on + v_decide then
      v_items := v_items || jsonb_build_object('item', 'order_awaited:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || r.due_id || ' was filed on ' || r.payment_order_filed_on
                 || ' and no payment order is recorded; CPL Art 144(4) gives the judge 3 business days',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev);
    elsif r.stage = 'order_issued' and v_as_of >= r.serve_order_by - v_warn then
      v_items := v_items || jsonb_build_object('item', 'serve:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', case when v_as_of > r.serve_order_by
                      then 'The payment order on charge #' || r.due_id || ' was not served by ' || r.serve_order_by || ' and is void (CPL Art 146(2)); file again or withdraw'
                      else 'The payment order on charge #' || r.due_id || ' must be served by ' || r.serve_order_by || ' or it is void (CPL Art 146(2))' end,
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev || jsonb_build_object('serve_order_by', r.serve_order_by));
    elsif r.stage = 'order_served' and v_as_of > r.grievance_until then
      v_items := v_items || jsonb_build_object('item', 'enforce:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'No grievance against the payment order on charge #' || r.due_id || ' by ' || r.grievance_until
                 || ' (CPL Art 147(1)): the order is final; apply for execution and record the recovery',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev || jsonb_build_object('grievance_until', r.grievance_until));
    elsif r.stage = 'grievance_filed' then
      v_items := v_items || jsonb_build_object('item', 'grievance:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', r.supplier || ' filed a grievance on ' || r.grievance_filed_on || ' against the payment order on charge #' || r.due_id
                 || '; the court decides it, and the outcome is recorded here',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev);
    end if;
  end loop;
  return jsonb_build_object('in_court', n, 'findings', public.fn_accountant_duty_settle('recovery', v_items));
end $fn$;
revoke execute on function public.fn_accountant_recovery_tick(date) from public, anon, authenticated;

create or replace function public.fn_accountant_recovery_position()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'open_claims', count(*) filter (where stage not in ('paid', 'settled', 'waived', 'cancelled')),
    'open_aed', coalesce(sum(claim_aed) filter (where stage not in ('paid', 'settled', 'waived', 'cancelled')), 0),
    'in_court', count(*) filter (where stage in ('filed', 'order_issued', 'order_served', 'grievance_filed')),
    'by_stage', coalesce((select jsonb_object_agg(stage, n) from (select stage, count(*) n from public.v_accountant_recovery_ledger
                                                                   where not demo group by stage) s), '{}'::jsonb),
    'recovered_aed', coalesce(sum(claim_aed) filter (where stage in ('paid', 'settled')), 0),
    'basis', 'public.v_accountant_recovery_ledger, ZZ DEMO suppliers excluded. claim_aed is the refund, the AED 250 fee and the 9% simple interest accrued by fn_supplier_dues_accrue_interest.')
  from public.v_accountant_recovery_ledger where not demo;
$fn$;
revoke execute on function public.fn_accountant_recovery_position() from public, anon, authenticated;
