-- FIVE MODEL CALLERS THAT NEVER GOT A CREDENTIAL OF THEIR OWN.
--
-- public_site, inquiry_intake, marketing_social_inbox, quote_extract and reasoned_delivery (_shared/reasoned_delivery.ts,
-- run inside wa_inbound, site_assistant, supplier_api, email_triage and others) reach the model through _shared/think.ts
-- defaultDeps(admin, '<fn>') -> makeLlmRich({ fn }). llm.ts gatewayCredential presents
-- app_secrets.cred_fn_<fn>, and only falls back to the shared inbound_secret when that key is absent.
-- None of the five had one, and the shared secret's context (legacy.shared) is inactive, so
-- ai_gateway refused every call with 403 and the caller read the null as "the model declined".
-- Measured 19 Oct 2026 in agent_runs (agent llm_gateway_auth, 14 days): public_site 71
-- legacy_fallback + 71 gateway_forbidden, inquiry_intake 8 + 8, marketing_social_inbox 2 + 2;
-- quote_extract and reasoned_delivery 0 rows (found by the new check, not by a refusal).
--
-- They were missed because the audit-9.5 guard (scripts/checks/llm_gateway_credential.test.mjs) lists
-- only functions whose index.ts imports _shared/llm.ts directly; these reach it through think.ts.
-- scripts/checks/every_model_caller_has_a_gateway_credential.test.mjs now covers that path.
--
-- marketing_lead_sourcing (1 + 1, last 12 Oct) is NOT minted: no source names that caller any more —
-- the batch now asks through the marketing seat's own client — and a credential for a caller that
-- does not exist is standing access with no owner.
--
-- SCOPE is ['ai_gateway'] only, as fn.site_assistant: think.ts embeds through ml_embed_client.ts,
-- which presents cred_fn_ai (fn.ai holds embed_ml), so these callers need nothing else.
--
-- The secret is generated here, hashed by fn_internal_credential_hash, and written to app_secrets —
-- never in this file. Idempotent: an existing context is left exactly as it is.

do $mint$
declare
  v_fn text;
  v_secret text;
begin
  foreach v_fn in array array['public_site', 'inquiry_intake', 'marketing_social_inbox', 'quote_extract', 'reasoned_delivery'] loop
    continue when exists (select 1 from public.internal_credential where context = 'fn.' || v_fn);
    v_secret := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
    values ('fn.' || v_fn,
            v_fn || ' — model calls through _shared/think.ts to ai_gateway',
            public.fn_internal_credential_hash(v_secret), array['ai_gateway'], false, true);
    insert into public.app_secrets (key, value)
    values ('cred_fn_' || v_fn, v_secret)
    on conflict (key) do update set value = excluded.value;
  end loop;
end
$mint$;

-- Verdict row: existence and activity only, never a value.
select case when count(*) = 5 then 'PROBE OK'
            else 'PROBE FAILED: ' || (5 - count(*))::text || ' of 5 callers lack an active credential with a matching secret' end as verdict
  from public.internal_credential c
  join public.app_secrets s on s.key = 'cred_' || replace(c.context, '.', '_')
 where c.context in ('fn.public_site', 'fn.inquiry_intake', 'fn.marketing_social_inbox', 'fn.quote_extract', 'fn.reasoned_delivery')
   and c.active and c.scope = array['ai_gateway'] and length(s.value) = 64
   and c.secret_hash = public.fn_internal_credential_hash(s.value);
