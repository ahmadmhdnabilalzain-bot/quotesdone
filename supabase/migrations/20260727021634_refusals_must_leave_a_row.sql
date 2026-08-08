-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727021634   name: refusals_must_leave_a_row
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Re-verification found a defect in the controls built earlier today:
-- both refused by RAISE EXCEPTION, which rolls back the very audit rows
-- that record the refusal. A block that leaves no trace is not auditable.
-- Both now REFUSE BY QUARANTINE: the row persists in a blocked state,
-- carrying the reason, and cannot progress.
-- ================================================================

alter table public.decision_record
  add column if not exists gate_verdict text,
  add column if not exists gate_reason  text,
  add column if not exists gate_checked_at timestamptz;

create or replace function public.fn_decision_gate() returns trigger
language plpgsql as $fn$
declare v_was text; v_spend jsonb; v_reason text;
begin
  v_was := case when tg_op = 'UPDATE' then coalesce(old.status,'') else '' end;

  if new.status in ('approved','executed') and v_was not in ('approved','executed') then
    v_reason := null;

    if coalesce(length(new.impact_business),0)  < 20
    or coalesce(length(new.impact_financial),0) < 20
    or coalesce(length(new.impact_legal),0)     < 10
    or coalesce(length(new.impact_customer),0)  < 20
    or jsonb_array_length(coalesce(new.evidence,'[]'::jsonb)) = 0 then
      v_reason := 'Impact analysis incomplete: business, financial, legal and customer impact plus at least one evidence reference are all required before approval.';
    end if;

    if v_reason is null and coalesce(new.financial_aed,0) > 0 then
      v_spend := public.fn_check_spend(new.dept_key, new.financial_aed, new.approved_by);
      if not coalesce((v_spend->>'affordable')::boolean, false) then
        v_reason := v_spend->>'reason';
      elsif coalesce(new.financial_aed,0) > 10000 and coalesce(new.approved_by,'') not in ('founder','ceo') then
        v_reason := format('AED %s is above the AED 10,000 founder threshold and approved_by is "%s".', new.financial_aed, coalesce(new.approved_by,'(none)'));
      elsif coalesce(new.financial_aed,0) >= 1000 and coalesce(new.approved_by,'') not in ('brief','founder','ceo') then
        v_reason := format('AED %s needs Chief of Staff approval and approved_by is "%s".', new.financial_aed, coalesce(new.approved_by,'(none)'));
      end if;
    end if;

    if v_reason is not null then
      -- Refuse, and leave the refusal on the row rather than aborting the transaction
      -- and losing every trace of it.
      new.status          := 'blocked_by_gate';
      new.gate_verdict    := 'refused';
      new.gate_reason     := v_reason;
      new.gate_checked_at := now();
      raise warning 'decision refused by gate: %', v_reason;
    else
      new.gate_verdict    := 'passed';
      new.gate_reason     := null;
      new.gate_checked_at := now();
    end if;
  end if;
  return new;
end; $fn$;

revoke execute on function public.fn_decision_gate() from anon, authenticated, public;

-- ---- the same fix for the AP duplicate guard ----
create or replace function public.fn_ap_bill_dupe_guard() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare v_prior bigint;
begin
  if coalesce(new.status,'') in ('void','duplicate_hold') then return new; end if;

  select id into v_prior from ap_bills
  where vendor_id = new.vendor_id
    and coalesce(status,'') not in ('void','duplicate_hold')
    and id is distinct from new.id
    and total = new.total
    and bill_date = new.bill_date
  order by id limit 1;

  if v_prior is not null then
    new.status := 'duplicate_hold';

    insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
    values ('fake_supplier','critical','ap_bill', coalesce(new.bill_no, new.id::text), 'duplicate_invoice_presented',
            'Same vendor, same amount, same date as an invoice already booked. Held, not posted.',
            jsonb_build_object('vendor_id', new.vendor_id, 'total', new.total,
                               'bill_date', new.bill_date, 'prior_bill_id', v_prior,
                               'presented_bill_no', new.bill_no))
    on conflict do nothing;

    insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                      money_aed, learned_by, confidence, evidence_ref)
    values ('pattern','ap_bill', coalesce(new.bill_no, new.id::text),
            'Duplicate invoice presentation held before payment.',
            format('Vendor %s presented %s for %s on %s, matching bill id %s already on file.',
                   new.vendor_id, coalesce(new.bill_no,'(no ref)'), new.total, new.bill_date, v_prior),
            'held as duplicate_hold; not posted, not paid', new.total, 'finance_bookkeeper', 1.0,
            'trg_ap_bill_dupe_guard; ap_bills id ' || v_prior);

    insert into company_event (event_type, entity_type, entity_id, actor, payload)
    values ('invoice.flagged','ap_bill', coalesce(new.bill_no, new.id::text), 'finance_bookkeeper',
            jsonb_build_object('reason','duplicate_invoice','vendor_id', new.vendor_id,
                               'total', new.total,'prior_bill_id', v_prior));

    raise warning 'invoice held as duplicate of bill id %', v_prior;
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_ap_bill_dupe_guard on public.ap_bills;
create trigger trg_ap_bill_dupe_guard before insert or update on public.ap_bills
for each row execute function public.fn_ap_bill_dupe_guard();

revoke execute on function public.fn_ap_bill_dupe_guard() from anon, authenticated, public;

-- A held bill must never be paid, whatever route the payment takes.
create or replace function public.fn_ap_pay_block_held() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.status in ('paid','part_paid') and coalesce(old.status,'') = 'duplicate_hold' then
    raise exception 'bill % is held as a duplicate and cannot be paid until a person clears the hold', coalesce(new.bill_no, new.id::text);
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_ap_pay_block_held on public.ap_bills;
create trigger trg_ap_pay_block_held before update on public.ap_bills
for each row execute function public.fn_ap_pay_block_held();

revoke execute on function public.fn_ap_pay_block_held() from anon, authenticated, public;

-- Finance must hear about an over-budget request. It had no subscription at all.
insert into public.event_subscription (agent_key, event_type, reason, active) values
('cfo','invoice.flagged','Owns supplier payments and is accountable for money leaving the company.', true),
('cfo','budget.exceeded','A department asking for more than it has is a Finance decision, not a department one.', true),
('brief','budget.exceeded','Chief of Staff arbitrates when a department''s plan does not fit its budget.', true)
on conflict do nothing;

create or replace function public.fn_emit_budget_exceeded(p_dept text, p_amount numeric, p_requested_by text, p_purpose text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare v jsonb;
begin
  v := fn_check_spend(p_dept, p_amount, p_requested_by);
  if not coalesce((v->>'affordable')::boolean, true) then
    insert into company_event (event_type, entity_type, entity_id, actor, payload)
    values ('budget.exceeded','department', p_dept, coalesce(p_requested_by,'system'),
            jsonb_build_object('requested_aed', p_amount, 'available_aed', v->>'available_aed',
                               'purpose', p_purpose, 'reason', v->>'reason'));
  end if;
  return v;
end; $fn$;

revoke execute on function public.fn_emit_budget_exceeded(text,numeric,text,text) from anon, authenticated, public;
