-- A CUSTOMER'S WHATSAPP DRAWING IS READ LIKE A PORTAL UPLOAD: wa_inbound gets its own credential for drawing_boq and drawing_redact.
-- it_engineer, 10 Nov 2026 (channels audit R2, HIGH). Seat: customer_support (WhatsApp); the drawing path is the portal's.
--
-- MEASURED (production, SELECT only, 10 Nov 2026): wa_inbound holds two internal credentials, fn.wa_inbound (scope ai_gateway)
-- and fn.wa_docs (scope license_extract). drawing_boq is reachable by fn.customer_api and cron.agents, drawing_redact by
-- fn.customer_api and fn.attach_photos; nothing wa_inbound holds may call either, so a registered customer's drawing sent on
-- WhatsApp (wa_inbound/customer_files.ts) could be stored and attached but not read for its take-off nor drawn for suppliers.
-- fn_internal_credential_issue no longer exists (pg_proc 10 Nov 2026: only fn_internal_credential_hash and the audit trigger),
-- so the credential is written the way that routine wrote one: a random secret, its hash on internal_credential, the secret in
-- app_secrets under the name the function reads (sec('cred_fn_wa_drawings')).
--
-- WHAT THIS CHANGES: one new credential row (context fn.wa_drawings, scope drawing_boq + drawing_redact, nothing else) and one
-- app_secrets row. Idempotent: nothing happens when cred_fn_wa_drawings already exists. NOT CHANGED: fn.wa_docs keeps
-- license_extract alone (a_report_that_arrives_as_a_document.sql: the document-reading credential gains nothing), and no
-- routine, table, grant or policy is created, so there is nothing to revoke.
-- prevented by: supabase/functions/wa_inbound/a_customers_file_reaches_their_request.test.ts (the edge path) and the verdict
-- row at the end of this file.
do $$
declare v_secret text;
begin
  if not exists (select 1 from public.app_secrets where key = 'cred_fn_wa_drawings') then
    v_secret := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.internal_credential (context, label, secret_hash, scope)
    values ('fn.wa_drawings',
            'wa_inbound: a registered customer''s drawing sent on WhatsApp is read (drawing_boq) and drawn for suppliers with the identity left out (drawing_redact), as a portal upload is',
            public.fn_internal_credential_hash(v_secret), array['drawing_boq', 'drawing_redact']);
    insert into public.app_secrets (key, value) values ('cred_fn_wa_drawings', v_secret);
  end if;
end $$;

select case
  when exists (select 1 from public.internal_credential c join public.app_secrets s on s.key = 'cred_fn_wa_drawings'
                where c.context = 'fn.wa_drawings' and c.active and c.scope @> array['drawing_boq', 'drawing_redact']
                  and array_length(c.scope, 1) = 2 and c.secret_hash = public.fn_internal_credential_hash(s.value))
  then 'PROBE OK'
  else 'PROBE FAILED: cred_fn_wa_drawings is not a live credential scoped to drawing_boq and drawing_redact alone' end as verdict;
