---
name: founder-plan-audit-then-llm-then-full-test
description: "The founder's plan of 22 Sep 2026 (instr 760) — finish in-flight work, laptop restart, deep audit of everything + code structure, then LLM per seat + OpenRouter on, then a full feature test run"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-22T12:37:25.732Z
---

The founder's plan, 22 Sep 2026 (instruction 760), in order:

1. **Finish in-flight work.**
   - #840: WhatsApp delivery receipts. Fix the hard-coded project ref, then review, apply and merge. After that, set the Twilio sender status callback to https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/wa_status.
   - The WhatsApp signature fix plus the welcome/menu PR (branch `customer_support/whatsapp-answers-every-hello`). Then ask the founder to send "hi" again to prove it end to end.
   - Then tell him: **"good to go, restart your laptop."** His laptop is laggy, so no big fan-out before the restart.
2. **After the restart: the deep audit.** It must give a confirmation on everything, with a measurement behind each answer and never a claim:
   - Missing tasks per seat; is the wiring perfect; is each agent good enough, and can every agent do all its tasks.
   - Website, customer portal and supplier portal.
   - Connection issues, interruptions and timeout rules: edge CPU and wall caps, the PostgREST 8 s limit, and rate limits.
   - All PDF templates on the QuotesDone template; the Arabic email fixed; professional English and native formal Gulf Arabic everywhere.
   - Every unsolved issue.
   - Meta, Twilio and Postiz settings.
   - Email deliverability: inbox, not spam (mail-tester, SPF/DKIM/DMARC).
   - **Code structure:** organised as a senior engineer would build it, easy to find and fix bugs. This is for the investor pitch; see [[code-extremely-well-built]].
   - Fix everything the audit finds.
3. **Then:** the founder sets the LLM for each seat (plans A/B/C; see [[next-phases-marketing-then-llm-per-seat]]), and OpenRouter is opened.
4. **Then a second full audit and test.** Every feature is exercised with the LLM on:
   - many types of inquiries: with a BOQ, with drawings, with neither;
   - voice notes;
   - every flow, end to end.

**Why:** he will pitch to investors and needs certainty about what he has.

**How to apply:**
- Keep this order.
- Keep fan-out light until the restart.
- Use worktrees only for builders, and delete each one on merge.
