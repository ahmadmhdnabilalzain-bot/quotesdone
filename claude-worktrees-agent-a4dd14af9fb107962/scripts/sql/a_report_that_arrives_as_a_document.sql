-- A REPORT THAT ARRIVES AS A DOCUMENT
--
-- "If I ask for a report it should reach me as a proper PDF." Today the command channel answers
-- him in a WhatsApp bubble capped at 1,200 characters, and a company report does not fit in a
-- bubble — agent_brain routinely returns two to four thousand characters and the channel truncates
-- it mid-sentence without saying so.
--
-- Every piece already exists and none of them are wired together: pdf_native renders a branded,
-- letterheaded, signed PDF from an HTML fragment and returns a SEVEN-DAY SIGNED URL, which is
-- exactly the shape Twilio's MediaUrl needs (Twilio fetches it itself, unauthenticated), and
-- sendWa has never passed MediaUrl.
--
-- This issues the one credential for that hop. Scope is pdf_native alone: cred_fn_wa_docs may call
-- license_extract and must not gain the ability to mint documents, and cred_fn_to_agent_brain must
-- not gain either.
do $$
declare v_issued jsonb; v_secret text;
begin
  if not exists (select 1 from app_secrets where key = 'cred_fn_wa_pdf') then
    v_issued := public.fn_internal_credential_issue('fn.wa_inbound_pdf',
                  array['pdf_native'],
                  'Outbound credential for wa_inbound''s report path: it calls pdf_native and nothing else, so the founder''s reports can be rendered as documents without widening the chat or document-reading credentials.', null);
    v_secret := coalesce(v_issued->>'secret', v_issued->>'value', v_issued->>'token');
    if v_secret is null then raise exception 'credential issue returned no secret: %', v_issued::text; end if;
    insert into app_secrets(key, value) values ('cred_fn_wa_pdf', v_secret)
      on conflict (key) do update set value = excluded.value;
  end if;
end $$;
