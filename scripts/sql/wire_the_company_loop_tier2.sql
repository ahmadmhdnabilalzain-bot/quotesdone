-- Wire the live company loop — Tier 2: emit the missing trigger events at their real producers, so the
-- workflows that could never auto-start now do. Producers verified against the live catalog (2026-09-02).
-- The generic emit helper is public.fn_emit(p_event_type, p_entity_type, p_entity_id, p_actor, p_payload).
--
--   CHAIN-01  a refund REQUEST (a refunds row with status='requested') now opens the founder-gated
--             `refund` workflow. Record-only and money-SAFE: it starts the review record; the existing
--             z00_refund_founder_decision_only / z05_refund_execution_requires_decision triggers still
--             block any execution without a founder decision. Externally-issued Stripe refunds (which
--             carry a stripe_refund_id and land as 'succeeded') are excluded — a fact is not a request.
--   CHAIN-02  the deterministic supplier-suspension signal (an APPROVED supplier whose trade licence has
--             expired) now emits supplier.suspension_proposed to open the `supplier_suspension` review.
--             Scoped to approval_status='approved' (never the ~15k scraped leads) and idempotent per
--             lead/episode; 0 suppliers qualify today. The judgement signals (fraud, repeated
--             non-response, trust finding) stay agent calls to fn_emit at their decision points.
--   SINK-04   campaign.launched (a paid Meta ad going live) now reaches marketing_analyst, mirroring
--             campaign.published. Distinct signal (external paid ad vs internal content), was orphaned.
--
-- Not wired here (correctly): TRIG-03 lead.qualified and TRIG-04 contract.submitted are genuinely
-- external — no sales-lead or contract intake surface exists yet; they fire on real inbound traffic.
-- TRIG-05 invoice.received is already wired (trg_emit_invoice_received on ap_bills), latent only.
--
--   node scripts/apply_sql.mjs scripts/sql/wire_the_company_loop_tier2.sql --apply --ddl

begin;

-- CHAIN-01 — a customer refund request opens the founder-gated refund workflow.
create or replace function public.fn_emit_refund_requested()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
begin
  -- Only a genuine NEW customer request: status 'requested' and no Stripe refund id (an externally
  -- issued refund is a recorded fact, not a request, and must not enter the approval workflow).
  if new.status = 'requested' and new.stripe_refund_id is null then
    perform public.fn_emit('refund.requested', 'refund', new.id::text,
      coalesce(new.requested_by, 'system'),
      jsonb_build_object('refund_id', new.id, 'inquiry_id', new.inquiry_id,
        'customer_id', new.customer_id, 'supplier_lead_id', new.supplier_lead_id,
        'amount_fils', new.amount_fils, 'reason_code', new.reason_code));
  end if;
  return new;
end $function$;
revoke execute on function public.fn_emit_refund_requested() from public;

drop trigger if exists trg_emit_refund_requested on public.refunds;
create trigger trg_emit_refund_requested
  after insert on public.refunds
  for each row execute function public.fn_emit_refund_requested();

-- CHAIN-02 — deterministic suspension signal: an approved supplier with an expired trade licence.
-- ROUTINE REMOVED 7 September 2026. public.fn_emit_supplier_suspension_proposed was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_emit_supplier_suspension_proposed(int) from public;

-- SINK-04 — give the orphaned paid-ad-launch signal a consumer.
insert into public.event_subscription (agent_key, event_type, reason, active)
values ('marketing_analyst', 'campaign.launched',
        'Collects paid-ad launch attribution against company goals', true)
on conflict (agent_key, event_type) do update set active = true, reason = excluded.reason;

commit;
