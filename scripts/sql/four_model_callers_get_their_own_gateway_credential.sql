-- MODEL CALLERS ISSUED AT RUNTIME ARE NAMED FOR A REBUILT DATABASE (19 Oct 2026, it_engineer).
-- PENDING. A no-op on production: every credential below is already live (read 19 Oct).
--
-- Finding llm_gateway_auth. Callers that reach ai_gateway through _shared/think.ts defaultDeps,
-- makeLlm({ fn }) or a direct post were never counted by the audit-9.5 guard, which only saw
-- textual importers of llm.ts. The five that were actually missing on production (public_site,
-- inquiry_intake, marketing_social_inbox, quote_extract, reasoned_delivery) are minted by
-- scripts/sql/the_think_callers_get_their_own_gateway_credential.sql (#1475), which is canonical
-- for them. The widened guard in llm_gateway_credential.test.mjs then found these three, issued
-- at runtime with no minting file in the repository, so a rebuilt database would put them back on
-- the shared secret.
--
-- Same routine as audit 9.5: fn_internal_credential_issue / _rotate, secret stored in app_secrets,
-- which is where llm.ts sec() reads it.
do $$
declare
  callers text[] := array['marketing_outreach','sales_engineer','accountant'];
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
