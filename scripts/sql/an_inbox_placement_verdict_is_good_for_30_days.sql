-- AN INBOX-PLACEMENT VERDICT IS GOOD FOR 30 DAYS, NOT 7. Seat: sales_engineer, 2 Nov 2026 (the founder, 2 Nov: "focus on the
-- addresses that go to the inbox, ignore Microsoft, resume the invitations, all pending to be done").
--
-- MEASURED before writing: public.invite_placement_bar holds ONE row; its max_age is 7 days. That number is a session's
-- choice (it_engineer, when the gate was built: the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql),
-- NOT a founder ruling: ledger 1312 is only the Outlook 80% inbox bar. The only class open is google, on the GlockApps
-- test of 27 Oct 2026 09:33Z, so on a 7-day window the Google class goes stale at 3 Nov 22:50Z, fn_invite_placement_gate
-- answers fail:stale_verdict for every class, and enqueue_supplier_invites, the outreach tick and the nudges queue
-- nothing. Keeping it open on 7 days means a new GlockApps test every week: about 110 seeds that nobody answers, one
-- credit each, and seeds that never engage read pessimistically (docs/reports/MICROSOFT_YAHOO_PLACEMENT_PLAN_2_NOV.md,
-- actions 4 and 6).
--
-- WHAT THIS CHANGES: invite_placement_bar.max_age 7 days -> 30 days, and the reason is appended to note. Nothing else.
-- WHAT IT DOES NOT CHANGE: sender, microsoft_min_inbox_pct (80), google_max_spam_pct (20), google_min_delivered_pct (80),
-- yahoo_aol_min_inbox_pct (80); no routine; no campaign switch (invite_enabled stays the founder's own); the bounce
-- brake. Microsoft, Yahoo/AOL and other stay closed because their measured inbox rate is under the bar, which a longer
-- window does not touch. Only Google, measured 25 of 25 seeds delivered and 0 spam, stays open for longer.
-- The only reader of max_age is fn_invite_placement_class_verdicts (b.max_age); the rest read the percentage columns.
-- The column DEFAULT stays 7 days: it is read only by the insert that created the one row.
--
-- Idempotent: the note is appended once. Proved by an_inbox_placement_verdict_is_good_for_30_days_probe.sql and
-- scripts/checks/an_inbox_placement_verdict_is_good_for_30_days.test.mjs.

do $$
declare n integer;
begin
  update public.invite_placement_bar
     set max_age    = interval '30 days',
         note       = case when position('2 Nov 2026, sales_engineer: a verdict is good for 30 days' in note) > 0 then note
                      else note || ' 2 Nov 2026, sales_engineer: a verdict is good for 30 days, not 7. The 7 days was it_engineer''s '
                        || 'choice when the gate was built, not a founder ruling (ledger 1312 is only the Outlook 80% inbox bar). '
                        || 'The founder, 2 Nov: focus on the addresses that go to the inbox, ignore Microsoft, resume the invitations. '
                        || 'A weekly GlockApps test sends about 110 seeds nobody answers, and a seed that never engages reads '
                        || 'pessimistically. Only the time window changed: every percentage bar, the sender and the bounce brake '
                        || 'are as they were, and a class below its bar stays closed for the whole window.' end,
         updated_at = now(),
         updated_by = 'sales_engineer'
   where id;
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'invite_placement_bar has % rows, expected exactly 1 (is the gate file applied?)', n;
  end if;
end $$;
