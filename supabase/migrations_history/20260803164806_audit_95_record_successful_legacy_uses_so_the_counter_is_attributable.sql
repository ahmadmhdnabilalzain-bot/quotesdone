-- AUDIT 9.5 — the counter moved and there was no way to find out who moved it.
--
-- WHAT HAPPENED. legacy.shared.use_count went 373 -> 376 between 15:38 and 16:23 UTC today, with
-- last_function = 'ai_gateway' — after every one of ai_gateway's 32 shared-secret callers had been
-- migrated and verified. Going to internal_credential_audit to find the caller returned nothing:
-- of 420 audit rows, the 50 marked allowed are all reason='issued', i.e. credential ISSUANCE. A
-- successful authentication has never been recorded at all.
--
-- So the audit table attributes REFUSALS precisely and attributes SUCCESSES not at all — and the
-- successes are the entire thing 9.5 is trying to drive to zero. The instrument measured the number
-- it needed and lost the name attached to it. I could tell the founder the counter had moved and
-- not tell him what moved it, which is worth about as much as not knowing it had moved.
--
-- THE FIX, deliberately narrow: record every ALLOWED use of a LEGACY credential. Scoped credentials
-- are not recorded — email_cron alone is 34 uses in an hour, and a row per internal call would turn
-- an audit trail into a firehose and bury the thing worth seeing. Legacy uses are the ones that are
-- supposed to be rare and heading to zero, so each one deserves a row with a name on it.
--
-- This matters for exactly one week. On withdrawal day the shared secret goes and this branch stops
-- firing on its own.
create or replace function public.fn_internal_auth(p_secret text, p_function text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare c public.internal_credential;
begin
  if p_secret is null or length(p_secret) = 0 then
    insert into public.internal_credential_audit (function_name, reason, allowed)
    values (p_function, 'no_credential_presented', false);
    return jsonb_build_object('ok', false, 'error', 'no_credential');
  end if;

  select * into c from public.internal_credential
   where secret_hash = encode(extensions.digest(p_secret, 'sha256'), 'hex')
     and active and retired_at is null
     and (expires_at is null or expires_at > now())
   limit 1;

  if not found then
    insert into public.internal_credential_audit (function_name, reason, allowed)
    values (p_function, 'unknown_credential', false);
    return jsonb_build_object('ok', false, 'error', 'unknown_credential');
  end if;

  if not (c.scope @> array['*'] or p_function = any (c.scope)) then
    insert into public.internal_credential_audit (function_name, reason, allowed, credential_id, context)
    values (p_function, 'out_of_scope', false, c.id, c.context);
    return jsonb_build_object('ok', false, 'error', 'out_of_scope', 'context', c.context,
      'message', 'The ' || c.context || ' credential is not scoped to call ' || p_function || '.');
  end if;

  update public.internal_credential
     set use_count = coalesce(use_count, 0) + 1, last_used_at = now(), last_function = p_function
   where id = c.id;

  -- THE NEW PART. Only for legacy: a named record of every remaining use of the shared secret, so
  -- "the counter moved" always comes with "and here is what moved it".
  if c.is_legacy then
    insert into public.internal_credential_audit (function_name, reason, allowed, credential_id, context)
    values (p_function, 'legacy_secret_used', true, c.id, c.context);
  end if;

  return jsonb_build_object('ok', true, 'context', c.context, 'credential_id', c.id,
                            'legacy', c.is_legacy, 'scope_all', c.scope @> array['*']);
end $fn$;

create or replace view public.v_legacy_secret_users as
select function_name, count(*) as uses, min(at) as first_seen, max(at) as last_seen
  from public.internal_credential_audit
 where reason = 'legacy_secret_used'
 group by function_name order by count(*) desc;
comment on view public.v_legacy_secret_users is
  'Who is still presenting the shared secret, by name. Empty until the next legacy use after '
  '3 Aug 2026 16:30 UTC — before that the audit table recorded refusals and issuances but never a '
  'successful authentication, so a moving counter had no name attached to it.';;
