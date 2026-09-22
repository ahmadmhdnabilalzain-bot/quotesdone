-- THE SOCIAL SWITCHES EXIST BEFORE THE CODE READS THEM (customer_support, 22 Sep 2026, INT-06)
--
-- MEASURED 22 Sep 2026: supabase/functions/marketing_social_inbox/index.ts reads three app_secrets
-- keys that HAVE NO ROW — social_send_enabled, social_model_enabled and meta_app_id (full key list
-- read from public.app_secrets; none of the three is present).
--
-- The function is written to survive that, and it does: `(await sec('social_send_enabled')) !== 'on'`
-- is true for a missing key exactly as it is for 'off', so a reply is held with send_status
-- 'held_switch_off' either way. THAT is the problem. A missing key and a deliberate 'off' are the
-- same behaviour and a different fact, and only one of them is a decision anybody made. Read the
-- store and you cannot tell whether social sending is held because the marketing seat decided so or
-- because nobody ever wrote the row — and a key that appears for the first time when somebody sets
-- it to 'on' is a switch with no off position in its own history.
--
-- VALUE FORMAT IS THE CODE'S, NOT A NEW CONVENTION. Both switches are compared with `!== 'on'`
-- (marketing_social_inbox/index.ts lines 151 and 203) and scripts/marketing/connect_social_inbox.mjs
-- prints `send === 'on' ? 'on' : 'off'`. So 'off' is the written form of the off position, not
-- 'false'; writing 'false' here would read as off and say the wrong thing.
--
-- meta_app_id is not a switch and not a secret: it is the public Meta app id (it is in every
-- browser that loads a Meta SDK). marketing_social_inbox uses it only to recognise our own
-- Messenger echoes, so without it the seat can mistake its own outbound message for a customer's.
--
-- ON CONFLICT DO NOTHING throughout: if the marketing seat has already set any of these, this file
-- must not walk over the decision. That makes it safe to re-apply.

insert into public.app_secrets (key, value) values
  ('social_send_enabled',  'off'),
  ('social_model_enabled', 'off'),
  ('meta_app_id',          '1778791833261376')
on conflict (key) do nothing;
