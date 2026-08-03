-- RESTORE. I rewrote fn_internal_auth from a 900-character fragment of its own definition instead
-- of from its source, and guessed the hash as encode(digest(p_secret,'sha256'),'hex'). The real
-- function uses public.fn_internal_credential_hash(p_secret). Every credential therefore stopped
-- matching and the verifier refused EVERY internal call across the platform with
-- 'unknown_credential' — a self-inflicted outage, live, for the few minutes between the two
-- migrations. Caught by probing the change rather than trusting that it applied cleanly; "migration
-- succeeded" says the SQL parsed, not that the function still works.
--
-- Restored verbatim from supabase/migrations/20260803044744, with ONE addition, which was the whole
-- point of the change: a named audit row for every successful use of a LEGACY credential.
--
-- WHY THAT ADDITION IS NEEDED. legacy.shared.use_count moved 373 -> 376 today with last_function =
-- 'ai_gateway', AFTER all 32 of ai_gateway's shared-secret callers were migrated and verified. Going
-- to internal_credential_audit to find the caller returned nothing: of 420 rows, every one marked
-- allowed is reason='issued', i.e. credential issuance. A successful authentication had never been
-- recorded. The original comment says so outright — "Successes bump counters on the credential
-- rather than writing a row per call" — which is right for scoped credentials (email_cron alone is
-- 34 uses in an hour) and wrong for the legacy one, whose every remaining use is a thing someone
-- needs to find and fix before 10 August.
--
-- So: scoped successes stay unlogged, legacy successes get a row with a function name on it. The
-- branch stops firing by itself on withdrawal day.
create or replace function public.fn_internal_auth(p_secret text, p_function text)
returns jsonb language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare c public.internal_credential%rowtype; v_hash text; v_fn text;
begin
  v_fn := lower(btrim(coalesce(p_function, '')));
  if v_fn = '' then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'no_function_named', p_function);
    return jsonb_build_object('ok', false, 'error', 'no_function_named',
      'message', 'The verifier was called without naming the function being invoked, so it cannot check scope.');
  end if;

  if coalesce(btrim(p_secret), '') = '' then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'no_credential_presented', v_fn);
    return jsonb_build_object('ok', false, 'error', 'no_credential_presented');
  end if;

  v_hash := public.fn_internal_credential_hash(p_secret);
  select * into c from public.internal_credential where secret_hash = v_hash;

  if not found then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'unknown_credential', v_fn);
    return jsonb_build_object('ok', false, 'error', 'unknown_credential');
  end if;

  if not c.active or c.retired_at is not null then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, false, 'credential_retired');
    return jsonb_build_object('ok', false, 'error', 'credential_retired', 'context', c.context);
  end if;

  if c.expires_at is not null and c.expires_at <= now() then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, false, 'credential_expired');
    return jsonb_build_object('ok', false, 'error', 'credential_expired', 'context', c.context,
      'expired_at', c.expires_at);
  end if;

  if not (c.scope @> array['*'] or c.scope @> array[v_fn]) then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason, detail)
    values (c.id, c.context, v_fn, false, 'out_of_scope', jsonb_build_object('scope', c.scope));
    return jsonb_build_object('ok', false, 'error', 'out_of_scope', 'context', c.context,
      'message', format('The %s credential is not scoped to call %s.', c.context, v_fn));
  end if;

  update public.internal_credential
     set last_used_at = now(), last_function = v_fn, use_count = use_count + 1
   where id = c.id;

  -- THE ADDITION. Legacy only.
  if c.is_legacy then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, true, 'legacy_secret_used');
  end if;

  return jsonb_build_object('ok', true, 'context', c.context, 'credential_id', c.id,
                            'legacy', c.is_legacy, 'scope_all', c.scope @> array['*']);
end $fn$;

comment on function public.fn_internal_auth(text, text) is
  'AUDIT 9.5. The single verifier for server-to-server calls. Fail-closed: unknown, retired, expired or out-of-scope is refused and audited. Scoped successes bump counters only; LEGACY successes also write a named audit row, because every remaining one is a caller that has to be found before the shared secret is withdrawn.';

create or replace view public.v_legacy_secret_users as
select function_name, count(*) as uses, min(at) as first_seen, max(at) as last_seen
  from public.internal_credential_audit
 where reason = 'legacy_secret_used'
 group by function_name order by count(*) desc;
comment on view public.v_legacy_secret_users is
  'Who is still presenting the shared secret, BY NAME. Empty until the next legacy use after 3 Aug '
  '2026 ~16:35 UTC: before that the audit recorded refusals and issuances but never a successful '
  'authentication, so a moving counter had no name attached to it.';;
