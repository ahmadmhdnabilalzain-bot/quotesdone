-- A LICENCE THAT NAMES ANOTHER COMPANY IS HELD FOR THE SALES ENGINEER; IT NEVER OVERWRITES THE REGISTERED NAME.
-- Seat: sales_engineer. 2 Nov 2026, founder ledger 1467/1468, on the finding of the production document walk
-- (https://github.com/ahmadmhdnabilalzain-bot/quotesdone/actions/runs/41366031918, case t_wrong_company).
--
-- MEASURED. A licence printing "ZZ DEMO Mirage Contracting LLC" uploaded by an invited supplier registered as "ZZ DEMO
-- Sahara Technical Services LLC" replaced the registered name and was APPROVED (founder ruling 1176, 7 Oct 2026:
-- "auto fill the name from the attachment instead of rejection"). Production has never taken that branch for a real
-- supplier (agent_actions kind supplier_name_from_licence: 0 rows), so no real company was renamed.
--
-- WHY THE RULING IS NARROWED. A supplier we invited, or that registered itself, already has a name it chose; a licence
-- naming ANOTHER company is the licence-swap case (or a subsidiary / sister company registering on the parent's
-- account), and overwriting the name approves one company under another's identity. So:
--   * the registered name is BLANK            -> the licence name fills it (ruling 1176 as before), unless another
--                                                claimed supplier already holds that name (the #1275 hold);
--   * the registered name differs MATERIALLY  -> never overwritten, never approved: held 'pending' for the sales
--     (fn_company_name_norm differs)             engineer with reason licence_name_mismatch, whatever the status
--                                                (an approved supplier is held too, as #1275 already did), and the
--                                                supplier is told in English what was found and what to do;
--   * a subsidiary or sister company's own licence: the sales engineer, having compared the licence and the
--     relationship the supplier replied with, calls fn_sales_engineer_confirms_licence_name(lead, note). That records
--     agent_actions kind supplier_licence_name_confirmed keyed on the licence name, and the gate then accepts exactly
--     that licence name for that supplier (a different licence name is held again). The company name is unchanged.
--
-- Built on the live body of fn_sales_engineer_verifies_supplier (read from production 2 Nov 2026), which this REPLACES
-- WHOLE; nothing else in it moves. Companion probe: a_licence_naming_another_company_..._probe.sql (never applied).

create or replace function public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text default 'save_profile'::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_name_taken boolean := false; v_old_name text; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int; v_doc_reading boolean; v_confirmed boolean := false;
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
  -- 2 Nov 2026 (ledger 1467): a licence name the sales engineer has confirmed for THIS supplier (a subsidiary or
  -- sister company's own licence) is accepted; the company name is not touched.
  if v_name_mismatch then
    v_confirmed := exists (select 1 from public.agent_actions a
                            where a.kind = 'supplier_licence_name_confirmed' and a.target_table = 'leads' and a.target_id = l.id::text
                              and a.detail ->> 'licence_name_key' = public.fn_company_registration_name_key(l.licence_legal_name));
    if v_confirmed then v_name_mismatch := false; end if;
  end if;
  -- FOUNDER RULING 1176 (7 Oct 2026), NARROWED 2 Nov 2026 (ledger 1467): the licence name fills the company name ONLY
  -- WHEN THE REGISTERED NAME IS BLANK. A registered name that differs is never overwritten (see the header): it is held.
  -- The one exception to filling is a licence naming a company ANOTHER claimed supplier already registered: copying
  -- that name would break leads_claimed_company_name_uidx and hand one company's identity to another (#1275's hold).
  if v_name_mismatch and public.fn_company_name_norm(coalesce(l.company_name, '')) = '' then
    v_name_taken := exists (select 1 from public.leads o where o.id <> l.id and o.claimed
                              and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(l.licence_legal_name));
    if not v_name_taken then
      v_old_name := l.company_name;
      update public.leads set company_name = btrim(l.licence_legal_name) where id = l.id;
      l.company_name := btrim(l.licence_legal_name);
      v_name_mismatch := false;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'supplier_name_from_licence', 'auto_done', 'low',
              'Company name filled from the trade licence — ' || left(l.company_name, 120),
              'No action required. The registered name was blank; the name the trade licence prints is now the company name (founder ruling 1176, for a blank name only).',
              jsonb_build_object('supplier_id', l.id, 'previous_name', v_old_name, 'new_name', l.company_name,
                                 'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path, 'source', p_source),
              'leads', l.id::text);
      if coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' then
        perform public.fn_sales_engineer_writes('company_name_from_licence', 'supplier', coalesce(nullif(btrim(l.claimed_by), ''), l.email), l.id, null, null, null,
          'Your company name was updated to match your trade licence',
          'Your company name was blank. Your trade licence prints "' || l.company_name || '", so your company name on QuotesDone is now "' || l.company_name
            || '". This is the name customers, quotes and documents show. If this is not right, reply to this email or upload the correct trade licence.',
          null, null, '{}'::text[], 'company_name_from_licence:' || l.id || ':' || md5(l.company_name));
      end if;
    end if;
  end if;
  -- A licence naming another company than the registered one: the supplier is told once per pair of names, in English.
  if v_name_mismatch and public.fn_company_name_norm(coalesce(l.company_name, '')) <> ''
     and coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' then
    perform public.fn_sales_engineer_writes('licence_names_another_company', 'supplier', coalesce(nullif(btrim(l.claimed_by), ''), l.email), l.id, null, null, null,
      'Your trade licence names a different company',
      'The trade licence you uploaded is issued to "' || btrim(l.licence_legal_name) || '", but your registration is for "' || coalesce(l.company_name, '')
        || '". We have not changed your company name, and your registration is on hold while our sales engineer checks it. '
        || 'If "' || btrim(l.licence_legal_name) || '" is a subsidiary or sister company you are registering, reply to this email and say how it relates to "' || coalesce(l.company_name, '')
        || '". Otherwise upload the trade licence issued to "' || coalesce(l.company_name, '') || '".',
      null, null, '{}'::text[], 'licence_names_another_company:' || l.id || ':' || md5(public.fn_company_name_norm(l.licence_legal_name) || '|' || public.fn_company_name_norm(l.company_name)));
  end if;
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '';
  -- 7 Oct 2026 (#1285): a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  -- 13 Oct 2026 (review of #1404): a profile or catalogue still being read ('reading', marked before its parse) holds
  -- approval: the gate never approves past a document whose read has not finished (or was killed mid-parse).
  v_doc_reading := exists (select 1 from public.supplier_capabilities c, jsonb_array_elements(coalesce(c.source_docs -> 'docs', '[]'::jsonb)) e
                            where c.supplier_id = l.id and e ->> 'status' = 'reading');
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread
     and not v_name_mismatch and not v_expiry_unread and not v_number_unread then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  -- 2 Nov 2026 (ledger 1467): a licence naming another company is held for the sales engineer whatever the status
  -- (this was only for an approved supplier; a not-yet-approved one was action_required, or had its name overwritten).
  elsif cardinality(v_missing) = 0 and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
  -- 7 Oct 2026 (#1285): an unread expiry or licence number is held, never approved on the name alone - also for
  -- an APPROVED supplier whose new licence (licence_changed) could not be dated or numbered.
  elsif v_expiry_unread then v_decision := 'pending'; v_reason := 'licence_expiry_unread';
  elsif v_number_unread then v_decision := 'pending'; v_reason := 'licence_number_unread';
  elsif v_doc_reading then v_decision := 'pending'; v_reason := 'documents_being_read';
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
  values ('sales_engineer', 'supplier_verification', case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread', 'documents_being_read') or (v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_name_mismatch', 'licence_expiry_unread', 'licence_number_unread') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then case when v_reason = 'documents_being_read'
              then 'Held: a company profile or catalogue of this supplier is still being read. The gate is run again when the read finishes; a read still unfinished after 30 minutes is marked unreadable and handed to you (document_read_stuck).'
              when v_reason = 'licence_name_mismatch'
              then 'Review: the trade licence names a company other than the registered name, which was NOT changed. Matching is held and the supplier has been told in English. Compare the licence with the registered name. A subsidiary or sister company with its own licence: call fn_sales_engineer_confirms_licence_name(lead, note). Otherwise ask for the right licence.'
              when v_reason in ('licence_expiry_unread', 'licence_number_unread')
              then 'Review: complete, but the ' || case v_reason when 'licence_expiry_unread' then 'expiry date' else 'licence number' end || ' on the trade licence could not be read. Read it on the licence, record it, then approve or ask for a clearer copy. It is never approved automatically on the name alone.'
              when v_reason = 'licence_unreadable'
              then 'Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
              else 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.' end
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread, 'licence_name_confirmed', v_confirmed,
                             'licence_expiry_unread', v_expiry_unread, 'licence_number_unread', v_number_unread,
                             'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$;

-- The sales engineer's one door for a subsidiary or sister company that registers on its own licence. It records
-- WHICH licence name was accepted for WHICH supplier, then runs the gate again. The company name is never changed.
create or replace function public.fn_sales_engineer_confirms_licence_name(p_lead_id bigint, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare l public.leads;
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;
  if public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'licence_name_unread');
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('ok', false, 'error', 'note_required'); end if;
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_licence_name_confirmed', 'auto_done', 'low',
          'Licence name accepted for ' || left(coalesce(l.company_name, 'supplier #' || l.id), 100) || ': ' || left(l.licence_legal_name, 100),
          'The sales engineer compared the licence with the registered company and accepted this licence name for this supplier. The company name is unchanged. A different licence name is held again.',
          jsonb_build_object('supplier_id', l.id, 'registered_name', l.company_name, 'licence_legal_name', l.licence_legal_name,
                             'licence_name_key', public.fn_company_registration_name_key(l.licence_legal_name), 'note', left(p_note, 500)),
          'leads', l.id::text);
  return public.fn_sales_engineer_verifies_supplier(p_lead_id, 'licence_name_confirmed');
end $function$;

revoke all on function public.fn_sales_engineer_confirms_licence_name(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_confirms_licence_name(bigint, text) to service_role;
