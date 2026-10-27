# Standing approval: merge and deploy reviewed PRs (27 Oct 2026)

**His words, 27 Oct 2026 about 14:30 UTC:** "Standing approval: merge and deploy reviewed PRs, don't ask me".

**What it covers.** A PR whose current head carries an independent reviewer's "Verdict: ready to merge", with
the local gate (`npm run gate`) showing only the known container failures, is merged, its SQL applied (with the
MANIFEST line and pending note removed) and its functions deployed, without asking the founder first. Report
afterwards, not before.

**What still goes to him.**
- Policy calls, for example what counts as a WhatsApp opt-in.
- Anything that sends to real suppliers or customers, for example turning `invite_enabled` on. Ledger 1312 still
  gates invitations on GlockApps Outlook ≥ 80% inbox.
- New spend.
- Anything that cannot be undone, for example purging data.

**What it does not lower.** Every PR still needs the independent review and the local gate. A PR changed after
its review needs a fresh review of the new commits before it merges.
