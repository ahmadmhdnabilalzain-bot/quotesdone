-- SCOPE CORRECTION caught by the 6.5(f) probe, which asserted something 6.3's own probe never did:
-- that a NEWLY INSERTED approved supplier is matchable.
--
-- It was not. The licence-gate trigger fires on INSERT (a column list on `update of` does not apply
-- to inserts), found no trade licence document on a brand-new row, and demoted it to
-- action_required with a 14-day clock before the supplier had reached the document step. Since
-- auto_approve_suppliers is true, that would have put EVERY new registration into the exception
-- queue and out of matching the moment they registered.
--
-- The gate's job in 6.3 is corrected-document recovery, not onboarding policy. So:
--   demote  only when there IS licence evidence and it FAILS (a document on file that is expired,
--           or whose number could not be read)
--   recover whenever the evidence passes, which is the whole point of 6.3
--   absence of a document is not this trigger's business - the registration flow owns that, and
--   silently changing it here would be a behaviour change nobody asked for.
create or replace function public.fn_leads_licence_gate_rerun()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare g jsonb; has_doc boolean;
begin
  if tg_op = 'UPDATE'
     and new.license_doc_path  is not distinct from old.license_doc_path
     and new.trade_license_no  is not distinct from old.trade_license_no
     and new.license_expiry    is not distinct from old.license_expiry then
    return new;
  end if;

  has_doc := coalesce(new.license_doc_path, '') <> '';
  g := public.fn_supplier_licence_gate(new.license_doc_path, new.trade_license_no, new.license_expiry);

  if (g ->> 'ok')::boolean then
    if coalesce(new.approval_status,'') = 'action_required' then
      new.approval_status     := 'approved';
      new.licence_gate_reason := null;
    elsif coalesce(new.approval_status,'') = 'rejected'
          and coalesce(new.exception_outcome,'') = 'expired_auto_rejected' then
      new.approval_status     := 'approved';
      new.licence_gate_reason := null;
      new.exception_outcome   := 'recovered_after_auto_reject';
    end if;
  elsif has_doc then
    -- Evidence exists and fails. THIS is the case worth acting on.
    if coalesce(new.approval_status,'') in ('approved','verified') then
      new.approval_status     := 'action_required';
      new.licence_gate_reason := g ->> 'reason';
    elsif coalesce(new.approval_status,'') = 'action_required' then
      new.licence_gate_reason := g ->> 'reason';
    end if;
  end if;
  return new;
end $fn$;;
