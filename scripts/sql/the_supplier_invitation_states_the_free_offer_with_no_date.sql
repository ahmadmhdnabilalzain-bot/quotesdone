-- THE SUPPLIER INVITATION STATES THE FREE OFFER WITH NO DATE (5 Oct 2026; Assigned: marketing (copy)).
--
-- MEASURED (read-only, production, 5 Oct 2026; also seen in notifications#83961 sent that day): app_secrets.invite_body
-- still carried a bullet saying registration was free for all suppliers until a July 2027 date, with an annual
-- subscription of AED 1,000 from the next day, and the first 1,000 suppliers exempt. The founder's ruling of
-- 6 Sep 2026: no dates in the copy. The offer as ruled: free permanently for the first 1,000 supplier
-- registrations; AED 1,000 a year from the 1,001st.
--
-- WHAT THIS CHANGES: that one bullet of invite_body, replaced in place (every other word of the body is untouched).
-- The update is keyed on the old bullet's exact text, so re-running it, or running it after someone has already
-- reworded the bullet, changes nothing.
-- WHAT IT DOES NOT CHANGE: invite_subject, invite_preheader (already undated), invite_body_ar, the switches.
-- prevented by: invitation_copy.ts invitationCopyLint 'no date in the copy' (invitation_copy.test.ts replays the
-- old bullet), which scripts/invitation_inbox_check.mjs runs against the LIVE copy and the m365 lane runs before
-- every send; and the verdict row below.

update public.app_secrets
   set value = replace(value,
     $old$- Registration is free for all suppliers until 31 July 2027. From 1 August 2027 an annual subscription of AED 1,000 applies — but the first 1,000 suppliers to register never pay it. Register now and that is you.$old$,
     $new$- Registration is free permanently for the first 1,000 supplier registrations. From the 1,001st registration an annual subscription of AED 1,000 applies. Register now and that is you.$new$),
       updated_at = now()
 where key = 'invite_body'
   and position($old$until 31 July 2027$old$ in value) > 0;

select case
  when (select value from public.app_secrets where key = 'invite_body') ~* '\m(19|20)[0-9]{2}\M'
    then 'PROBE FAILED: invite_body still carries a year'
  when (select value from public.app_secrets where key = 'invite_body') ~* '\m(january|february|march|april|june|july|august|september|october|november|december)\M'
    then 'PROBE FAILED: invite_body still carries a month name'
  when position('first 1,000 supplier registrations' in (select value from public.app_secrets where key = 'invite_body')) = 0
    then 'PROBE FAILED: invite_body does not state the offer as ruled'
  else 'PROBE OK' end as verdict;
