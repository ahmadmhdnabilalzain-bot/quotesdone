---
name: the-llm-understands-code-only-checks
description: "Founder rulings 1663, 1664, 1666 of 12 Nov 2026: wherever a document or a person has to be UNDERSTOOD (trade licence, company profile, the sales agent, any customer chat, the widget) the model reads and understands; code does not interpret first and never overrides it. 'Code first' was never the rule for these. The bar is the model's own app: attach the same file there and it reads it right, so where the platform reads worse the cause is what we put around the model."
metadata:
  type: feedback
  modified: 2026-11-12
---

**What happened (12 Nov 2026, ledger 1662).** The founder registered a real company of his own from his iPhone, the first
real phone test. The portal refused it: "This trade licence expired on 30 Oct 2026". The licence (Dubai Economy and
Tourism, the standard e-licence PDF) prints Expiry Date 29/10/2027 and Issue Date 30/10/2026. A code text parser had read
a wrong expiry off the licence's Commercial Register page, and the rule then in force kept any field code had read over
the model's. The model (openai/gpt-6-luna-pro) was asked and its issue date was stored, correctly; its expiry answer was
discarded in favour of code's and was not kept, so what it answered cannot be shown. No demo company had ever caught it.

**The founder, the same evening, verbatim:**
- 1663: *"But why should be there rules to how the layout of the trade license is? The AI should read it no matter what,
  even if the expiry date was in the bottom of the page."*
- 1664: *"And no, our rule is not code first in such thing. That's why we have LLM. Trade license reading, company profile
  reading, there's no code first, 100%. And sales age, any chat with customers, widget, anything like that, it's not code
  first. Otherwise, there are tons of issues that can come up."*
- 1666: *"there's no way that I will attach any PDF on the planet, a trade license for any country in the world … and GPT
  6.1 Luna Pro or whatever will mess it. These are very simple tasks for such model. … if I go now to ChatGPT, the app
  itself, and I pick the model and I attach any trade license, it will read it. … The same way I talk to you and you in a
  second you figured it out, that's how I'm expecting the platform to be."*

**Where the wrong rule came from.** `code-extremely-well-built.md` recorded his words of 14 Sep 2026 ("if something can
be coded then we do it") under the description "code first, LLM only where code can't", with "always with a
deterministic fallback", and without a limit. Sessions then applied it to reading documents and conversations; about
twenty files in `supabase/functions` state it. He never meant it there. That file now says so.

**How to apply (the session's reading of his rulings, labelled as its own):**
- Understanding is the model's: what a document says, what a supplier's profile means, what a customer or supplier wrote
  or said. Code does not classify free text by regex or keyword list, does not parse a document by its layout, and does
  not "correct" or move what the model understood.
- Code is for what must be exact or safe: sums of money, who may see or receive what, limits, duplicates, storage,
  routing by a fact already known (a stored emirate, a phone number, a button's fixed payload), and checking the model's
  answer against something certain (a catalogue key exists; one of seven emirates; an expiry is after its issue date).
- A check never blocks a real person on weak evidence. A PDF's text layer is itself unreliable (the founder's file had
  dropped Arabic letters), so "the model's value is not in the text" may at most leave a note for our own reviewer.
- When the platform does worse than the model's own app, look at what we wrap around the model before blaming it: code
  that overrides it, how the file is sent (the portal turned each PDF page into a picture and did not send the PDF), the
  prompt, the effort.
- Do not add a model call per message where the call that already writes the reply can also return the understanding.
  Speed is part of correctness.
- Evidence about "the model invents values" must name the model. The one incident on file (12 Oct 2026, a 1x1 image
  returned an expiry and the number 123456) was an older, smaller model and its log row is gone; it was wrongly offered
  to the founder as evidence against today's reader.

**The audit (12 Nov 2026):** `docs/reports/2026-11-12-llm-first-audit.md`. Nine places where code decided meaning over
or instead of the model, 20 where it pre-filtered, 24 legitimate. Related: [[code-extremely-well-built]],
[[a-paid-test-checks-only-what-changed]].
