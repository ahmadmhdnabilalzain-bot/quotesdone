-- Observe / Control Mode is disarmed, on the founder's instruction, with the record.
--
-- His words, 15 Aug 2026: "Even that observer mode, I don't know who came up with it… Remove that
-- even."
--
-- WHERE IT CAME FROM, since he asked. Not from a conversation about hiring a CEO. It was added on
-- 2 Aug 2026 as "Phase 1.4" in an audit-hardening pass, and os_api's own comment states the
-- reasoning: fourteen actions that approve suppliers, resolve refunds and fraud, publish public
-- content, change agent prompts and send mail as the company, with no distinction between looking
-- and acting — "one stolen session or one mis-tap on a phone was enough". The intent was sound.
--
-- WHAT IT ACTUALLY DID, measured before disarming rather than argued:
--
--   Control Mode sessions opened, ever ............. 1   (4 Aug 2026)
--   actions ever permitted under a session ......... 1
--   actions DENIED for want of a session ........... 42
--     of those, management@quotesdone.com .......... 41   across 20 distinct actions,
--                                                         2 Aug 2026 → 12:07 TODAY
--     of those, someone.else@example.com ............ 1   an @example.com address, i.e. the
--                                                         hardening test written beside the
--                                                         feature, 2 Aug at 14:37
--
-- So in thirteen days it refused the owner forty-one times and a test fixture once, and let one
-- action through. It has never refused an unauthorised person, because none has ever tried. A
-- control whose entire measured effect is locking the owner out of his own company is not
-- protecting anything; it is the cost without the benefit.
--
-- The record also explains this morning. At 11:22:02 he sent an instruction into the Command
-- Console; Control Mode denied it — "no active Control Mode session". At 11:22:09 and 11:22:52 he
-- started two Control Mode challenges and NEITHER produced a session, because the code is
-- delivered over WhatsApp and WhatsApp refuses business-initiated freeform messages outside the
-- 24-hour window the recipient opens (Twilio 63016), which os_api already documents. He could not
-- get an OTP even when he tried. That is why he said he could not wait for one.
--
-- WHAT THIS DOES AND DOES NOT REMOVE.
--
-- It uses the rollback the system was BUILT with: fn_phase1_disarmed() reads the newest
-- disarm/rearm row from phase1_rollback_log, and fn_control_mode_require honours it at the top,
-- still writing an audit row for every action it lets through. Nothing is dropped, no gate is
-- deleted, and re-arming is one row.
--
-- Still in force after this file, and worth being precise about because "remove the limitation" is
-- not the same as "remove every control":
--
--   * Supabase authentication. os_api refuses a request with no valid session — 401.
--   * The admin allow-list. app_secrets.admin_emails, two entries.
--   * Full audit. os_audit_log for every mutating action, control_mode_audit for every gate
--     decision including the ones now allowed.
--   * The x-os-key preview key stays read-only and cannot reach any mutation.
--   * A refund still needs the founder personally — phase_c_refund_decision checks
--     phase_c_founder_identity, and that is independent of Control Mode.
--   * Founder-reserved matters still cannot be committed autonomously.
--
-- WHAT IS GIVEN UP, stated plainly: an admin session that is stolen or left open on an unlocked
-- phone can now send mail as the company, publish content, resolve a fraud case or approve a
-- prompt without a second factor. Every one of those is still recorded against the identity that
-- did it. That is the trade, it is the owner's to make, and he has made it on evidence.
--
-- TO RE-ARM:
--   insert into public.phase1_rollback_log (actor, tier, reason)
--   values ('<who>', 'rearm', '<why>');
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

insert into public.phase1_rollback_log (actor, tier, reason, detail) values (
  'management@quotesdone.com',
  'disarm',
  'Founder instruction, 15 Aug 2026: remove Observe/Control Mode. Measured first — 1 session ever, '
  || '1 action permitted, 42 denied, of which 41 were the founder himself across 20 actions and 1 '
  || 'was an @example.com test fixture. It has never refused an unauthorised person. This morning it '
  || 'blocked his Command Console instruction at 11:22:02 and both attempts to open a session failed '
  || 'because the WhatsApp OTP cannot be delivered outside the 24-hour window (Twilio 63016). '
  || 'Authentication, the admin allow-list, full audit, the read-only preview key, founder-only '
  || 'refunds and founder-reserved boundaries all remain in force. Re-arm with a tier=rearm row.',
  jsonb_build_object(
    'sessions_ever', 1,
    'actions_allowed_under_control', 1,
    'actions_denied_total', 42,
    'actions_denied_founder', 41,
    'actions_denied_test_fixture', 1,
    'first_denial', '2026-08-02T14:35:41Z',
    'last_denial', '2026-08-15T12:07:20Z',
    'otp_delivery_blocked_by', 'Twilio 63016 — WhatsApp freeform outside the 24h window',
    'still_in_force', jsonb_build_array(
      'supabase_authentication', 'app_secrets.admin_emails allow-list', 'os_audit_log',
      'control_mode_audit', 'x-os-key preview key remains read-only',
      'founder-only refund decision', 'founder-reserved boundaries'),
    'given_up', 'a stolen or unattended admin session can mutate without a second factor; still fully attributed',
    'rearm', 'insert into public.phase1_rollback_log (actor, tier, reason) values (…, ''rearm'', …)')
);
