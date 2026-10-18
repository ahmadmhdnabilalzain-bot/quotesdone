-- Assigned: sales_engineer
-- A LICENCE NAME BECOMES THE COMPANY NAME, AND A FIELD NOBODY COULD READ IS HELD (7 Oct 2026, #1285).
-- BUILT ON #1275 (an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again.sql), which applies first:
-- its log guard (a re-run that changed nothing is not logged for 'mandatory_item_changed' and 'licence_changed'),
-- its re-gate of an approved supplier who swaps licences, and its z20 trigger stand unchanged.
--
-- FOUNDER RULING 1176: "auto fill the name from the attachment instead of rejection". A licence name that was READ
-- (by code, or by the model under licenceNameFromModel's confidence rule - leads.licence_legal_name is only ever
-- written so) and differs from the registered name becomes leads.company_name. The previous name is kept in an
-- agent_actions row (kind supplier_name_from_licence, detail.previous_name), the supplier is told in English through
-- fn_sales_engineer_writes, and the gate continues as for a matching name: no hold, no review. This applies to an
-- approved supplier who swaps licences too: he gets the new name. ONE exception: a licence printing the name another
-- CLAIMED supplier registered stays #1275's licence_name_mismatch hold (pending, needs_review) - copying it would
-- break leads_claimed_company_name_uidx and give one company another's identity.
-- Every surface reads the company name from leads.company_name (measured 7 Oct 2026: no other table stores a copy of
-- it in the schema mirror), so the portal, quotes, PDFs and search show the new name from the next read.
--
-- FOUNDER RULING 1177 + LEDGER 1162: every licence is read in full (code, then the vision model); a field still
-- unread after both is HELD, never guessed: name -> licence_unreadable (as before), expiry -> licence_expiry_unread,
-- number -> licence_number_unread; pending, needs_review, medium, and the supplier is asked for a clearer copy
-- (serverCopy.ts); a new upload is read again and re-runs this gate. The approved branch asks all three, so an
-- approved supplier's new licence that could not be dated or numbered is held too. Measured on production 7 Oct 2026:
-- 3 approved suppliers, 0 with a mismatch and 0 with an unread expiry or number - no current approval changes.
-- Measured on 50 synthetic licences by scripts/e2e/document_intake_accuracy.mjs (--gate-sql, inside a rolled-back
-- transaction): before, the gate approved on the name alone.
-- NOT changed: the six, the rule for an expiry that WAS read. CREATE OR REPLACE keeps the existing ACL (revoked in
-- the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql).
-- Prevented by: scripts/checks/an_unread_licence_field_is_held_never_approved.test.mjs and the suite's gate probe.

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_name_taken boolean := false; v_old_name text; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
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
  -- FOUNDER RULING 1176 (7 Oct 2026): "auto fill the name from the attachment instead of rejection". A licence name
  -- that was READ (code, or the model under its confidence rule - licence_legal_name is only ever written so) and
  -- differs from the registered name becomes the company name: the old name is kept in agent_actions, the supplier
  -- is told in English, and the gate goes on as for a matching name. Not a hold, not a review.
  -- The one exception is a licence naming a company ANOTHER claimed supplier already registered: copying that name
  -- would break leads_claimed_company_name_uidx and hand one company's identity to another, so it stays the
  -- licence_name_mismatch hold of #1275 for a person to look at.
  if v_name_mismatch then
    v_name_taken := exists (select 1 from public.leads o where o.id <> l.id and o.claimed
                              and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(l.licence_legal_name));
    if not v_name_taken then
      v_old_name := l.company_name;
      update public.leads set company_name = btrim(l.licence_legal_name) where id = l.id;
      l.company_name := btrim(l.licence_legal_name);
      v_name_mismatch := false;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'supplier_name_from_licence', 'auto_done', 'low',
              'Company name updated from the trade licence — ' || left(l.company_name, 120),
              'No action required. The registered name did not match the name the trade licence prints; the licence name now is the company name (founder ruling 1176). The previous name is in detail.previous_name.',
              jsonb_build_object('supplier_id', l.id, 'previous_name', v_old_name, 'new_name', l.company_name,
                                 'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path, 'source', p_source),
              'leads', l.id::text);
      if coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' then
        perform public.fn_sales_engineer_writes('company_name_from_licence', 'supplier', coalesce(nullif(btrim(l.claimed_by), ''), l.email), l.id, null, null, null,
          'Your company name was updated to match your trade licence',
          'Your registered company name was "' || coalesce(v_old_name, '') || '". Your trade licence prints "' || l.company_name
            || '", so your company name on QuotesDone is now "' || l.company_name || '". This is the name customers, quotes and documents show. '
            || 'If this is not right, reply to this email or upload the correct trade licence.',
          null, null, '{}'::text[], 'company_name_from_licence:' || l.id || ':' || md5(l.company_name));
      end if;
    end if;
  end if;
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '';
  -- 7 Oct 2026 (#1285): a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread
     and not v_name_mismatch and not v_expiry_unread and not v_number_unread then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  -- 7 Oct 2026 (review of #1275): an APPROVED supplier whose licence names another company is held for
  -- review, whatever asked - a licence change or a save. The approved branch above used to keep him approved
  -- and log "the licence name matches", which was false. A supplier whose name matches is untouched by a save.
  elsif coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0
        and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
  -- 7 Oct 2026 (#1285): an unread expiry or licence number is held, never approved on the name alone - also for
  -- an APPROVED supplier whose new licence (licence_changed) could not be dated or numbered.
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
  if v_changed > 0 or p_source not in ('mandatory_item_changed', 'licence_changed') then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread') or (v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_name_mismatch', 'licence_expiry_unread', 'licence_number_unread') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then case when v_reason = 'licence_name_mismatch'
              then 'Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name. Matching is held. Compare the licence with the registered name, then re-approve or ask for the right licence.'
              when v_reason in ('licence_expiry_unread', 'licence_number_unread')
              then 'Review: complete, but the ' || case v_reason when 'licence_expiry_unread' then 'expiry date' else 'licence number' end || ' on the trade licence could not be read. Read it on the licence, record it, then approve or ask for a clearer copy. It is never approved automatically on the name alone.'
              when v_reason = 'licence_unreadable'
              then 'Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
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
end $function$;
