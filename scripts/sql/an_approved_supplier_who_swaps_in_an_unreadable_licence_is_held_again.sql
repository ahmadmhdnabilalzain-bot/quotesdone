-- Assigned: sales_engineer
--
-- AN APPROVED SUPPLIER WHO SWAPS IN AN UNREADABLE LICENCE IS HELD AGAIN (7 Oct 2026).
--
-- #1268 made fn_sales_engineer_verifies_supplier hold an approved supplier whose licence name was not
-- read ('pending', reason licence_unreadable). Measured on production the same day, in a rolled-back
-- probe on ZZ DEMO supplier 126512: name read -> approved; then the exact write supplier_api
-- process_docs makes for a new licence code cannot name (license_doc_path set, licence_legal_name
-- null) -> STILL approved, reason null, verified true; calling the verification by hand afterwards ->
-- pending/licence_unreadable. The routine was right; nothing called it. z20 re-runs the verification
-- only WHEN the supplier is waiting (action_required / pending), so for an approved supplier a new
-- licence document never reached the review at all. #1268's own probe called the routine directly,
-- so it measured the case the fix handled, not the path a real upload takes.
--
-- The fix is in the one place every writer routes through: z20 also fires for an APPROVED supplier
-- when the licence document or the licence name changes. That covers supplier_api process_docs,
-- supplier_portal save_documents, resend_inbound and wa_inbound alike. Nothing else changes for an
-- approved supplier: a phone, profile or terms change still does not re-review him (the six gate,
-- trg_leads_e0_mandatory_six_gate, already demotes a supplier who loses a mandatory item), and an
-- approved supplier whose licence merely expired stays approved, as before.
--
-- 7 Oct 2026, the same day (coordinator decision): a licence change on an APPROVED supplier also asks the
-- name question. A new READABLE licence that names another company holds him as pending, reason
-- licence_name_mismatch, needs_review for the sales engineer. z20 tells the routine which case it is by
-- p_source = 'licence_changed' (only when he was approved and the licence document or name changed);
-- save_profile and every other source keep the approved branch exactly as before, so an ordinary profile
-- save never re-gates an approved supplier.
--
-- Both routines are CREATE OR REPLACE (ACL preserved, so no revoke; signatures unchanged, search_path pinned). pg_trigger_depth() < 1 stays: the
-- verification's own update never re-enters.
--
-- Prevented by: an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again_probe.sql (writes
-- the column change only, never calls the routine) and the trigger assertion in
-- scripts/checks/an_unread_licence_name_is_never_approved_automatically.test.mjs.

create or replace function public.fn_leads_mandatory_item_landed_reverifies()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.fn_sales_engineer_verifies_supplier(new.id,
    case when old.approval_status = 'approved'
              and (old.license_doc_path is distinct from new.license_doc_path
                   or old.licence_legal_name is distinct from new.licence_legal_name)
         then 'licence_changed' else 'mandatory_item_changed' end);
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
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

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread
     and not (p_source = 'licence_changed' and v_name_mismatch) then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  -- 7 Oct 2026: an APPROVED supplier whose new licence names another company is held for review, never
  -- approved and never told "action required" by code alone. Only a licence change asks this (z20 passes
  -- 'licence_changed'); an ordinary profile save leaves an approved supplier approved, as before.
  elsif p_source = 'licence_changed' and coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0
        and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';
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
  if v_changed > 0 or p_source not in ('mandatory_item_changed', 'licence_changed') then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', case when v_reason = 'licence_unreadable' or (v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_name_mismatch') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then case when v_reason = 'licence_name_mismatch'
              then 'Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name. Matching is held. Compare the licence with the registered name, then re-approve or ask for the right licence.'
              when v_reason = 'licence_unreadable'
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
end $function$;

drop trigger if exists z20_leads_mandatory_item_landed_reverifies on public.leads;
create trigger z20_leads_mandatory_item_landed_reverifies
  after update of company_name, phone, phone_e164, owner_phone_verified, owner_email_verified, license_doc_path,
                  license_expiry, company_profile_doc_path, signed_terms_path, licence_legal_name
  on public.leads for each row
  when (pg_trigger_depth() < 1
        and (new.approval_status = any (array['action_required', 'pending'])
             or (new.approval_status = 'approved'
                 and (old.license_doc_path is distinct from new.license_doc_path
                      or old.licence_legal_name is distinct from new.licence_legal_name))))
  execute function public.fn_leads_mandatory_item_landed_reverifies();
