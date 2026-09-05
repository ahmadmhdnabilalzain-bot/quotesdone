-- THE INBOUND CLASSIFIER USES THE ONE DOOR (6 Sep 2026, MASTER_PLAN A6).
--
-- resend_inbound classified supplier attachments by POSTing to openrouter.ai directly with the raw
-- provider key. It honoured the zero-cost gate, but it ran outside fn_llm_preflight, the budget,
-- the cache and the cost ledger, and it was the estate's last chat/completions call not made through
-- ai_gateway. The function now imports _shared/llm.ts, which presents app_secrets.cred_fn_resend_inbound
-- to the gateway. This file issues that credential the same way the audit-9.5 migration issued the
-- other 31 (widen-or-issue, re-runnable) and asserts the invariant, not the change.
--
--   node scripts/apply_sql.mjs scripts/sql/the_inbound_classifier_uses_the_one_door.sql --apply --ddl
begin;

do $issue$
declare v_id bigint; v_has_secret boolean; v jsonb; c constant text := 'resend_inbound';
begin
  select id into v_id from public.internal_credential where context = 'fn.' || c and active and retired_at is null order by created_at desc limit 1;
  select exists(select 1 from public.app_secrets where key = 'cred_fn_' || c) into v_has_secret;

  if v_id is not null and v_has_secret then
    update public.internal_credential
       set scope = array(select distinct s from unnest(scope || array['ai_gateway']) s order by s)
     where id = v_id and not (scope @> array['ai_gateway']);
  elsif v_id is not null and not v_has_secret then
    v := public.fn_internal_credential_rotate('fn.' || c, 'rotated 6 Sep 2026: the credential existed but its secret was not stored');
    insert into public.app_secrets (key, value) values ('cred_fn_' || c, v->>'secret')
    on conflict (key) do update set value = excluded.value;
  else
    v := public.fn_internal_credential_issue('fn.' || c, array['ai_gateway'],
           '_shared/llm.ts -> ai_gateway. Issued 6 Sep 2026 when resend_inbound left the direct-provider register (MASTER_PLAN A6).',
           now() + interval '1 year');
    insert into public.app_secrets (key, value) values ('cred_fn_' || c, v->>'secret')
    on conflict (key) do update set value = excluded.value;
  end if;
end $issue$;

-- The invariant: the credential the function will present is one ai_gateway accepts. Verified by
-- calling the verifier with the stored secret; the secret never leaves the database.
do $proof$
declare v_auth jsonb;
begin
  select public.fn_internal_auth(s.value, 'ai_gateway') into v_auth
    from public.app_secrets s where s.key = 'cred_fn_resend_inbound';
  if v_auth is null or coalesce((v_auth->>'ok')::boolean, false) is not true then
    raise exception 'cred_fn_resend_inbound is not accepted by fn_internal_auth for ai_gateway: %', coalesce(v_auth->>'error', 'no secret stored');
  end if;
  raise notice 'proof: fn.resend_inbound credential accepted for ai_gateway (context %)', v_auth->>'context';
end $proof$;

commit;
