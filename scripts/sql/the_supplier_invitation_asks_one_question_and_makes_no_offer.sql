-- THE SUPPLIER INVITATION ASKS ONE QUESTION AND MAKES NO OFFER (it_engineer, 27 Oct 2026). Variant A.
--
-- Assigned: it_engineer. The founder delegated the choice of copy on 27 Oct 2026 ("approved. dont ask me", relayed by
-- the coordinator). MEASURED the same day: GlockApps id:2026-10-27-09:33:53:634t placed the previous text in Junk at 18
-- of 18 Microsoft seeds, with SPF, DKIM (selector1, d=quotesdone.com) and DMARC passing and the sending IP and the
-- domain on no blocklist. That previous text carried an offer list ("What you get", "Free registration for our first
-- 1,000 suppliers", "No commission", "To join, register at quotesdone.com"). Variant A keeps every standing rule (no
-- link and no domain written out, English only, never the word AI, the QuotesDone Technologies signature, the reply-stop
-- line last) and drops every offer phrase. It is about 80 words and asks one question a supplier answers by replying.
-- Full evidence: docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md
--
-- WHAT THIS CHANGES, EXACTLY. The Microsoft 365 lane and the Resend fallback build the email in code
-- (send_outbox/m365_lane.ts campaignMail -> m365InvitationText / m365Subject), not from these two keys. The keys feed
-- the queued rows (fn_supplier_invite_candidates), the gap recruitment plans and the daily placement seed. They are
-- kept equal to the code so nothing stored describes an email that is not sent:
-- scripts/checks/the_supplier_invitation_carries_no_link.test.mjs fails if this body and m365InvitationText drift apart.
--
-- ROLLBACK: the previous values are written by the update block of
-- scripts/sql/the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql
-- (invite_subject 'Quote requests in the UAE'; invite_body the "What you get" text), and quoted in full in the report.
--
-- Data only, no DDL. invite_enabled and wa_supplier_invite_golive are not touched and read 'false'.

update public.app_secrets set value = $body$Hi {{company}} team,

I'm Ahmad, founder of QuotesDone in Dubai. QuotesDone is a platform where companies in the UAE post requests for quotation, and each request goes only to suppliers who work in that exact trade.

We are putting together our list of suppliers now, before buyers start sending requests. Would your company like to receive the requests that match your trade when they come in?

Best regards,
Ahmad Alzain
Founder, QuotesDone
QuotesDone Technologies · Dubai, UAE

If this isn't relevant, reply "stop" and we won't contact you again.$body$, updated_at = now()
 where key = 'invite_body';
update public.app_secrets set value = 'A question about your work in the UAE', updated_at = now() where key = 'invite_subject';

-- verdict row: the read-back is the new copy, it breaks no copy rule the builders enforce, and both switches read false
select case
  when (select value from public.app_secrets where key = 'invite_subject') is distinct from 'A question about your work in the UAE'
    then 'PROBE FAILED: invite_subject did not read back'
  when (select value from public.app_secrets where key = 'invite_body') not like 'Hi {{company}} team,%Would your company like to receive the requests that match your trade when they come in?%'
    then 'PROBE FAILED: invite_body did not read back'
  when (select value from public.app_secrets where key = 'invite_body') ~* '(https?://|www\.|\{\{link\}\}|quotesdone\.com|al furjan|NOL-|\mfree\M|\mjoin\M|\mregister\M|commission|1,000|\mAI\M)'
    then 'PROBE FAILED: the stored body carries a link, the domain, an offer phrase or the forbidden word'
  when (select value from public.app_secrets where key = 'invite_body') !~ 'reply "stop" and we won''t contact you again\.$'
    then 'PROBE FAILED: the stop line is not last'
  when (select value from public.app_secrets where key = 'invite_enabled') is distinct from 'false'
    then 'PROBE FAILED: invite_enabled is not false'
  when (select value from public.app_secrets where key = 'wa_supplier_invite_golive') is distinct from 'false'
    then 'PROBE FAILED: wa_supplier_invite_golive is not false'
  else 'PROBE OK' end as verdict;
