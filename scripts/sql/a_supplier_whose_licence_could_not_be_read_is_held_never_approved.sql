-- Assigned: sales_engineer
-- A SUPPLIER WHOSE LICENCE COULD NOT BE READ IS HELD, NEVER APPROVED (7 Oct 2026).
-- Stage-2 sandbox run (#1230), S02: a supplier whose trade licence was never read (extraction stubbed,
-- failed, or unreadable - leads.licence_legal_name empty) stayed 'approved' with licence_gate_reason
-- null, because the "already approved and the six are complete" branch came BEFORE the unread-name
-- check. Now an approval stands only while the licence name has been read; otherwise the supplier is
-- held at 'pending' with reason 'licence_unreadable' (renamed from licence_name_unread, which was only
-- reached for suppliers not yet approved) and the verification row needs review.
-- CREATE OR REPLACE keeps the existing ACL (revoked in the_mandatory_six_have_one_definition_...).
-- Probe: scripts/sql/a_supplier_whose_licence_could_not_be_read_is_held_never_approved_probe.sql
-- Prevented by: scripts/checks/an_unread_licence_name_is_never_approved_automatically.test.mjs

update public.leads set licence_gate_reason = 'licence_unreadable' where licence_gate_reason = 'licence_name_unread';

create or replace function public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
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
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
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
  values ('sales_engineer', 'supplier_verification', case when v_reason = 'licence_unreadable' then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason = 'licence_unreadable' then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then case when v_reason = 'licence_unreadable'
              then 'Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
              else 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.' end
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                             'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$
;
