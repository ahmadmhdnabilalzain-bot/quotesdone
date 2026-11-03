-- INVITATIONS NEVER GO TO YAHOO OR MICROSOFT MAILBOXES (sales_engineer, 3 Nov 2026; founder_instruction 1537).
--
-- The founder, 3 Nov 2026: "invitations exclude yahoo and microsoft". Until now that held only because the latest
-- GlockApps verdict failed both classes (test 2026-10-27, fn_invite_placement_judge: microsoft and yahoo_aol
-- "fail:below_bar", open_providers ["google"]). A passing re-test would have reopened them. Measured 3 Nov: 0 of the
-- 92 invitations of the 8 days before went to either class; 2,390 not-yet-invited leads are on yahoo/ymail/rocketmail/
-- aol/hotmail/outlook/live/msn domains.
--
-- WHAT CHANGES. fn_invite_placement_open_providers is the one list every SQL caller reads when an invitation is
-- QUEUED: enqueue, the nudges, the invite batch, the CEO's target and the resumed-day release (send_outbox has no
-- provider check, so this acts at queue time; measured 3 Nov: the 38 queued invitations are all google). It now never contains
-- 'microsoft' or 'yahoo_aol', whatever the verdict. The classes are fn_mail_provider_of_email's (the first cached MX
-- host, then the domain), the same ones the gate already used, so a company whose mail is hosted by Microsoft 365
-- stays excluded as it is today. Nothing else moves: Google and other providers still follow their verdict.
--
-- To reopen a class, the founder rules it and this list changes. No setting can reopen it.
--
-- Prevented by: the probe below (always raises, rolled back), and the static check in
-- scripts/checks/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.test.mjs.

create or replace function public.fn_invite_placement_open_providers(p_day date default null::date, p_now timestamp with time zone default now())
returns text[] language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- founder_instruction 1537 (3 Nov 2026): never Yahoo/AOL or Microsoft, whatever the GlockApps verdict says
  return array(select p from jsonb_array_elements_text(public.fn_invite_placement_judge(p_day, p_now) -> 'open_providers') p
               where p not in ('microsoft', 'yahoo_aol'));
end $fn$;
revoke execute on function public.fn_invite_placement_open_providers(date, timestamp with time zone) from public, anon, authenticated;
