-- AUDIT 9.5 (3 Aug 2026): give unsubscribe links their own signing key.
--
-- THE PROBLEM. send_outbox signs every unsubscribe token as HMAC-SHA256 keyed on `inbound_secret`,
-- and `unsubscribe` verifies with the same key. Two consequences nobody had written down:
--
--   1. Withdrawing or rotating the shared secret invalidates every unsubscribe link in every email
--      ALREADY DELIVERED. Recipients clicking "unsubscribe" would get "invalid or expired".
--   2. send_outbox builds the link and the RFC 8058 List-Unsubscribe headers only `if (inbound)`.
--      Remove the row and supplier mail goes out with NO unsubscribe mechanism at all - worse than
--      a broken link.
--
-- Either one would have happened silently on the day the shared secret was withdrawn, which is the
-- whole point of audit 9.5. A scoped credential is the WRONG fix here: credentials are rotatable by
-- design, and rotatability is exactly what breaks a link that was printed into an email months ago.
--
-- THE FIX. Two purpose-scoped, long-lived keys, and `unsubscribe` never reads `inbound_secret` again:
--
--   unsubscribe_signing_key         - fresh 256-bit key. Signs every link from now on.
--   unsubscribe_signing_key_legacy  - a COPY of today's inbound_secret value. Verify-only, so links
--                                     already in recipients' inboxes keep working after the shared
--                                     secret row is deleted.
--
-- The legacy copy is deliberately a separate row rather than a reference: after this migration the
-- withdrawal of `inbound_secret` has no effect on unsubscribe at all. Retire the legacy key only
-- when it is accepted that no email older than that date will ever be opened again; there is no
-- automatic sunset, because guessing one wrong means silently breaking a compliance path.

do $$
declare v_shared text; v_new text; v_had_legacy boolean;
begin
  select value into v_shared from public.app_secrets where key = 'inbound_secret';

  -- Fresh signing key. Never overwrite an existing one: links signed with it are already in the wild.
  if not exists (select 1 from public.app_secrets where key = 'unsubscribe_signing_key') then
    v_new := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.app_secrets (key, value) values ('unsubscribe_signing_key', v_new);
    raise notice 'unsubscribe_signing_key: minted';
  else
    raise notice 'unsubscribe_signing_key: already present, left alone';
  end if;

  -- Verify-only copy of the value that signed every link delivered up to today.
  select exists (select 1 from public.app_secrets where key = 'unsubscribe_signing_key_legacy')
    into v_had_legacy;
  if v_had_legacy then
    raise notice 'unsubscribe_signing_key_legacy: already present, left alone';
  elsif v_shared is null or length(v_shared) < 8 then
    -- Fail loudly. Silently skipping the legacy copy is exactly how the old links would break.
    raise exception 'inbound_secret is missing or implausibly short, so the legacy unsubscribe key '
                    'cannot be captured. Every unsubscribe link already delivered would stop '
                    'verifying. Refusing to continue.';
  else
    insert into public.app_secrets (key, value) values ('unsubscribe_signing_key_legacy', v_shared);
    raise notice 'unsubscribe_signing_key_legacy: captured from inbound_secret';
  end if;
end $$;;
