# WI-001 — Replace the shared `inbound_secret` with purpose-specific scoped credentials

**Opened:** 2 August 2026, on founder instruction (Phase 1 hardening, final action 6)
**Priority:** P0 · **Status:** open · **Tracked in:** `spec_backlog` id 201, `spec_ref = 'WI-001'`
**Gate:** Phase 2 *shadow* development may proceed. **No broad production autonomy is activated until this is complete.**

---

## The problem, stated plainly

One string in `app_secrets.inbound_secret` authenticates:

- **146 cron jobs** (141 active) calling their edge functions
- `os_api` calling `secretary_act`, `extract_text`, `make_pdf`, `prompt_gate`, `gen_category_knowledge` and `knowledge_exam`
- `alert_founder` and `send_outbox` calling `send_whatsapp`
- every other server-to-server hop in the platform

So it is not a credential. It is *the* credential. Three consequences, in order of how much they should worry us:

1. **One disclosure is total.** Anyone holding that string can invoke any internal function as the platform: send mail as the company, dispatch knowledge work, run paid model calls, trigger WhatsApp sends. There is no scope to fall back on, because there is no scope.
2. **It cannot be rotated.** Changing it means changing every caller in the same instant. In practice that means it is never changed, which means its blast radius only grows with age.
3. **It cannot be attributed.** Every call authenticated by it looks identical in the logs. If it leaked, we could not tell which caller was real and which was not, and therefore could not scope an incident.

None of this is hypothetical or new — it was flagged in the July handover and again in the Phase 0 backend audit. It has survived two rounds of hardening because every round found something with a shorter path to harm. It now has nothing in front of it.

## Why it blocks autonomy specifically

Observe/Control Mode gates the **console**. `org_authority` gates **agent action classes**. Both assume the caller is who they say they are. `inbound_secret` is the assumption underneath both: a caller holding it is trusted by every internal function, without an identity, without a scope and without a mode.

Turning on broad autonomous execution multiplies the number of processes holding that string and the number of times a day it crosses a network boundary. Doing that before the separation is spending the one control that has no fallback.

## Proposed design

Not a rewrite. A rename with structure, done in one pass and verifiable at every step.

**1. One credential per calling context, not per caller.** Roughly a dozen contexts, not 146 — `cron.marketing`, `cron.finance`, `cron.supplier_lifecycle`, `os_api.internal`, `notifications.outbound`, and so on. Fewer than one per job (unmanageable) and far more than one for everything (today).

**2. Each credential declares what it may call.** A table — `internal_credential(key, context, allowed_functions[], created_at, rotated_at, expires_at, active)` — and a single verifier every function calls instead of comparing a string. A credential presented to a function outside its list is refused and audited, the same fail-closed shape as `fn_control_mode_require`.

**3. Rotation is a routine operation, not an event.** Two credentials valid per context during an overlap window; the verifier accepts both; the old one is deactivated when no call has used it for 24 hours. A runbook, and a view showing last-used-at per credential so a stale one is visible.

**4. Attribution comes free.** Every internal call records which credential authenticated it, so an incident can be scoped instead of guessed at.

**5. Migration order matters.** Add the verifier accepting both old and new (nothing breaks) → issue per-context credentials and move callers a context at a time, most privileged first → when `inbound_secret` has had no successful use for 7 days, refuse it → delete it. Each step is independently reversible, and the middle steps are observable rather than assumed.

## Acceptance

- No function accepts `app_secrets.inbound_secret`; the row is deleted.
- Every internal call authenticates with a context credential scoped to the function it invokes.
- A credential used against a function outside its scope is refused and audited — with a test that proves it, in the same suite as the action-classification checks.
- Rotating one context's credential is a single operation that breaks nothing else, demonstrated once end to end.
- A view shows, per credential: scope, last used, age, and whether rotation is due.

## Estimate and risk

Roughly two to three days of work. The risk is not difficulty, it is **breadth**: 146 cron jobs is 146 chances to typo a context name and silently stop a job. Hence the dual-accept window and the last-used-at view — every step must be observable before the previous one is withdrawn. The one thing not to do is a big-bang swap.

---

*Related: `docs/phases/PHASE1_REPORT.md` (Control Mode), `docs/phases/PHASE1_HARDENING_REPORT.md` (fail-closed gating), `docs/audit/backend-current-state.md` §8 (cron).*
