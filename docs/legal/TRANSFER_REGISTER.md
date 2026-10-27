# Cross-border transfer register

Owner: **ceo** seat. Created 19 Oct 2026 for LEGAL_RISK_REVIEW_19_OCT finding 16. This file is the only
register of the providers that receive personal data from QuotesDone outside the UAE. Add a row when a
provider is added, and remove it when the provider is removed.

**Transfer mechanism (all rows).** Under UAE PDPL (Federal Decree-Law 45/2021) Art. 22, a transfer is
allowed to a country the Data Office has found adequate. No adequacy decision has been issued yet, so
every transfer below depends on Art. 23: contractual safeguards. In practice that means the provider's
DPA and the transfer clauses (SCCs or equivalent) it contains. "SCCs" below means only that the DPA text
we read refers to standard contractual clauses or transfer addenda. It does not mean a UAE-specific
clause was signed.

**Method.** Each DPA URL was fetched on 19 Oct 2026. "Read" means the page loaded and said it is a DPA.
"Not verified" means it did not. "Data processed" describes what the code sends or stores and is not a
contract term.

| Provider | Role | Region | DPA (public URL) | Read on | Transfer clauses in DPA | Data processed |
|---|---|---|---|---|---|---|
| Supabase | Database, auth, storage, edge functions (hosting) | ap-southeast-1, Singapore (from the session brief, not re-measured here) | https://supabase.com/legal/dpa | 19 Oct 2026, read | SCCs (cl. 12, Sched. 2) | All platform data: accounts, inquiries, quotes, messages, files, ledgers |
| Vercel | Website hosting, edge network | Global edge | https://vercel.com/legal/dpa | 19 Oct 2026, read | 2021 SCCs + UK IDTA (Scheds. 3, 5) | Request logs (IP, URL), page traffic |
| OpenRouter, and the model providers it routes to | LLM gateway | US (OpenRouter), then whichever provider serves the model | https://openrouter.ai/data-processing-agreement (incorporated by Terms §10.2) | 19 Oct 2026, read | SCCs Module 2 (§13.2) | Prompts and context passed to `ai_gateway`: inquiry text, chat messages, documents a seat reads |
| Resend | Transactional email, inbound mail | US | https://resend.com/legal/dpa | 19 Oct 2026, read | EU and UK SCCs (§§1.14–1.16, 6) | Recipient addresses, email bodies and attachments, inbound mail |
| Microsoft 365 | Company mailboxes (quotesdone.com app) | Microsoft tenant region | https://www.microsoft.com/licensing/docs/view/Microsoft-Products-and-Services-Data-Protection-Addendum-DPA | 19 Oct 2026, read (page loaded and is the DPA; the first 100k characters did not name SCCs, rest not read) | Not confirmed from the text read | Company mail with customers and suppliers |
| Meta (WhatsApp Business) | WhatsApp messaging | Meta data centres | https://www.whatsapp.com/legal/business-data-processing-terms | 19 Oct 2026, read (updated 22 Aug 2025) | Data Transfer Addenda referenced; SCCs not named in the text | Phone numbers, WhatsApp message content |
| Twilio | OTP / SMS / voice | US | https://www.twilio.com/en-us/legal/data-protection-addendum | 19 Oct 2026, read | EU SCCs (Sched. 3 §2.4) | Phone numbers, OTP and SMS content |
| Stripe | Payments | US / EEA | https://stripe.com/legal/dpa | 19 Oct 2026, read (UAE English version) | EEA SCCs (Decision 2021/914) | Payer name, email, card data (held by Stripe), payment records |
| Dropbox | File storage | US | https://assets.dropbox.com/documents/en/legal/dfb-data-processing-agreement.pdf (linked from https://www.dropbox.com/business_agreement) | 19 Oct 2026, title read ("Dropbox Data Processing Agreement"), body not readable by the fetcher | Not verified from the DPA. Privacy policy names SCCs | Files placed in the company Dropbox |
| Serper | Web search API | US | None found: https://serper.dev/terms has no DPA | 19 Oct 2026, **not verified** | None found | Search queries sent by seats (should not contain personal data) |

## OpenRouter: training and zero data retention (measured 19 Oct 2026)

- **What the code sends.** `supabase/functions/ai_gateway/index.ts` is the only caller of
  `https://openrouter.ai/api/v1/chat/completions` (git grep over `supabase/functions` and `src`). Its payload
  is `model`, `max_tokens`, `messages`, `usage: { include: true }`, the per-model shape from
  `_shared/request_shape.ts`, and optional `stream`, `plugins`, `tools` and `tool_choice`. **It sends no
  `provider` object.** No `data_collection: 'deny'`, no `zdr`, and no provider allow-list appear anywhere in
  `supabase/`, `src/` or `scripts/sql/` (git grep, case-insensitive).
- **What OpenRouter's terms say.** Terms §6.1 says OpenRouter has opted out of model training with the
  models it uses "where possible", and that some models may still train on inputs under their own terms.
  Zero data retention is an account setting (§§3, 6.3(b)).
- **Not measured here.** The account-level privacy settings in the OpenRouter dashboard (training opt-out,
  ZDR) were not read. Until they are read, or the gateway sends `provider: { data_collection: 'deny' }`
  (and `zdr: true` where wanted) on every request, **"no training on our data" is not established**.
