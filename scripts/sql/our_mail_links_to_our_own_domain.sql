-- customer_support, 22 Sep 2026. Founder instructions 633 and 635 ("do whatever to make sure we don't land
-- in junk or spam").
--
-- MEASURED: one real English and one real Arabic supplier invitation, sent through send_outbox -> Resend to
-- mail-tester.com (notifications#37424 and #37425), both scored 9.6/10: SPF pass, DKIM pass (d=quotesdone.com),
-- DMARC pass (p=quarantine), rDNS a9-156 / a14-42.smtp-out.amazonses.com, 0 of 20 IP blocklists, List-Unsubscribe
-- present, no broken links. The only point lost was SpamAssassin URI_NOVOWEL (0.5): the project host
-- "htdblwldjkcgjvmqkbeh.supabase.co" in the unsubscribe link and the logo URL reads as machine-generated.
--
-- CHANGES: send_outbox builds the unsubscribe link from unsubscribe_public_base and moves the brand
-- assets to email_asset_public_base (payload.ts ownDomain). quotesdone.com proxies both
-- (next.config.mjs rewrites /u/unsubscribe and /m/brand/*), so every link in the mail names our domain.
-- NOT CHANGED: the unsubscribe function, its signing keys and every link already delivered (the project URL
-- keeps working).
--
-- ORDER: apply ONLY after the site deploy carrying the rewrites is live, and after both of these answer:
--   curl -s -o /dev/null -w "%{http_code}" "https://quotesdone.com/u/unsubscribe?e=x%40example.invalid&t=x"   -> 400 (the function's "Invalid link")
--   curl -s -o /dev/null -w "%{http_code}" "https://quotesdone.com/m/brand/kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png" -> 200
-- Prevented by: supabase/functions/send_outbox/payload.test.ts (URI_NOVOWEL replay) and
-- `node --no-warnings scripts/invitation_inbox_check.mjs`, which FAILS on the live config until this is applied.

insert into public.app_secrets (key, value) values
  ('unsubscribe_public_base', 'https://quotesdone.com/u/unsubscribe'),
  ('email_asset_public_base', 'https://quotesdone.com/m/brand')
on conflict (key) do update set value = excluded.value;
