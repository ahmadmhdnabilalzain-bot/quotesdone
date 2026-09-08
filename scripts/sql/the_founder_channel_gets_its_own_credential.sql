-- A SCOPED CREDENTIAL FOR THE FOUNDER'S COMMAND CHANNEL.
--
-- ceo_agent is deployed and refuses every caller, which is correct and is why this file exists. The
-- shared `inbound_secret` no longer authenticates anything: every live caller in
-- public.internal_credential holds a scoped credential naming the exact functions it may call, and
-- `ceo_agent` is on nobody's scope.
--
-- WHY A NEW ONE RATHER THAN WIDENING AN EXISTING SCOPE. The obvious shortcut is to append 'ceo_agent'
-- to `action.invoker`, which already lists 34 callees. That credential is held by the generic action
-- worker; giving it the founder's command channel would mean any compromise of the action pipeline
-- could submit instructions AS THE FOUNDER. The channel that carries his instructions gets its own
-- credential, so a leak is scoped to it and the log names it rather than saying "something with the
-- shared secret".
--
-- THE SECRET VALUE NEVER LEAVES THE DATABASE. It is generated here by gen_random_bytes, hashed by
-- fn_internal_credential_hash (HMAC-SHA256 under internal_credential_hmac_key), and the plaintext is
-- written to app_secrets under the key the callers read — the same shape as every other
-- `cred_*` entry. It is not in this file, not in the repository, and was never in a chat window.
-- That is deliberate: the Twilio token that passed through a chat on 8 September had to be rotated
-- afterwards, and the fix for that class is to never let a secret take that path in the first place.
--
-- IDEMPOTENT BY CONFLICT, NOT BY REGENERATION. Re-applying must not mint a second secret and leave
-- the callers holding the first: if the context already exists this file leaves it exactly as it is.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_channel_gets_its_own_credential.sql --apply --ddl

begin;

do $mint$
declare
  v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.founder_channel') then
    raise notice 'fn.founder_channel already exists — left untouched';
    return;
  end if;

  v_secret := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values (
    'fn.founder_channel',
    'The founder''s command channel — WhatsApp, email and the API reaching the CEO seat',
    public.fn_internal_credential_hash(v_secret),
    array['ceo_agent'],
    false,
    true
  );

  insert into public.app_secrets (key, value)
  values ('cred_fn_founder_channel', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

commit;
