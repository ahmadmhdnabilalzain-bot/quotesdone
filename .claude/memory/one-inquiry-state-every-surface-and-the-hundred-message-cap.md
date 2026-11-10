---
name: one-inquiry-state-every-surface-and-the-hundred-message-cap
description: 10 Nov 2026, ledger 1572. public.inquiry_state is the one state per inquiry conversation; the 100-message cap counts both sides; New request carries the portal job.
metadata:
  type: project
---
Founder ledger 1572 (10 Nov 2026): expert conversation until complete, Egyptian/Lebanese/Gulf dialects, **hard limit 100 messages per inquiry**, nothing said in message 2 forgotten by message 30+.

**What exists (phase 1, branch sales_engineer-inquiry-core):**
- `public.inquiry_state` (scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql), written only by `fn_inquiry_state_merge` / `fn_inquiry_state_carry`. Keys: `intake:<id>` (request chat), `<a-c-account>#<episode start>` (portal job; the episode moves only on a confirmed summary), `wa:<phone>`, the widget conv id. Code that reads it is `_shared/inquiry_state.ts`; every call answers null when the table is absent.
- **The cap counts every message, ours and theirs.** The reply about to be written is message N: from 80 ask only what is missing, from 95 summarise, at 100 the hand-off reply, past 100 nothing is sent (`capStage`). At the cap the request is held and `spec.not_sure` goes to sales_engineer (portal: `sales_engineer/lib/inquiry_cap.ts` writes the held request from the job's transcript).
- A spec in the state, or one the customer said they do not know (any dialect, `saysDontKnow`; the model's `unknown_keys`), is never asked again: exhausted at once in `slots.reconcileSlots`; the hold never re-asks it.
- Reply LANGUAGE is still the registered one (ruling 1008); the Arabic REGISTER follows the customer's dialect (`arabicRegister`), never for a supplier.
- Portal `SUMMARY_AFTER` now counts replies since a must-have was last given (a moving plan keeps asking).

**Why:** the audit found three surfaces sharing only the transcript, blank New request after a chat, no cap, three history windows.

**How to apply:** a new customer surface writes the state with `mergeState`; never add a history `slice` (scripts/checks/every_inquiry_conversation_keeps_one_state.test.mjs fails). Phase 2 (expert solutioning, solution catalogue) adds columns to this table, not a second store.
