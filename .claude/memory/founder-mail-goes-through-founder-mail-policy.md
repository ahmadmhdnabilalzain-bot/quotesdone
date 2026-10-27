# Founder mail goes through founder_mail_policy (6 Sep 2026)

Founder's order: "so many errors were sent to me from the engine." 30 days measured: 242 emails to him, ~30 his
(brief, reports, money); the rest a department's work sent by 20+ routines each with its own dedupe idea.

The mechanism now (branch founder-gets-exceptions-only, scripts/sql/the_founder_is_emailed_exceptions_only.sql):
- `public.founder_mail_policy(kind, allowed_to_email, reason, owner_role)` — 17 allowed (founder_brief, reports,
  refund_*, spend_approval_needed, finance_alert, ledger_imbalance, stripe_webhook_failed, unexpected_charge,
  platform_down, uptime_alert, backup_failed_after_retry, security_critical), 41 routed. Unlisted = routed to cto.
- `fn_notify_founder(p_event, p_detail, p_level, p_kind, p_dedupe_key, p_owner_agent)` returns jsonb; the 3-arg
  overload is GONE. Always pass `p_kind => '<registered kind>'` (CI: the_founder_is_emailed_exceptions_only.test.mjs).
- `fn_founder_mail_route(kind, subject, body, level, owner_agent)` opens ONE org_task per condition
  (signature = kind + subject with [TAG] stripped and digits → '#', ledger alert_signature watcher 'founder_mail');
  an open task is bumped (result->founder_mail->seen_count), a closed one lets the condition re-open.
- `a10_notifications_founder_mail_policy` BEFORE INSERT on notifications refuses (return null) every founder-bound
  email/WhatsApp row whose coalesce(kind, type) is not allowed, after routing it. `notifications.kind` column added.
- `alert_founder` edge fn is a shim over the rpc; pass `kind` in its body.
- The daily brief's WITH THE ORGANISATION lists routed counts/kinds — the only way routed traffic reaches him.

Traps met: a new BEFORE trigger must sort before trg_notifications_digest (name order); the probe must stamp
failure rows BEFORE its own rehearsal_window starts (fn_watch_failed_runs ignores rows inside a window); a
transport-truncated RAISE payload (2000 chars) needs one-letter keys; deploy_functions can serve a stale bundle
for a couple of probes — run verify_deploy_parity and redeploy the STALE ones.

Left as found (not mine, disclosed): cost_snapshot_* crons inactive since 16 Aug (so "AI credit low" stopped),
wa_flush/sms_flush inactive since 2 Sep + no founder_alert WhatsApp template (10 stale WA rows marked skipped).
