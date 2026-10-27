# Customer-chat model comparison 2: does a "complete answer" instruction close the gap? (13 Oct 2026, sales_engineer)

## Status: incomplete. The answers are measured, but the Opus judging was not finished.
The USD 3 cap was reached during Opus judging (spent USD 2.88; the script stops at cap minus 0.15).
The script holds the judge scores in memory and writes them only after all 30 questions, so the
partial Opus scores (about USD 0.64 of judging) were lost. **No quality scores out of 10 exist for this run.**
I have not estimated or invented any.

## Method
- Script: copy of `scripts/kb/brief_quality_test.mjs` (the 12 Oct comparison, ledger 1198), in the session scratchpad at `mc2/mc2.mjs`.
  Same 30 questions (`scripts/kb/brief_quality_questions.json`, 15 EN and 15 AR) and the same compiled brief as the system prompt.
- Changes: the judge is `anthropic/claude-opus-5.5` (it was gemini-3.8-flash). The `rehearsal_window` insert and update are removed,
  so the run made no production writes. max_tokens is 1500 (it was 900).
- "+complete" candidates add this instruction: answer completely, like a senior expert, typically 300-500 words where the question needs it, and keep simple questions short.
- Costs come from OpenRouter's `usage.cost` for each call. USD per 1k counts only replies after the first, cache-writing call.

## Results (30 answers per model, 0 errors)
| Model | Opus score /10 | Avg output tokens | Median latency | USD per 1,000 replies | Run cost | Hit 1500-token limit |
|---|---|---|---|---|---|---|
| GPT-6 Luna + complete | not judged | 283 (earlier run: ~214) | 4.5 s | 0.72 | 0.028 | 0 |
| Haiku 5.5 + complete | not judged | 1,309 | 8.5 s | 1.57 | 0.057 | **14 of 30** |
| Gemini 3.8 Flash | not judged | 534 | 7.7 s | **47.30** (brief not cached) | 1.418 | 0 |
| GPT-5.6 Luna | not judged | 150 | 2.6 s | 1.32 | 0.053 | 0 |
| Sonnet 5.5 (baseline) | not judged (earlier run: 9.73) | 654 | 6.4 s | 15.80 | 0.687 | 1 |

## What the measurements show without scores
- **Luna ignores the length instruction.** Average output rose only from ~214 to 283 tokens, and the "Keep replies chat-length" line in the preamble still applies. The instruction alone does not make Luna's answers complete.
- **Haiku overcorrects.** It averages 1,309 tokens and hit the cap on 14 of 30 answers, so those replies are cut off mid-answer. As tested, that is unusable for chat. The instruction needs a hard ceiling, for example "at most 400 words".
- **Gemini 3.8 Flash costs about 3x Sonnet per reply** here, because OpenRouter did not cache the 29k-token brief for it. Gemini is not a cost-saving option unless caching works for it.
- **GPT-5.6 Luna** is the shortest and fastest, at 150 tokens, the same shortness that cost Luna its score in the first run.

## Side-by-side example (en04)
**Q:** I paid to reveal a supplier 4 working days ago and he hasn't replied. What happens now and will I get my money back?

**Luna + complete (282 tokens):**
> The process runs from your payment date, excluding UAE public holidays. On working day 3, QuotesDone chases the supplier and copies you. On working day 5, the case goes to the CEO for a final decision. If the supplier still has not responded, the full amount you paid is refunded, with nothing deducted; refunds are not automatic. Banks usually take 7–14 working days to show the refund. You can copy supplier@quotesdone.com when contacting the supplier to record your attempt.

**Sonnet 5.5 (814 tokens):**
> You're on working day 4, so the process is already running without you doing anything:
> - **Day 3:** QuotesDone chases the supplier and copies you. That should already have gone out, so check your email.
> - **Day 5 (the next working day):** if there's still no response, your case goes to QuotesDone's CEO for a final call.
> - **If the supplier still hasn't responded:** everything you paid is refunded, with nothing deducted. Banks usually take 7-14 working days to show it.
>
> I can't promise the outcome, because every refund is decided by the CEO and you'll get a refund case reference. The refund only applies if the supplier truly hasn't responded. A reply by any means, including WhatsApp or a call, counts as a response, so check those channels too.
>
> You can also message the supplier yourself and copy **supplier@quotesdone.com** to put your attempt on record. If you haven't seen the day-3 chase, write to management@quotesdone.com or call +971 50 931 9355 (Mon-Fri, 9am-6pm).

Both answers state the same facts. Sonnet adds what Luna leaves out: it places the customer on day 4, tells him the day-3 chase should already be in his inbox, says a WhatsApp reply or a call counts as a response, and gives him an escalation contact.

## To finish
Re-judge the saved answers without buying them again: `node mc2/mc2.mjs --out mc2/out --judge-only --cap 1.2`.
Opus judging costs about USD 0.9-1.1 for 30 questions. This needs about USD 1.2 more, beyond the USD 3 cap.
Suggested: first rerun Haiku with "at most 400 words" (about USD 0.06), so the judge sees Haiku answers that are not cut off.
Answers: `C:\Users\Opera\AppData\Local\Temp\claude\C--Users-Opera-quotesdone\8c4972a3-8a16-4cb0-a308-31a4f45e00bb\scratchpad\mc2\out\answers.json`.

## Run 4, 13 Oct: GPT-6 Luna Pro and GPT-6.1 Sol Pro
Setup: the same 30 questions (15 EN, 15 AR), the same compiled brief as the system prompt, no extra instruction, a 2,000-token reply cap, and Opus 5.5 as judge with the run-3 rubric. Each model was judged alone, one answer per call, not side by side with the others. Cost is OpenRouter's billed `usage.cost`, which includes reasoning tokens.

| Model | Overall | English | Arabic | Accuracy | Helpfulness | Avg output tokens (of which reasoning) | Median latency | USD per 1,000 replies |
|---|---|---|---|---|---|---|---|---|
| Sonnet 5.5 (run 3) | 8.80 | | | | | | | 14.59 |
| GPT-6 Luna Pro | 8.20 | 8.47 | 7.93 | 9.03 | 7.83 | 801 (590) | 8.2 s | 7.54 |
| GPT-6.1 Sol Pro (13 EN answers only) | 8.31 | 8.31 | not measured | 9.08 | 8.15 | 336 (114) | 8.7 s | 134.48 |

- **Luna Pro** answered all 30, with none cut off. It scores 0.6 below Sonnet at about half Sonnet's cost. Its weak point is Arabic (7.93).
- **Sol Pro** costs about USD 0.13 per reply, 9x Sonnet. Only en01-en13 were bought before the spend ceiling stopped the run, so it has no Arabic score and no 30-question overall. At that price it is not a candidate for chat.
- Run spend: Luna Pro USD 0.63 and Sol Pro USD 2.05, USD 2.68 in total, which is USD 0.18 over the USD 2.5 cap. The Sol Pro re-judge pass reset the script's spend counter.
- Files: `scratchpad/mc2/out/answers4.json`, `judged4.json`, `summary4.json` (Luna Pro); `answers5.json`, `judged5.json` (Sol Pro).
