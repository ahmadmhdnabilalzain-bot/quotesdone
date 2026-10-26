-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727014208   name: duplicate_invoice_control
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Layer-4 remediation, part 2: the duplicate_payment scenario.
-- Found: ap_bills had no unique constraint and no trigger; the same
-- invoice was booked twice and PAID twice (AED 10,500 out the door),
-- fn_fraud_scan had no rule that reads any payment table, and nothing
-- was written anywhere, so the episode left no trace at all.
-- ================================================================

-- 1. Hard stop at the source. The same vendor cannot present the same
--    invoice number twice, full stop.
create unique index if not exists ap_bills_vendor_billno_uidx
  on public.ap_bills (vendor_id, bill_no)
  where bill_no is not null and status <> 'void';

-- 2. Near-duplicates that dodge the number: same vendor, same amount,
--    same date, different reference. Blocked with a message a person can act on.
create or replace function public.fn_ap_bill_dupe_guard() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare v_prior bigint;
begin
  select id into v_prior from ap_bills
  where vendor_id = new.vendor_id
    and coalesce(status,'') <> 'void'
    and id is distinct from new.id
    and total = new.total
    and bill_date = new.bill_date
  limit 1;

  if v_prior is not null then
    insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
    values ('fake_supplier','high','ap_bill', new.bill_no, 'duplicate_invoice_presented',
            'Same vendor, same amount, same date as an invoice already booked.',
            jsonb_build_object('vendor_id', new.vendor_id, 'total', new.total,
                               'bill_date', new.bill_date, 'prior_bill_id', v_prior,
                               'presented_bill_no', new.bill_no))
    on conflict do nothing;

    insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                      money_aed, learned_by, confidence, evidence_ref)
    values ('pattern','ap_bill', new.bill_no,
            'Duplicate invoice presentation blocked.',
            format('Vendor %s presented %s for %s on %s, matching bill id %s already on file.',
                   new.vendor_id, new.bill_no, new.total, new.bill_date, v_prior),
            'blocked before posting', new.total, 'finance_bookkeeper', 1.0,
            'trg_ap_bill_dupe_guard; ap_bills id ' || v_prior);

    raise exception 'duplicate invoice: vendor % already has bill id % for % on % - void it or reference it before booking %',
      new.vendor_id, v_prior, new.total, new.bill_date, new.bill_no;
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_ap_bill_dupe_guard on public.ap_bills;
create trigger trg_ap_bill_dupe_guard before insert on public.ap_bills
for each row execute function public.fn_ap_bill_dupe_guard();

revoke execute on function public.fn_ap_bill_dupe_guard() from anon, authenticated, public;

-- 3. Give the fraud scanner a rule that actually reads the payment tables,
--    so an already-booked duplicate that predates the guard is still surfaced.
create or replace function public.fn_ap_duplicate_scan() returns integer
language plpgsql security definer set search_path = public as $fn$
declare n integer := 0;
begin
  insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
  select 'fake_supplier','critical','ap_bill', min(b.bill_no), 'duplicate_invoice_booked',
         'More than one non-void bill exists for the same vendor, amount and date.',
         jsonb_build_object('vendor_id', b.vendor_id, 'total', b.total, 'bill_date', b.bill_date,
                            'bill_ids', array_agg(b.id order by b.id), 'count', count(*))
  from ap_bills b
  where coalesce(b.status,'') <> 'void'
  group by b.vendor_id, b.total, b.bill_date
  having count(*) > 1
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end; $fn$;

revoke execute on function public.fn_ap_duplicate_scan() from anon, authenticated, public;

insert into public.org_action_executor (action_class, kind, target, params, active, note, advisory_safe, department)
values ('ap_duplicate_scan','rpc','fn_ap_duplicate_scan','{}'::jsonb, true,
        'Deterministic sweep for duplicate supplier invoices already booked. Complements the insert-time guard.', false, 'finance')
on conflict do nothing;
