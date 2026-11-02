-- A STOP FROM THE NUMBER A SUPPLIER OPTED IN FROM OPTS THAT SUPPLIER OUT (it_engineer for marketing, 27 Oct 2026).
--
-- Assigned: it_engineer (for marketing). Found in the safety review of the WhatsApp supplier invitation before the
-- founder's switch (ledger 1373: "if whatsapp invitations are safe of course proceed").
--
-- MEASURED (27 Oct 2026, main 21640c8db, read-only):
--   * An opt-in is a (lead, number) pair. fn_supplier_whatsapp_optin_record takes p_phone, so the number a supplier
--     said yes on can be one that is on NO lead row (not phone_e164, not whatsapp_phone). The queue sends to THAT
--     number (opted.phone), by design.
--   * fn_wa_supplier_invite_opt_out (19 Oct file, canonical until this one) set whatsapp_opt = 'none' only on leads
--     whose phone_e164 or whatsapp_phone is the STOP number. A STOP from an opted-in number that is on no lead row
--     therefore changed no lead: the queue's opt-out filters (y.whatsapp_opt and l.whatsapp_opt) both still passed,
--     and the invitation would have gone to a person who had just said STOP. The STOP-rate brake in
--     fn_wa_supplier_invite_gate counts l.whatsapp_opt = 'none' on the invited lead, so that STOP was not counted
--     either.
--   * Production today: 0 opt-ins and 0 invitations, so no person was affected. The gap is latent.
--
-- WHAT THIS CHANGES: the opt-out also marks every lead whose recorded opt-in names the STOP number. The queue, the
-- send-time gate in send_whatsapp (which reads the lead's whatsapp_opt) and the STOP-rate brake all read that column,
-- so all three now see it. The opt-in row itself is kept: it is the evidence of what the supplier once agreed to.
-- NOT CHANGED: the cancellation of queued rows by to_phone, the signature, the ACL (create or replace keeps it, so no
-- revoke here), and any switch.
-- Prevented by: scripts/checks/the_supplier_whatsapp_invitation_waits_for_opt_in_and_both_switches.test.mjs
-- ("STOP from a number that is on no lead row ...").

create or replace function public.fn_wa_supplier_invite_opt_out(p_from text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '\D', '', 'g'); v_leads int; v_cancelled int;
begin
  if length(v_phone) < 9 then return jsonb_build_object('ok', false, 'reason', 'no number'); end if;
  update public.leads set whatsapp_opt = 'none'
   where phone_e164 = v_phone or whatsapp_phone = v_phone
      or id in (select o.lead_id from public.supplier_whatsapp_optin o where o.phone = v_phone);
  get diagnostics v_leads = row_count;
  update public.notifications set status = 'cancelled', last_error = 'the recipient replied STOP; WhatsApp opt-out honoured'
   where type = any (array['supplier_invite_wa']) and to_phone = v_phone and status in ('queued', 'sending');  -- MARKETING_TYPES (_shared/marketing_send_gate.ts)
  get diagnostics v_cancelled = row_count;
  return jsonb_build_object('ok', true, 'leads_opted_out', v_leads, 'invitations_cancelled', v_cancelled);
end $fn$;
