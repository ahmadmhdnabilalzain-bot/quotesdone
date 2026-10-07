-- Assigned: sales_engineer
-- A LICENCE WHOSE EXPIRY OR NUMBER COULD NOT BE READ IS HELD, AND A WRONG NAME UN-APPROVES (7 Oct 2026).
-- Founder gate, ledger 1162: "not a single mistake in any trade licence shared by a supplier". Measured by the
-- document intake accuracy suite (scripts/e2e/document_intake_accuracy.mjs) on 50 synthetic licences, with
-- pricing_config.auto_approve_suppliers = true:
--   * the gate approved on the NAME alone. A licence whose name was read but whose expiry was not (a scan the model
--     named but could not date) was approved with license_expiry null - "not known to be expired" - so an expired
--     licence whose date could not be read would be approved. "Any unreadable field HELD, never guessed": a licence
--     on file with no expiry read is now held at 'pending' with reason licence_expiry_unread, and with no licence
--     number read, licence_number_unread; the verification row needs review, as licence_unreadable does.
--   * an APPROVED supplier who replaced the licence with one printing ANOTHER company's name stayed approved: the
--     approved branch came before the mismatch reason. A mismatch now takes the approval away (action_required,
--     licence_name_mismatch). Measured on production 7 Oct 2026: 3 approved suppliers, 0 with a mismatch, 0 with an
--     unread expiry or number, so no current approval changes. An expired licence on an approved supplier still
--     stays approved (fn_reconcile_doc_blocks pauses its matching), as before.
-- NOT changed: the six, the rule for an expiry that WAS read, and the order of the reasons (missing, mismatch,
-- expired, then the unread holds). CREATE OR REPLACE keeps the existing ACL (revoked in
-- the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql).
-- Prevented by: scripts/checks/an_unread_licence_field_is_held_never_approved.test.mjs, and the suite's gate probe,
-- which measures this file inside a rolled-back transaction before it is applied (--gate-sql).

create or replace function public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
begin
  select * into l from public.leads where id = p_lead_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;
  -- A registration closed for being incomplete (fn_sales_engineer_supplier_documents_tick) is re-opened
  -- by the supplier saving again: the closing notice tells them they may. Any other rejection stands.
  if coalesce(l.banned, false)
     or (coalesce(l.approval_status, '') = 'rejected'
         and not (p_source = 'save_profile' and coalesce(l.rejection_reason, '') like 'registration incomplete after %')) then
    return jsonb_build_object('ok', true, 'decision', 'unchanged', 'approval_status', l.approval_status);
  end if;

  v_missing := public.fn_supplier_mandatory_six(l);
  -- "Not known to be expired": license_extract leaves the expiry null when the licence prints none, and
  -- blocking on that would refuse suppliers whose licence genuinely has no date (29 Jul 2026 note).
  v_expired := l.license_expiry is not null and l.license_expiry < current_date;
  -- 24 Sep 2026: the licence must be this company's. Unread name = not a mismatch (nothing guessed).
  v_name_mismatch := public.fn_supplier_licence_name_mismatch(l);
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '';
  -- 7 Oct 2026: a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread and not v_name_mismatch then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
  elsif v_expiry_unread then v_decision := 'pending'; v_reason := 'licence_expiry_unread';
  elsif v_number_unread then v_decision := 'pending'; v_reason := 'licence_number_unread';
  elsif coalesce(v_auto, false) then v_decision := 'approved';
  else v_decision := 'pending';
  end if;

  update public.leads
     set approval_status = v_decision,
         verified = (v_decision = 'approved'),
         approved_at = case when v_decision = 'approved' then coalesce(approved_at, now()) else approved_at end,
         approval_decided_by = 'sales_engineer',
         licence_gate_reason = v_reason
   where id = p_lead_id
     and (approval_status is distinct from v_decision or verified is distinct from (v_decision = 'approved')
          or licence_gate_reason is distinct from v_reason);
  get diagnostics v_changed = row_count;

  -- Every decision is recorded; a re-run by the trigger that changed nothing is not a decision.
  if v_changed > 0 or p_source <> 'mandatory_item_changed' then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread')
              then 'Review: complete, but the ' || case v_reason when 'licence_expiry_unread' then 'expiry date' when 'licence_number_unread' then 'licence number' else 'company name' end || ' on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
              else 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.' end
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                             'licence_expiry_unread', v_expiry_unread, 'licence_number_unread', v_number_unread,
                             'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$
;
