-- AUDIT 9.5 / decision D3 + D4 (3 Aug 2026): issue the outbound caller credentials.
--
-- Shape chosen (D3, option c): a PRECISE per-caller credential wherever a leak should be
-- attributable to one caller — the money and PII paths — and a small number of TIER credentials
-- everywhere else, so ~59 callers do not become ~59 credentials to rotate.
--
-- D4: doc_extract is NOT special. It used the shared secret as its ai_gateway credential only
-- because the string was shared. It becomes an ordinary member of the fn.ai tier.
--
-- Scopes are taken from scripts/inventory_outbound_hops.mjs, which resolves the callee per fetch
-- CALL and validates every slug against the real function list — not from grep, which has produced
-- a wrong number on this item three times.
--
-- SAFE TO APPLY BEFORE THE CODE CHANGES. Issuing a credential grants nothing by itself: nothing
-- presents it until a caller is migrated, and fn_internal_auth still accepts the legacy shared
-- secret. This is purely additive.
--
-- IDEMPOTENT. Re-running will not mint a second credential for a context that already has a live
-- one, because the plaintext is returned exactly once and a blind re-issue would orphan the value
-- already distributed in app_secrets and silently break every caller using it.

do $$
declare
  v jsonb;
  r record;
  v_issued int := 0;
  v_skipped int := 0;
begin
  for r in
    select * from (values
      -- ---- PRECISE, per caller: money, PII, and the customer/supplier surfaces --------------
      ('fn.customer_api',    'cred_fn_customer_api',    array['ai_gateway','cad_convert','compliance_archive','drawing_boq','drawing_redact','pdf_native','quote_compare','route_inquiry']),
      ('fn.supplier_api',    'cred_fn_supplier_api',    array['license_extract','profile_ai','quote_extract','supplier_review']),
      ('fn.supplier_portal', 'cred_fn_supplier_portal', array['license_extract']),
      ('fn.reveal_invoice',  'cred_fn_reveal_invoice',  array['pdf_native']),
      ('fn.finance_doc',     'cred_fn_finance_doc',     array['ai_gateway','extract_text','finance_ingest']),
      ('fn.kyc',             'cred_fn_kyc',             array['compliance_archive']),
      ('fn.pdpl_request',    'cred_fn_pdpl_request',    array['alert_founder']),
      -- os_api is the operator console. `secretary_act` is in this scope because the inventory
      -- found it at os_api:262 via a payload object built on a separate line — the single-line
      -- regex missed it, and issuing without it would have produced an out_of_scope outage on the
      -- secretary_chat action.
      ('fn.os_api',          'cred_fn_os_api',          array['extract_text','gen_category_knowledge','knowledge_exam','make_pdf','prompt_gate','send_whatsapp','secretary_act']),

      -- ---- TIERS -----------------------------------------------------------------------------
      -- fn.ai is by far the biggest: 29 callers, 31 hops, all to one callee.
      ('fn.ai',              'cred_fn_ai',              array['ai_gateway']),
      ('fn.docs',            'cred_fn_docs',            array['pdf_native','make_pdf','make_xlsx','extract_text','cad_convert','drawing_boq','drawing_redact','compliance_archive','marketing_image']),
      ('fn.knowledge',       'cred_fn_knowledge',       array['kb_search','kb_deepen','kb_ingest','kb_ingest_text','kb_fill_gap','knowledge_exam','gen_category_knowledge']),
      ('fn.internal',        'cred_fn_internal',        array['alert_founder','send_outbox','send_whatsapp','route_inquiry','agent_brain','postiz_publish','meta_ads','dropbox_sync','finance_ingest','translate_html','deploy_next_preview','inquiry_parse','supplier_review','quote_extract','profile_ai','license_extract','quote_compare','prompt_gate','dept_learn','dept_plan','intent_router','asset_delete'])
    ) as t(ctx, k, scope)
  loop
    if exists (select 1 from public.internal_credential c
                where c.context = r.ctx and c.active and c.retired_at is null) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v := public.fn_internal_credential_issue(
           r.ctx, r.scope,
           'D3 outbound caller credential, issued 3 Aug 2026 from the resolved hop inventory');

    -- Distribution stays on app_secrets for now. Decision D2: ship the migration on the existing
    -- mechanism and move to per-function environment secrets AFTER launch. Changing the credential
    -- distribution mechanism in the middle of a credential migration is how you get an outage.
    -- The limit is real and is recorded, not hidden: any compromised edge function can read every
    -- row in this table, so scoping buys attribution, rotation and containment of a credential
    -- leaked through logs or a third party — it does NOT contain a compromised function.
    insert into public.app_secrets (key, value)
    values (r.k, v ->> 'secret')
    on conflict (key) do update set value = excluded.value;

    v_issued := v_issued + 1;
  end loop;

  raise notice 'D3 credentials: issued=%, skipped_already_present=%', v_issued, v_skipped;
end $$;;
