-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721131333   name: supplier_doc_expiry_gate_reminder_and_suspension
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Document expiry: reminder one week out, then temporary suspension from matching.
--
-- WHAT ALREADY EXISTED (kept, not rebuilt):
--   * fn_reconcile_licence_blocks(grace) - suspended approved suppliers with an expired TRADE
--     LICENCE by setting matching_blocked/matching_block_reason, and restored them on renewal,
--     without clobbering manual blocks. Cron licence_block_reconcile_daily, 03:15.
--   * doc_reminder edge function - emails suppliers at 14 days about licence, insurance,
--     establishment card, VAT/TRN, ISO and manufacturer authorisation. Cron doc_reminders_daily.
--   * match_suppliers_kw already excludes matching_blocked, so suspension genuinely stops matches.
--
-- WHAT WAS MISSING, AND IS ADDED HERE:
--   1. Only the trade licence caused suspension. Insurance could lapse indefinitely.
--   2. The supplier was never told they had been suspended, or that they had been restored.
--   3. There was no final notice at one week - the last contact was the 14-day email.
--   4. No WhatsApp anywhere. notifications.channel has only ever held 'email' and 'sms'.
--
-- SCOPE OF SUSPENSION - deliberate: trade licence and insurance only. ISO and manufacturer
-- authorisation stay reminder-only. Cutting a supplier out of the marketplace for a lapsed ISO
-- certificate, which is not legally required to trade, would cost supply for no compliance gain.
-- Both gating documents are listed in one array below so the set is easy to change.

create or replace function public.fn_reconcile_doc_blocks(p_grace_days integer default 0)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lic_susp int := 0; v_ins_susp int := 0; v_restored int := 0;
  v_cut date := current_date - make_interval(days => p_grace_days);
  rec record;
begin
  -- ---- SUSPEND: trade licence expired -------------------------------------------------
  -- Only touches rows that are unblocked or already blocked for a document reason, so a
  -- manual block set by the team is never overwritten or silently cleared.
  for rec in
    select id, company_name, claimed_by, email, phone, whatsapp, license_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and license_expiry is not null and license_expiry < v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'licence_expired'
     where id = rec.id;
    v_lic_susp := v_lic_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - trade licence expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your trade licence expired on ' || rec.license_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed licence attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy - nothing else is needed and no fee applies.',
      'queued');
  end loop;

  -- ---- SUSPEND: insurance expired -----------------------------------------------------
  for rec in
    select id, company_name, claimed_by, email, insurance_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and insurance_expiry is not null and insurance_expiry < v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'insurance_expired'
       -- a licence block is the more serious of the two, so do not downgrade its reason
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'insurance_expired'
     where id = rec.id;
    v_ins_susp := v_ins_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - insurance expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your insurance certificate expired on ' || rec.insurance_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed certificate attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy.',
      'queued');
  end loop;

  -- ---- RESTORE: the blocking document is valid again -----------------------------------
  -- Only clears blocks this job set. A manual block stays put.
  for rec in
    select id, company_name, claimed_by, email, matching_block_reason
      from leads
     where matching_block_reason in ('licence_expired','insurance_expired')
       and ((matching_block_reason = 'licence_expired'
             and (license_expiry is null or license_expiry >= v_cut))
         or (matching_block_reason = 'insurance_expired'
             and (insurance_expiry is null or insurance_expiry >= v_cut)))
  loop
    update leads set matching_blocked = false, matching_block_reason = null where id = rec.id;
    v_restored := v_restored + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_restored', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is active again',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Thank you - your documents are up to date and your account is active again. You will start receiving matching customer requests immediately.',
      'queued');
  end loop;

  return json_build_object('licence_suspended', v_lic_susp, 'insurance_suspended', v_ins_susp,
                           'restored', v_restored, 'grace_days', p_grace_days, 'ran_at', now());
end $function$;

comment on function public.fn_reconcile_doc_blocks(integer) is
  'Suspends approved suppliers from matching when their trade licence or insurance has expired, and restores them automatically on renewal. Never overwrites a manual block. Notifies the supplier on both transitions. Replaces fn_reconcile_licence_blocks, which covered the trade licence only and told the supplier nothing.';

revoke all on function public.fn_reconcile_doc_blocks(integer) from public, anon, authenticated;
