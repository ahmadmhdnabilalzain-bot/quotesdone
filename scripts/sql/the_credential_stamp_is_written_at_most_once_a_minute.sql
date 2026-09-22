-- THE CREDENTIAL STAMP IS WRITTEN AT MOST ONCE A MINUTE (22 Sep 2026, it_engineer, CONN-08).
--
-- WHAT WAS MEASURED. fn_internal_auth is called 60,527 times in 24 hours — it is the gate in front of
-- every internal edge function — and it accounted for 5,048 seconds of database time in that window.
-- It reads one row and then writes it:
--
--     update public.internal_credential
--        set last_used_at = now(), last_function = v_fn, use_count = use_count + 1
--      where id = c.id;
--
-- public.internal_credential holds 96 rows (measured 22 Sep 2026), and the calling traffic is
-- concentrated on the few that the scheduled functions present, so those 60,527 UPDATEs land on a
-- handful of tuples: every call makes a new row version, every call writes WAL, every call competes for
-- the same page's lock, and autovacuum spends the day cleaning up after a usage stamp. Nothing reads the
-- stamp at that resolution — fn_it_credential_reverify asks whether the NEW credential has been used
-- since rotation, and fn_security_detect reports last_used_at and use_count in a finding.
--
-- WHAT CHANGES. The stamp is written when it would actually say something new: the credential has not
-- been stamped in the last minute, or it is being used for a DIFFERENT function than last time. A
-- credential in steady use is therefore stamped about 1,440 times a day instead of 60,527.
--
-- WHAT use_count NOW MEANS, said plainly because the name no longer says it: it is the number of times
-- this credential's use was STAMPED, not the number of calls. It was already only ever read as
-- "has this been used at all" and "here is the number in a finding", and both survive the change. A
-- true call count belongs in internal_credential_audit, which is a row per event and is untouched.
--
-- NOTHING ELSE IN THE ROUTINE MOVES. Every refusal path, the audit insert on each, the scope check and
-- the legacy_secret_used audit row are byte-for-byte what they were; this is the one UPDATE.

create or replace function public.fn_internal_auth(p_secret text, p_function text)
returns jsonb
language plpgsql
security definer
-- pg_temp ADDED 22 Sep 2026 (independent review, while the file was open). The live routine was pinned
-- to 'public', 'extensions' only. For a SECURITY DEFINER routine that is not a harmless omission: with
-- pg_temp absent from the list Postgres searches it FIRST for functions and operators, so a caller who
-- can create a temporary object can shadow one this body uses and have it run with the definer's
-- privileges. Naming pg_temp LAST is what puts it after public and extensions.
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
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

  -- THE STAMP, AT MOST ONCE A MINUTE PER FUNCTION (CONN-08). See the header: this same UPDATE, run on
  -- every one of 60,527 calls a day against a handful of shared rows, was 5,048 s of database time.
  if c.last_used_at is null or c.last_used_at < now() - interval '1 minute'
     or c.last_function is distinct from v_fn then
    update public.internal_credential
       set last_used_at = now(), last_function = v_fn, use_count = use_count + 1
     where id = c.id;
  end if;

  -- THE ADDITION. Legacy only.
  if c.is_legacy then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, true, 'legacy_secret_used');
  end if;

  return jsonb_build_object('ok', true, 'context', c.context, 'credential_id', c.id,
                            'legacy', c.is_legacy, 'scope_all', c.scope @> array['*']);
end $function$;

revoke execute on function public.fn_internal_auth(text, text) from public, anon, authenticated;
