-- THE LICENCE ARRIVED AND NOTHING READ IT
--
-- wa_inbound has read `Body` since the day it was written and has never once looked at MediaUrl0.
-- A supplier who does exactly what the invitation asks — attach your trade licence — gets a
-- courteous reply about how QuotesDone works, and the document goes nowhere. Not to storage, not
-- to license_extract, not to leads.license_doc_path, not to doc_reviews. Nothing records that it
-- arrived, so nobody can even find out it was ignored.
--
-- The identical journey by EMAIL has worked for weeks: resend_inbound sanitises the attachment,
-- uploads it to supplier-docs, calls license_extract, writes trade_license_no / license_authority
-- / license_expiry / TRN back onto the lead and files a doc_reviews row. This change gives
-- WhatsApp the same path rather than a second one — same bucket, same sanitiser, same extractor,
-- same columns, same audit row.
--
-- This file issues the one credential that hop needs. wa_inbound already holds cred_fn_ai (for
-- ai_gateway) and cred_fn_to_agent_brain (scope ['agent_brain']); neither may call license_extract
-- and neither should be widened to, because a credential's value is the exactness of its scope.
do $$
declare v_issued jsonb; v_secret text;
begin
  if not exists (select 1 from app_secrets where key = 'cred_fn_wa_docs') then
    v_issued := public.fn_internal_credential_issue('fn.wa_inbound_docs',
                  array['license_extract'],
                  'Outbound credential for wa_inbound''s document path: it calls license_extract and nothing else. Held separately from cred_fn_ai and cred_fn_to_agent_brain so the reading of a supplier document cannot borrow the authority of the chat path.', null);
    v_secret := coalesce(v_issued->>'secret', v_issued->>'value', v_issued->>'token');
    if v_secret is null then raise exception 'credential issue returned no secret: %', v_issued::text; end if;
    insert into app_secrets(key, value) values ('cred_fn_wa_docs', v_secret)
      on conflict (key) do update set value = excluded.value;
  end if;
end $$;
