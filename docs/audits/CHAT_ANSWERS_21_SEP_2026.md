# The chat answers the question it was asked — 21 Sep 2026

Seats: **customer_support** (public website widget, `site_assistant`) and **sales_engineer** (portal
chat, `sales_engineer` + `fn_sales_assist`). Customer audit of 21 Sep 2026, findings 6, 7, 13, 21.
No model is called anywhere below; OpenRouter is on hold and stays on hold.

Measured on production (`htdblwldjkcgjvmqkbeh`) on 21 Sep 2026 by a scratch script (not committed)
that prints no key. The demo customer is `qd-founderdemo-cust1@example.invalid` ("ZZ DEMO Customer A
founderdemo a"), request 151768, one revealed quote (AED 25,920, exclusions line
`electrical fittings painting of walls scaffolding above 4m`), chat thread `open`.

## What was wrong

| # | Surface | Measured before |
|---|---|---|
| 13 | Public widget | 0/3 correct in EN, 0/3 in AR. A supplier-quoting FAQ for "how many quotes will I get?"; the "no sourced answer" refusal for "what does it cost?" and for all three Arabic forms. 2.4–5.3 s each. |
| 7 | Portal chat | The scaffolding question about the customer's own quote got five unrelated FAQs, printed with raw `[company_faq · FAQ · Marketplace · en]` tags (EN), and three fee FAQs (AR). 1.0–4.8 s. |
| 6 | Messages | After the paid reveal the row read "No chat open" and was a `div` with a click handler: no role, no keyboard path, no control saying you can write. |
| 21 | Latency | Portal reply was >2 min in the audit. `fn_sales_assist` itself answers in 53–101 ms; the wait was the gte-small embed warming up, which had no bound. |

## Before — the deployed functions

Public widget (`site_assistant`, no session):

| Question | ms | Reply (start) |
|---|---|---|
| how many quotes will I get? | 5331 | "You quote from your supplier portal. Enter an itemised quotation…" (supplier FAQ, wrong audience and wrong question) |
| what does it cost? | 5100 | "I do not have a sourced answer to that yet, and I will not guess at it…" (FAQ 30 holds the fee) |
| how long until I receive quotes? | 2404 | "…quotes themselves usually arrive within 3-5 working days." (the only one on topic) |
| كم عدد عروض الأسعار التي سأحصل عليها؟ | 3190 | "ليس لدي إجابة موثقة على ذلك حتى الآن، ولن أخمّن…" (refused; FAQ 604 holds it) |
| كم تكلفة الخدمة؟ | 2962 | the same refusal (FAQ 609 holds it) |
| كم يستغرق الحصول على عروض الأسعار؟ | 2673 | the same refusal (no Arabic row existed) |

Asked a second time a few minutes later, all six hit the per-visitor rate limit (614–674 ms) before
any answering code runs. That limit is unchanged and is not part of this fix.

Portal chat (`sales_engineer` action `assist`, signed in as the demo customer):

| Question | ms | answered / cited | Reply (start) |
|---|---|---|---|
| The quote excludes scaffolding above 4 m, but my ceilings are only 3.2 m — does that exclusion affect me? | 4814 (1020 on a second run) | true / `company_faq:624,169,9,30,167` | "Does a Dubai supplier cover Abu Dhabi as well? [company_faq · FAQ · Marketplace · en] It depends on the supplier…" |
| عرض السعر يستثني السقالات فوق 4 متر لكن ارتفاع الأسقف عندي 3.2 متر فقط، هل يؤثر هذا الاستثناء عليّ؟ | 1638 (968) | true / `company_faq:611,609,603` | "متى يتم تحصيل الرسوم؟ [company_faq · FAQ · Arabic · ar] عند خطوة الكشف فقط…" |

Messages (`messages_api` action `thread`, same session, request 151768 / supplier 126512): 969 ms,
HTTP 200, `chat_status: open`, `locked: false`, 1 message. The server side already opens the chat
on first touch. The portal list was the problem: it labelled the row "No chat open" and gave no
way in.

## After — this branch, on the same production data

### Public widget: the three common questions never reach ai_gateway

`routeQuestion` sorts each question into count, cost or timeline by the asker's own words, in EN and
AR. `pickFaq` then returns the approved FAQ whose **question** is that question, in the asker's
language. This runs before the model key is read and before `ai_gateway` is called, so a held
gateway (`circuit_open`) cannot refuse these questions. The input is the 173 approved public FAQs
read from production. The Arabic timeline row (903) comes from the pending data file.

| Question | routed | FAQ | Reply (start) |
|---|---|---|---|
| how many quotes will I get? | count | 13 | "Only the suppliers who can genuinely fulfil your job — usually a handful…" |
| what does it cost? | cost | 30 | "As a customer you pay only when you reveal a supplier: a 3% reveal fee…" |
| how long until I receive quotes? | timeline | 26 | "It depends on the job, but 3-5 working days is realistic…" |
| كم عدد عروض الأسعار التي سأحصل عليها؟ | count | 604 | "الموردون القادرون فعلياً على تنفيذ عملك فقط، وعادة عدد محدود…" |
| كم تكلفة الخدمة؟ | cost | 609 | "بصفتك عميلاً تدفع رسماً واحداً فقط: رسوم كشف بنسبة 3٪…" |
| كم يستغرق الحصول على عروض الأسعار؟ | timeline | 903 (pending) | "يعتمد ذلك على طبيعة العمل، لكن من الواقعي أن تصلك عروض الأسعار خلال 3 إلى 5 أيام عمل…" |

Routing took 0–1 ms in-process. On top of that is the single `company_faq` read the function already
did. A per-trade price question ("gypsum ceiling cost per sqm") is deliberately not routed here; the
price guide owns it. In the Arabic price guide, "لكل each" is now translated per unit.

### Portal chat: a question about the customer's own quote is answered from that quote

`answerFromOwnQuotes` reads only the caller's own quotes (scoped through `inquiries.customer_id`). It
names the supplier only where a `transactions` row proves the reveal was paid. It then answers from
the line the question is about and compares the threshold:

- **EN** (25 ms over 2 quotes): "On your quote for request 151768 ("False ceilings and gypsum cornice
  for a private villa in Khalifa City, Abu Dhabi") from ZZ DEMO Interiors gypsum founderdemo, AED
  25,920, the exclusions line reads: "electrical fittings painting of walls scaffolding above 4m".
  Your figure (3.2 m) is below the 4 m threshold in that line, so as written this does not apply to
  your case. That is the quote's own wording; anything it does not say I cannot confirm — ask the
  supplier through Messages after a reveal, or a clarification on the request."
- **AR** (1 ms): "في عرض السعر للطلب 151768 (…) من ZZ DEMO Interiors gypsum founderdemo، بقيمة 25,920
  درهم، الاستثناءات كما وردت: «electrical fittings painting of walls scaffolding above 4m». رقمك (3.2
  متر) أقل من حدّ 4 متر المذكور في هذا السطر، لذا كما هو مكتوب لا ينطبق هذا الاستثناء على حالتك. هذا
  ما كُتب في العرض حرفياً؛ وما لم يُكتب فيه لا أستطيع تأكيده — …"

The quote's own text is quoted exactly as the supplier wrote it, in English. It is not translated.

If the question is not about a quote, `fn_sales_assist` answers it. What it returns is then dropped
unless it shares a substantive word with the question (`onTopic`; a nearest neighbour on its own is
never an answer). The raw corpus tag is no longer printed. When nothing survives, the reply is the
honest sentence in the asker's language, with the gap task number:

- EN: "I don't have that yet, and I won't guess. I've logged your question as you wrote it for the
  sales engineer (task #N), and the answer will come back to you."
- AR: "ليس لديّ هذه المعلومة بعد، ولن أخمّن. سجّلت سؤالك كما كتبته ليتولّاه مهندس المبيعات (المهمة رقم N)، وسيصلك الرد."

The re-defined `fn_sales_assist` was run inside a transaction that was then aborted. Nothing was
written, and the deployed routine was read back unchanged afterwards:

| Question | ms | answered | cited |
|---|---|---|---|
| does a Dubai supplier cover Abu Dhabi as well? | 53 | true | "Does a Dubai supplier cover Abu Dhabi as well?" (on topic) |
| what warranty applies to gypsum works? | 75 | false | none (below_similarity_floor_and_lexical_bar) → honest sentence |
| the EN scaffolding question | 101 | false | none (no_candidates); the own-quote route answers it before this call |

**A defect found by that run, and fixed here.** The pending file's lexical-only `company_faq` arm
selected `f.id, f.question, …` from a subquery aliased `g`. The dry run (`apply_sql.mjs`) passed,
but the first call failed with `42P01 missing FROM-clause entry for table "f"`. Applied as written,
every portal question would have failed with `retrieval_failed`. The outer select now reads `g`.

### Speed

The gte-small embed now has a 1.5 s limit, so the audit's >2 min portal reply cannot happen again.
Without the embed the lexical route answers on its own. Server-side work measured on this branch:
0–1 ms for widget routing, 1–85 ms for the own-quote answer, 53–101 ms for `fn_sales_assist`. The
round trip through the deployed edge was 0.97–1.6 s once the function was warm (the first call was
4.8 s). The < 3 s target is met on the server-side work. Round trips with this branch deployed have
not been measured yet.

### Messages after the reveal

The server already returns `chat_status: open` for the paid pair, and the composer renders when the
status is `open`. Each conversation row is now a real button (`role="button"`, `tabIndex=0`,
Enter/Space). It carries an explicit **Open and write a message** / **افتح واكتب رسالة** control, and
a revealed but unopened row reads **Ready to message** / **جاهزة للمراسلة** instead of "No chat open".

## Recurrence checks

- `supabase/functions/_shared/chat_answers.test.ts` (deno test) replays the failing inputs: the three
  public questions in EN and AR, the per-trade price exception, the scaffolding question in EN and AR
  with the threshold, an absent warranty answered as absent, an off-topic passage rejected.
- `scripts/checks/the_chat_answers_the_question_it_was_asked.test.mjs` (node --test) checks the order
  that gets the right answer to a customer: widget routing before `cred_fn_ai` and before the gateway
  fetch; the own-quote answer before `fn_sales_assist`; the `onTopic` filter; no raw tag; the 1.5 s
  embed bound; "Ready to message" and the button row in Messages.
- `scripts/sql/the_sales_engineer_could_not_see_the_faq_and_an_arabic_question_arrived_as_question_marks.sql`
  probe c3 checks the FAQ arm when it is applied.

## Not measured / not changed

- The two SQL files are not applied and no function is deployed. The "after" numbers come from this
  branch's code run against production data, not from a deployed build.
- The per-visitor rate limit still comes before the deterministic route.
- The "What you may need next" (~30 s) and negotiation panels from finding 21 are outside this change.
- The "before" run left its normal traces on production: `assistant_logs` rows and any gap tasks
  that the deployed code records for a refusal.
