-- the_acceptance_certificate_follows_the_trade_licence.sql
--
-- Seat: sales_engineer (supplier registration). Built by it_engineer, 12 Nov 2026. Founder ruling 1672 (12 Nov 2026): the supplier
-- "directly accepts the terms and conditions. We get the copy of that with the IP address ... Every single thing that comes out is
-- a PDF in our template", and "eventually legally we care about the trade license the most". His own certificate that evening
-- printed the company as he had typed it ("Triple six real estate") and no licence number.
--
-- Since ruling 1672 the Supplier Agreement is accepted at its own step, BEFORE the trade licence is attached (supplier_api
-- accept_terms). The acceptance is recorded at once, exactly as before: the time, the IP and device of that request, the version
-- and the SHA-256 of the text (_shared/supplier_terms.ts); z21_sign_supplier_on_acceptance asks compliance_archive for the
-- certificate, which then names the company "Not yet read from the trade licence" and draws no licence row (certificate.ts).
-- THIS TRIGGER issues the certificate again, for the SAME acceptance (compliance_archive reads the acceptance from the row; force
-- re-renders it, compare-and-set on signed_terms_path), the moment the licence is read: the company as the licence names it and the
-- licence number. Then the signed copy is the one Dropbox files (fn_enqueue_doc_backups files a supplier once he is named).
-- WHO IS RE-ISSUED, and who is not ("existing certificates are not rewritten"):
--   * a certificate exists and the licence's legal name or number was just read (it changed, to a value); AND
--   * the registration was not yet submitted (the licence read before Submit, the order of ruling 1672), or the company had no
--     name yet (a licence read after Submit names a company registered with none: create_company since ruling 1672);
--   * never an approved supplier, never a row with no acceptance, no certificate or no account.
-- Every supplier registered before this change has submitted and carries a name, so none of their certificates is re-issued.
-- A re-issue is recorded in agent_actions (sales_engineer / supplier_agreement_reissued, auto_done).
-- The trigger function is new: security definer, search_path pinned, EXECUTE revoked from every role but the owner.
-- APPLY ORDER: after a_supplier_is_named_by_his_trade_licence_not_by_typing.sql; deploy compliance_archive (the certificate names
-- the licensed company and its number) BEFORE applying this, or the re-issue prints what the old renderer prints.
-- Probe: the_acceptance_certificate_follows_the_trade_licence_probe.sql (rolled back).

create or replace function public.fn_sign_supplier_again_when_his_licence_is_read()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_secret text; v_ref text;
begin
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  -- resolved defensively, as qd_sign_supplier does: a trigger on the licence path must never refuse the licence
  begin v_ref := public.qd_project_ref(); exception when others then v_ref := null; end;
  if v_ref is null or coalesce(v_secret, '') = '' then return null; end if;
  perform net.http_post(
    'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
    jsonb_build_object('__secret', v_secret, 'action', 'sign', 'kind', 'supplier', 'email', new.claimed_by, 'force', true),
    '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_agreement_reissued', 'auto_done', 'low',
          'Supplier Agreement certificate issued again from the trade licence — ' || left(coalesce(nullif(btrim(new.licence_legal_name), ''), nullif(btrim(new.company_name), ''), 'supplier #' || new.id), 120),
          'No action required. The supplier accepted the Supplier Agreement before attaching the trade licence (founder ruling 1672); now that the licence is read, the certificate of that same acceptance (same time, IP, device, version and text hash) is issued again naming the company as the licence names it and its licence number.',
          jsonb_build_object('supplier_id', new.id, 'accepted_terms_at', new.accepted_terms_at, 'previous_certificate', old.signed_terms_path,
                             'licence_legal_name', new.licence_legal_name, 'trade_license_no', new.trade_license_no),
          'leads', new.id::text);
  return null;
end $fn$;
revoke execute on function public.fn_sign_supplier_again_when_his_licence_is_read() from public, anon, authenticated;

drop trigger if exists z22_sign_supplier_again_when_his_licence_is_read on public.leads;
create trigger z22_sign_supplier_again_when_his_licence_is_read
  after update of licence_legal_name, trade_license_no on public.leads
  for each row
  when (new.accepted_terms_at is not null and new.signed_terms_path is not null and new.claimed_by is not null
        and coalesce(new.approval_status, '') <> 'approved'
        and (new.registration_submitted_at is null or coalesce(btrim(old.company_name), '') = '')
        and ((new.licence_legal_name is not null and old.licence_legal_name is distinct from new.licence_legal_name)
             or (new.trade_license_no is not null and old.trade_license_no is distinct from new.trade_license_no)))
  execute function public.fn_sign_supplier_again_when_his_licence_is_read();
