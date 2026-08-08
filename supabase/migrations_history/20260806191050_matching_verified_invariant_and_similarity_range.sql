-- ROW #4 MATCHING, 6 Aug 2026. Two defects in the matching lane, both measured on production.
--
-- ═══ 1. THE APPROVAL COLUMNS DRIFT, AND THE DRIFT MAKES A SUPPLIER PERMANENTLY UNMATCHABLE ═══
--
-- 20260803181750_matching_single_predicate.sql made leads.verified THE gate ("the rule: verified")
-- on the stated grounds that verified and approval_status "cannot drift", because
-- fn_supplier_autoapprove_clean was believed to be the only writer of either and it sets
-- approval_status='approved', verified=true and verification_status='verified' in one UPDATE.
--
-- That is not true today. FOUR paths set approval_status='approved' on production:
--   fn_supplier_autoapprove_clean         sets verified  ✓
--   supplier_api  save_profile            sets verified  ✓
--   os_ops        supplier_decide         sets verified  ✓
--   fn_leads_licence_gate_rerun (TRIGGER) sets approval_status ONLY   ✗
--
-- The trigger is the automatic recovery path: license_extract's OCR writes license_doc_path /
-- trade_license_no / license_expiry, the trigger re-runs fn_supplier_licence_gate on the same row
-- write and promotes 'action_required' -> 'approved' (and rescues an expired_auto_rejected row).
-- It leaves verified false. The result is a supplier who is approved everywhere a human looks —
-- approved in os, approved on their own portal, allowed to submit quotes, since submit_quote gates
-- on approval_status — and invisible to fn_is_matchable, match_suppliers, match_suppliers_kw and
-- fn_match_capability FOREVER. They would never receive one RFQ and nothing would report it.
--
-- Symmetric, because the badge is a claim too. The demotion branch (a licence that has expired or
-- become unreadable) left verified=true, and customer_api my_inquiries serves that field to the
-- customer as a trust badge on a quote. A supplier we can no longer evidence must not carry it.
--
-- The CHECK makes it impossible for the FIFTH writer to reintroduce this. Measured before adding:
-- 0 of 20,464 production rows have approval_status='approved', so nothing is grandfathered in.

create or replace function public.fn_leads_licence_gate_rerun()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
      -- WITHOUT THESE TWO LINES THIS PROMOTION IS COSMETIC: fn_is_matchable reads `verified`, so an
      -- approval that does not set it produces a supplier no matching path can ever return.
      new.verified            := true;
      new.verification_status := 'verified';
    elsif coalesce(new.approval_status,'') = 'rejected'
          and coalesce(new.exception_outcome,'') = 'expired_auto_rejected' then
      new.approval_status     := 'approved';
      new.licence_gate_reason := null;
      new.exception_outcome   := 'recovered_after_auto_reject';
      new.verified            := true;
      new.verification_status := 'verified';
    end if;
  elsif has_doc then
    -- Evidence exists and fails. THIS is the case worth acting on.
    if coalesce(new.approval_status,'') in ('approved','verified') then
      new.approval_status     := 'action_required';
      new.licence_gate_reason := g ->> 'reason';
      -- The evidence that earned the flag has failed, so the flag goes with it. Leaving it set
      -- keeps a trust badge on the customer's quote card for a supplier whose licence we cannot read.
      new.verified            := false;
      new.verification_status := 'unverified';
    elsif coalesce(new.approval_status,'') = 'action_required' then
      new.licence_gate_reason := g ->> 'reason';
    end if;
  end if;
  return new;
end $function$;

comment on function public.fn_leads_licence_gate_rerun() is
  'Re-runs the trade-licence gate whenever the licence columns change and moves approval_status '
  'with the evidence. It MUST move leads.verified in the same write: fn_is_matchable gates on '
  'verified, so an approval that leaves it false yields a supplier who is approved to everyone and '
  'matchable to no one. Enforced by leads_approved_implies_verified.';

alter table public.leads drop constraint if exists leads_approved_implies_verified;
alter table public.leads add constraint leads_approved_implies_verified
  check (coalesce(approval_status,'') <> 'approved' or coalesce(verified,false) = true);

-- ═══ 2. inquiry_matches.similarity IS A FRACTION, AND NOTHING SAID SO ═══════════════════════════
--
-- Both writer sites passed the literal null, so the column had never held a value and no scale was
-- ever declared. They now store a 0..1 fraction, each normalised against the maximum its OWN
-- matcher can award (fn_match_capability /100, match_suppliers_kw /23). Writing a raw 87 or a raw
-- 19 into this column would render as "8700% match" and "1900% match" on the customer's quote card,
-- and there would be nothing in the schema to catch it. NULL stays legal and means NOT SCORED —
-- the legacy AI-adjudicator path returns a binary fit/no verdict and no number exists to store.
alter table public.inquiry_matches drop constraint if exists inquiry_matches_similarity_fraction;
alter table public.inquiry_matches add constraint inquiry_matches_similarity_fraction
  check (similarity is null or (similarity >= 0 and similarity <= 1));

comment on column public.inquiry_matches.similarity is
  'How well this supplier matched this brief, as a 0..1 fraction of the maximum its matcher can '
  'award (fn_match_capability score/100, match_suppliers_kw match_score/23). NULL means the match '
  'was made on a path that computes no number - render it as absent, never as 0%.';
