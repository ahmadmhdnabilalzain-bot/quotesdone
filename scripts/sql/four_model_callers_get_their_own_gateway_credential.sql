-- FOUR MODEL CALLERS GET THEIR OWN GATEWAY CREDENTIAL (19 Oct 2026, it_engineer).
-- PENDING: not applied. The release operator applies it under Option A (live customer-facing outage).
--
-- Finding llm_gateway_auth: public_site, inquiry_intake, marketing_social_inbox and
-- marketing_lead_sourcing have no fn.<caller> row in internal_credential and no
-- app_secrets.cred_fn_<caller>. _shared/llm.ts gatewayCredential() therefore falls back to
-- inbound_secret, whose credential legacy.shared is inactive, and ai_gateway answers 403.
-- Measured 12-18 Oct (agent_runs agent='llm_gateway_auth', one row per caller per 30 min, so a floor):
-- public_site 49 forbidden windows, inquiry_intake 8, marketing_lead_sourcing 1.
--
-- WHY THEY WERE NEVER MINTED: none of them imports _shared/llm.ts. They reach it through
-- _shared/think.ts defaultDeps(admin, '<fn>'), which imports llm.ts dynamically and passes its own
-- fn name. The audit-9.5 issuing list and its guard (llm_gateway_credential.test.mjs) only counted
-- directories that import llm.ts textually, so these callers were registered nowhere.
--
-- Same routine as audit 9.5: fn_internal_credential_issue / _rotate, secret stored in app_secrets,
-- which is where llm.ts sec() reads it. No separate edge-secret push exists for cred_fn_*.
do $$
declare
  -- The new guard (every defaultDeps fn name has an issuing file) found three more. reasoned_delivery
  -- has no credential on production either (a fifth gap, same cause). marketing_outreach and
  -- sales_engineer were issued at runtime and are live; naming them here is a no-op on production
  -- and keeps them on a rebuilt database.
  callers text[] := array['public_site','inquiry_intake','marketing_social_inbox','marketing_lead_sourcing',
                          'reasoned_delivery','marketing_outreach','sales_engineer','accountant','quote_extract'];
  c text; v jsonb; v_id bigint; v_has_secret boolean; n_missing int;
begin
  foreach c in array callers loop
    select id into v_id from public.internal_credential where context = 'fn.' || c and active;
    select exists(select 1 from public.app_secrets where key = 'cred_fn_' || c and coalesce(btrim(value), '') <> '')
      into v_has_secret;

    if v_id is not null then
      update public.internal_credential
         set scope = array(select distinct s from unnest(scope || array['ai_gateway']) s order by s)
       where id = v_id and not (scope @> array['ai_gateway']);
      if not v_has_secret then
        v := public.fn_internal_credential_rotate('fn.' || c,
               'rotated 19 Oct 2026: the credential existed but its secret was not stored, so it could never be presented');
        insert into public.app_secrets (key, value) values ('cred_fn_' || c, v->>'secret')
        on conflict (key) do update set value = excluded.value;
      end if;
    else
      v := public.fn_internal_credential_issue('fn.' || c, array['ai_gateway'],
             '_shared/think.ts defaultDeps -> _shared/llm.ts -> ai_gateway. Issued 19 Oct 2026 (finding llm_gateway_auth).');
      insert into public.app_secrets (key, value) values ('cred_fn_' || c, v->>'secret')
      on conflict (key) do update set value = excluded.value;
    end if;
  end loop;

  select count(*) into n_missing
    from unnest(callers) as t(fnname)
   where not exists (
     select 1 from public.internal_credential ic
      join public.app_secrets s on s.key = 'cred_fn_' || t.fnname
     where ic.context = 'fn.' || t.fnname and ic.active and ic.scope @> array['ai_gateway']
       and coalesce(btrim(s.value), '') <> '');
  if n_missing > 0 then
    raise exception '% of % callers still have no presentable ai_gateway credential', n_missing, array_length(callers, 1);
  end if;
end $$;
