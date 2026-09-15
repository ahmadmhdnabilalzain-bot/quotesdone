-- THE MANDATORY SIX HAVE ONE DEFINITION, THE DATABASE HOLDS IT, AND THE SALES ENGINEER VERIFIES.
--
-- Assigned: sales_engineer. Founder: "A supplier whose mandatory fields are incomplete cannot be
-- verified by the sales engineer." The six are company name, mobile (verified), e-mail (verified),
-- trade licence (a DOCUMENT), company profile (a document) and the signed terms. The rest are extra.
--
-- MEASURED 15 SEP 2026 (origin/main 05eefcb, production read-only):
--   * Two live definitions disagreed. supplier_api save_profile (_shared/supplier_registration.ts)
--     accepted the licence NUMBER without a document and ticked the terms on accepted_terms_at;
--     fn_supplier_mandatory_check (WhatsApp / support) required a +9715 phone_e164 but not a verified
--     mobile, read leads.email_verified (text, null on every claimed row) instead of the owner's
--     verified e-mail, and ticked the licence on a path whether or not storage held the file.
--   * Nothing in the database refused an approval. fn_supplier_licence_gate and its re-run trigger were
--     dropped on 7 Sep (scripts/sql/DROPPED.txt lines 317-318); approval was a line of TypeScript.
--   * At 06:30 UTC a rehearsal held 3 claimed ZZ DEMO suppliers (124775-124777), approved and verified
--     with company_profile_doc_path NULL: approved without one of the six. By the time this file was
--     finished the rehearsal had torn them down, and 0 leads were claimed or carried any approval_status.
--     A rehearsal that seeds an approved supplier without a company profile is now refused by the gate.
--   * 22,264 unclaimed listings: approval_status null, verified false. Untouched by everything here.
--
-- WHAT THIS FILE BUILDS
--   1. fn_supplier_mandatory_six(leads) -> the missing codes, in the founder's order. The codes are the
--      portal's (reg_name .. reg_terms, EN+AR copy in src/components/portal/supplier/serverCopy.ts).
--      The TypeScript reads this through fn_supplier_mandatory_six_for; it no longer decides.
--   2. fn_supplier_mandatory_check (the WhatsApp/support answer) now reads the same six.
--   3. trg_leads_e0_mandatory_six_gate: approval or verified=true is REFUSED while anything is missing;
--      an already-approved supplier who loses an item is DEMOTED to action_required (the exception
--      invariant, which fires after this by name, opens the 14-day window).
--   4. fn_sales_engineer_verifies_supplier(lead): the six plus "licence not known to be expired", then
--      approved+verified (pricing_config.auto_approve_suppliers on), pending (off: the sales engineer's
--      queue), or action_required with the first reason. Every decision is an agent_actions row
--      (agent sales_engineer, kind supplier_verification).
--   5. z20_leads_mandatory_item_landed_reverifies: when a mandatory column changes on a supplier who is
--      waiting (action_required / pending), the verification runs again, whatever wrote the column —
--      supplier_api process_docs, supplier_portal save_documents, compliance_archive's certificate, the
--      e-mailed licence. Documents-tab uploads used to leave such a supplier stuck.
--   6. z21_sign_supplier_on_acceptance: accepting the terms asks compliance_archive for the signed
--      certificate (the same qd_sign_supplier call made on e-mail verification). Before this only kyc's
--      accept_terms produced signed_terms_path, so a supplier who accepted in save_profile alone could
--      never have the signed-terms item.
--
-- WHAT IT DOES NOT CHANGE: the 14-day rejection sweep and the daily document reconcile are
-- the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql; approval_status in
-- matching is a_supplier_is_matchable_only_once_approved.sql. The mobile item keeps the founder's
-- "UAE mobile" (+9715, 7 Sep) AND requires the OTP verification.
--
--   node scripts/apply_sql.mjs scripts/sql/the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql --apply --ddl

-- ── 1. THE SIX ───────────────────────────────────────────────────────────────────────────────────
-- A document is present only when storage holds it: a path naming nothing is how three seed rows ended
-- up 'abandoned: source object is not in storage' (_shared/stored_at.ts). storage.objects is unique on
-- (bucket_id, name), so each lookup is one index probe.
create or replace function public.fn_supplier_mandatory_six(p public.leads)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select array_remove(array[
    case when coalesce(btrim(p.company_name), '') = '' then 'reg_name' end,
    case when not (coalesce(p.owner_phone_verified, false)
                   and regexp_replace(coalesce(nullif(btrim(p.phone), ''), p.phone_e164, ''), '[^0-9]', '', 'g') ~ '^9715[0-9]{8}$')
         then 'reg_mobile' end,
    case when not coalesce(p.owner_email_verified, false) then 'reg_email' end,
    case when not exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.license_doc_path)
         then 'reg_licence' end,
    case when not exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.company_profile_doc_path)
         then 'reg_profile' end,
    case when coalesce(btrim(p.signed_terms_path), '') = '' then 'reg_terms' end
  ], null)
$fn$;

create or replace function public.fn_supplier_mandatory_six_for(p_lead_id bigint)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_supplier_mandatory_six(l) from public.leads l where l.id = p_lead_id
$fn$;

revoke execute on function public.fn_supplier_mandatory_six(public.leads) from public, anon, authenticated;
revoke execute on function public.fn_supplier_mandatory_six_for(bigint) from public, anon, authenticated;
comment on function public.fn_supplier_mandatory_six(public.leads) is
  'The founder''s six for a supplier, as missing codes (reg_name, reg_mobile, reg_email, reg_licence, reg_profile, reg_terms). The one definition: supplier_api, supplier_portal, the gate trigger and fn_supplier_mandatory_check all read it.';

-- ── 2. THE WHATSAPP / SUPPORT ANSWER READS THE SAME SIX ───────────────────────────────────────────
-- Moved here from the_mandatory_set_is_different_for_a_customer_than_for_a_supplier.sql (which keeps
-- the customer four). Same jsonb shape, plus missing_codes.
create or replace function public.fn_supplier_mandatory_check(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare l public.leads; v_miss text[]; v_label jsonb := jsonb_build_object(
  'reg_name', 'Company name', 'reg_mobile', 'Verified UAE mobile number', 'reg_email', 'Verified email address',
  'reg_licence', 'Trade licence', 'reg_profile', 'Company profile', 'reg_terms', 'Signed terms and conditions');
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'No such lead.'); end if;
  v_miss := public.fn_supplier_mandatory_six(l);
  return jsonb_build_object(
    'ok', true, 'party_kind', 'supplier', 'id', p_lead_id, 'name', l.company_name,
    'complete', cardinality(v_miss) = 0,
    'have', (select coalesce(jsonb_agg(v_label->>k order by o), '[]') from unnest(array['reg_name','reg_mobile','reg_email','reg_licence','reg_profile','reg_terms']) with ordinality u(k, o) where not (k = any (v_miss))),
    'missing', (select coalesce(jsonb_agg(v_label->>k order by o), '[]') from unnest(v_miss) with ordinality u(k, o)),
    'missing_codes', to_jsonb(v_miss),
    'missing_count', cardinality(v_miss),
    'mandatory_total', 6);
end $fn$;
-- CREATE OR REPLACE of an existing routine keeps its ACL (revoked from public on 7 Sep); restated so a
-- fresh database built from this file is closed too.
revoke execute on function public.fn_supplier_mandatory_check(bigint) from public, anon, authenticated;

-- public.mandatory_field_policy (the prose register created by the file this routine moved from) is not
-- on production: to_regclass returned null on 15 Sep 2026. The routine above is the rule; nothing
-- here recreates the table.

-- ── 3. THE GATE ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_leads_mandatory_six_gate()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_missing text[] := public.fn_supplier_mandatory_six(new);
begin
  if cardinality(v_missing) = 0 then return new; end if;
  if tg_op = 'UPDATE' and (coalesce(old.approval_status, '') = 'approved' or coalesce(old.verified, false)) then
    -- Already approved and an item is gone (or was never there: nothing re-checked approvals before).
    new.approval_status := 'action_required';
    new.verified := false;
    new.licence_gate_reason := v_missing[1];
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_verification', 'auto_done', 'medium',
            'Supplier demoted to action_required (' || array_to_string(v_missing, ', ') || ') — ' || left(coalesce(new.company_name, 'supplier #' || new.id), 120),
            'No action required. A mandatory item is missing from an approved supplier, so the approval was withdrawn and the 14-day window opened. The supplier is approved again automatically when the item is back.',
            jsonb_build_object('supplier_id', new.id, 'decision', 'demoted', 'missing', v_missing, 'source', 'trg_leads_e0_mandatory_six_gate'),
            'leads', new.id::text);
    return new;
  end if;
  raise exception 'leads %: a supplier whose mandatory fields are incomplete cannot be verified (missing: %)',
    new.id, array_to_string(v_missing, ', ') using errcode = 'check_violation';
end $fn$;
revoke execute on function public.fn_leads_mandatory_six_gate() from public, anon, authenticated;

-- BEFORE triggers fire in name order: after trg_leads_derive_owner_email_verified (it may set the
-- e-mail item) and before trg_leads_exception_invariant (it opens the window on action_required).
drop trigger if exists trg_leads_e0_mandatory_six_gate on public.leads;
create trigger trg_leads_e0_mandatory_six_gate
  before insert or update on public.leads
  for each row when (new.approval_status = 'approved' or new.verified)
  execute function public.fn_leads_mandatory_six_gate();

-- ── 4. THE SALES ENGINEER VERIFIES ───────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text default 'save_profile')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare l public.leads; v_missing text[]; v_expired boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
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
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1] when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  elsif v_reason is not null then v_decision := 'action_required';
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
  values ('sales_engineer', 'supplier_verification', 'auto_done',
          case when v_decision = 'action_required' then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present and the licence is not known to be expired.'
            when 'pending' then 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.'
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'reason', v_reason, 'auto_approve', v_auto);
end $fn$;
revoke execute on function public.fn_sales_engineer_verifies_supplier(bigint, text) from public, anon, authenticated;

-- ── 5. A MANDATORY ITEM LANDING RE-RUNS THE VERIFICATION ─────────────────────────────────────────
create or replace function public.fn_leads_mandatory_item_landed_reverifies()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_sales_engineer_verifies_supplier(new.id, 'mandatory_item_changed');
  return null;
end $fn$;
revoke execute on function public.fn_leads_mandatory_item_landed_reverifies() from public, anon, authenticated;

-- pg_trigger_depth() < 1: the verification's own update (depth 1) never re-enters.
drop trigger if exists z20_leads_mandatory_item_landed_reverifies on public.leads;
create trigger z20_leads_mandatory_item_landed_reverifies
  after update of company_name, phone, phone_e164, owner_phone_verified, owner_email_verified,
                  license_doc_path, license_expiry, company_profile_doc_path, signed_terms_path
  on public.leads
  for each row when (new.approval_status in ('action_required', 'pending') and pg_trigger_depth() < 1)
  execute function public.fn_leads_mandatory_item_landed_reverifies();

-- ── 6. ACCEPTING THE TERMS PRODUCES THE SIGNED CERTIFICATE ───────────────────────────────────────
-- qd_sign_supplier posts compliance_archive 'sign' with the db.internal credential (scoped to
-- compliance_archive; fn.supplier_api's is not, measured 15 Sep). compliance_archive refuses without an
-- acceptance on record, which this trigger's condition guarantees.
drop trigger if exists z21_sign_supplier_on_acceptance on public.leads;
create trigger z21_sign_supplier_on_acceptance
  after update of accepted_terms_at on public.leads
  for each row when (new.accepted_terms_at is not null and new.accepted_terms_at is distinct from old.accepted_terms_at
                     and new.claimed_by is not null
                     -- trg_sign_supplier already posts for this row when the same statement verifies the e-mail
                     and not (new.owner_email_verified is true and old.owner_email_verified is distinct from new.owner_email_verified
                              and new.signed_terms_url is null))
  execute function public.qd_sign_supplier();

-- ── PROBE ────────────────────────────────────────────────────────────────────────────────────────
-- A ZZ DEMO row with no claimed_by (so no sign trigger, no disposable-e-mail check), documents pointed
-- at two objects storage already holds (nothing is written to storage), every write inside a block
-- that is rolled back by its own raise. Real rows: the count of leads and of approved leads must not
-- move. This file carries DDL, so it ends in a notice.
do $probe$
declare
  v_id bigint; v_lic text; v_prof text; v_leads_before bigint; v_appr_before bigint;
  r_six text[]; r_refused boolean := false; r_first jsonb; r_after_docs text; r_after_clear text; r_reason text; r_actions int;
begin
  select count(*), count(*) filter (where approval_status = 'approved') into v_leads_before, v_appr_before from public.leads;
  select name into v_lic from storage.objects where bucket_id = 'supplier-docs' order by name limit 1;
  select name into v_prof from storage.objects where bucket_id = 'supplier-docs' and name <> v_lic order by name limit 1;
  if v_prof is null then raise exception 'six probe: supplier-docs holds fewer than two objects to point at'; end if;
  begin
    -- is_demo is a generated column: the ZZ DEMO name, the example.invalid email and the fixture phone set it.
    insert into public.leads (company_name, email, source, phone, owner_phone_verified)
    values ('ZZ DEMO six probe', 'qd-six-probe@example.invalid', 'probe', '+971500000099', true)
    returning id into v_id;
    update public.leads set owner_email_verified = true, registration_submitted_at = now() where id = v_id;
    r_six := public.fn_supplier_mandatory_six_for(v_id);
    begin
      update public.leads set approval_status = 'approved', verified = true where id = v_id;
    exception when check_violation then r_refused := true;
    end;
    r_first := public.fn_sales_engineer_verifies_supplier(v_id, 'probe');
    update public.leads set license_doc_path = v_lic, company_profile_doc_path = v_prof, signed_terms_path = 'suppliers/zz_six_probe.pdf' where id = v_id;
    select approval_status into r_after_docs from public.leads where id = v_id;
    update public.leads set license_doc_path = null where id = v_id;
    select approval_status, licence_gate_reason into r_after_clear, r_reason from public.leads where id = v_id;
    select count(*) into r_actions from public.agent_actions where kind = 'supplier_verification' and target_id = v_id::text;
    raise exception 'six_probe_done';
  exception when others then
    if sqlerrm <> 'six_probe_done' then raise; end if;
  end;
  if r_six is distinct from array['reg_licence','reg_profile','reg_terms']
     or not r_refused
     or r_first->>'decision' is distinct from 'action_required' or r_first->>'reason' is distinct from 'reg_licence'
     or r_after_docs is distinct from 'approved'
     or r_after_clear is distinct from 'action_required' or r_reason is distinct from 'reg_licence'
     or coalesce(r_actions, 0) < 3 then
    raise exception 'six probe FAILED: six=% refused=% first=% after_docs=% after_clear=% reason=% actions=%',
      r_six, r_refused, r_first, r_after_docs, r_after_clear, r_reason, r_actions;
  end if;
  if exists (select 1 from public.leads where id = v_id)
     or (select count(*) from public.leads) <> v_leads_before
     or (select count(*) from public.leads where approval_status = 'approved') <> v_appr_before then
    raise exception 'six probe left something behind or moved a real row';
  end if;
  raise notice 'six probe ok: missing % -> approval refused -> action_required(reg_licence) -> documents land -> approved -> licence cleared -> demoted(reg_licence); % decisions recorded, all rolled back; leads % / approved % unchanged',
    r_six, r_actions, v_leads_before, v_appr_before;
end $probe$;
