# Conversation quality, 3 Nov 2026 (customer_support)

Harness: `scripts/eval/conversation_quality.mjs` (code graders first; an independent judge for what code cannot grade).
Run: the live website widget (`site_assistant`, as deployed on 3 Nov 2026), scenario `villa_windows_sharjah`, 5 conversations
of 12 customer turns each (60 agent turns), every message `ZZ DEMO`, an anonymous visitor with a random conversation id.
Turns 9 to 12 of each conversation are the widget's capped sign-up reply (8 visitor messages per conversation).

Files:
- `conversation_quality_widget_2026-11-03T08-43-38-823Z.json`: conversation 1
- `conversation_quality_widget_2026-11-03T08-49-07-560Z.json`: conversations 2 to 5
- `judged.json`: the independent judge (16/16 agreement on the labelled calibration set) and what it flagged

Re-grade with today's graders: `node scripts/eval/conversation_quality.mjs grade --results <both files, comma-separated>`.
Replay this branch's code decisions on the same inputs: `node scripts/eval/conversation_quality.mjs replay --results <files>`.

## Measured, live widget, before this branch (60 agent turns, 5 conversations)

| measure | threshold | measured |
|---|---|---|
| unanswered turns | 0 | 0 |
| hallucinated company facts (code) | 0 | 3 turns: 2 "the detail was recorded" claims (تم تسجيل), 1 invented licence type and premises |
| hallucinated company facts (judge) | 0 | 6 turns: the same 3, plus 3 low-severity unsupported details |
| supplier identity leaks | 0 | 0 |
| wrong-language replies (customer) | 0 | 6 (5 at turn 4, a mixed English/Arabic message; 1 carried into turn 5) |
| wrong-language replies (supplier) | 0 | no supplier scenario ran on this surface |
| reply cites its own knowledge ("the brief doesn't give") | 0 | 1 |
| capped visitor asks for a person, no published contact | 0 | 4 of 5 |
| restatement accuracy | >= 99% | 15 of 15 (100%) |

Not run: the portal, WhatsApp (customer and supplier) and the supplier quotation thread need the management token,
which this session could not use (`SUPABASE_ACCESS_TOKEN` unset; reading credentials from the database was refused).
The widget allows 40 visitor messages per IP per day, so one scenario x 5 runs is that day's widget budget from one IP.

## Root causes found and fixed on this branch

1. Language: `chat_answers.langOf` treated any Arabic letter as an Arabic message. `turnLang` keeps the conversation's
   language for a mixed message (widget and portal). Replay on the same 60 messages: 5 to 0 messages given the wrong language.
2. Knowledge conflict: `knowledge/brief/company.md` said an inquiry can be edited within 24 hours. The product
   (`fn_edit_inquiry`, `customer_api` `EDIT_WINDOW_MS`) and the published FAQ say 1 hour. Both models' edit-window answers
   said 1 hour; the brief now says 1 hour too.
3. Invented premises: the brief had no statement about an office or address. It now says no address is published and
   there is no office to visit.
4. Reply guard: a reply citing "the brief" or "my sources" is refused for a rewrite (`support_reply_guard.ts`). Replay:
   the 1 such reply is now caught.
5. Capped person request: the cap rule said "give no number" and its facts held only the sign-up link. The rule and the
   facts now carry the published contact when a person is asked for.
6. "Recorded" claims: the visitor rules now say nothing written in the widget is recorded on a request.

Live "after" numbers need these changes deployed. That is done at merge, never before.
