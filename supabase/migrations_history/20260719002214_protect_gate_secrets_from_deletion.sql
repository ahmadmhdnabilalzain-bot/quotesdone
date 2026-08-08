-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719002214   name: protect_gate_secrets_from_deletion
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Protect the app_secrets rows that edge functions use as AUTHENTICATION GATES.
--
-- WHY THIS EXISTS (19 Jul 2026):
-- Roughly 30 edge functions authenticate with the shape
--     if (body.__secret !== (await sec('inbound_secret'))) return 403
-- where the local sec() helper returns UNDEFINED when the key is absent from app_secrets.
-- If the inbound_secret row were ever deleted, `undefined !== undefined` evaluates to FALSE,
-- so a request carrying NO __secret field at all would be treated as authorised - on every one
-- of those functions at once. That set includes send_sms (arbitrary billable SMS), send_outbox
-- (flushes the mail outbox), retention_purge (deletes customer files), qa_mint (creates
-- confirmed auth users), dispatch_inquiry and route_inquiry.
--
-- Individually rewriting 30 functions is 30 opportunities to introduce a regression. This guard
-- instead removes the PRECONDITION: the gate rows cannot be deleted, nor set to null/blank.
-- Rotation is still allowed - update the value in place to a new non-empty value.
--
-- This is defence in depth, not a substitute for a correct gate. Functions touched individually
-- (ai_health, cost_snapshot, uptime_check, wa_inbound, match) now also check the stored secret is
-- truthy before comparing, which is the pattern the rest should adopt over time.

create or replace function public.fn_protect_gate_secrets()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Keys that are used as an authentication gate somewhere in the edge-function fleet.
  gate_keys text[] := array[
    'inbound_secret',
    'content_secret',
    'resend_inbound_token',
    'resend_webhook_key',
    'postiz_publish_key',
    'stripe_webhook_secret'
  ];
begin
  if tg_op = 'DELETE' then
    if old.key = any(gate_keys) then
      raise exception
        'app_secrets.% is a protected authentication gate key and cannot be deleted. Removing it would cause edge functions that compare (body.__secret !== sec(%)) to authorise unauthenticated callers, because an absent key and an absent field are both undefined. To rotate it, UPDATE the value in place instead.',
        old.key, old.key
        using errcode = 'raise_exception';
    end if;
    return old;
  end if;

  if new.key = any(gate_keys) and (new.value is null or length(btrim(new.value)) = 0) then
    raise exception
      'app_secrets.% is a protected authentication gate key and cannot be set to null or blank. A blank gate secret makes the comparison (body.__secret !== sec(%)) pass for callers sending an empty or absent secret. Set a non-empty value.',
      new.key, new.key
      using errcode = 'raise_exception';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_gate_secrets_del on public.app_secrets;
create trigger trg_protect_gate_secrets_del
  before delete on public.app_secrets
  for each row execute function public.fn_protect_gate_secrets();

drop trigger if exists trg_protect_gate_secrets_upd on public.app_secrets;
create trigger trg_protect_gate_secrets_upd
  before insert or update on public.app_secrets
  for each row execute function public.fn_protect_gate_secrets();
