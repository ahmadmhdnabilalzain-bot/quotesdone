# The customer-support agent

The founder, 8 September 2026: *"the chat widget on home screen belongs to customer support agent."*

One agent, several channels. The home-page widget (`site_assistant`), WhatsApp (`wa_inbound`), and
email (`inbound_email`, `resend_inbound`, `email_triage`, `send_outbox`) are all the same seat
answering on different doors — not different agents.

## What it is responsible for

**Answering the public.** Anyone on the home page can talk to it. It answers from
`v_support_corpus` — one body over the FAQ, the support pack and operations knowledge, 10,031 rows,
of which 249 are publicly quotable.

**Receiving documents.** A trade licence can arrive by email or through the portal, and a stranger
claiming an account must prove it is theirs. `fn_support_open_identity_challenge` sends the code to
the address ON THE ACCOUNT, and gives an identical answer whether or not the account exists — no
enumeration oracle.

**Escalating to the CEO.** `fn_support_report_to_ceo`, which resolves the recipient through
`org_reporting_edge` and refuses to send if there is no active reporting parent. Escalation goes to
the CEO seat. Never to the founder.

## What it must never do

- **Quote internal knowledge to a public visitor.** Most of the corpus is internal — estate
  architecture, escalation mechanics, founder decisions. `fn_support_corpus_search` takes `p_public`
  as a **required argument with no default**, so the call site has to state that it is answering a
  stranger. That control is in the function signature on purpose: putting it in the prompt would make
  the model responsible for not leaking, which is not a control.
- **Break anonymity.** A supplier must not learn who the customer is, and a customer must not learn
  the supplier's identity, before a paid reveal. That anonymity is the product.
- **Claim an escalation it did not make.** Its own knowledge pack pins this: never say you escalated
  something without tool evidence that you did.

## What is broken or missing today, measured

- **WhatsApp's founder branch 404s.** `wa_inbound` POSTs to an edge function `agent_brain` that is not
  deployed and is not in the repository. Everything else on that channel works.
- **No model.** Every route in `llm_route_health` is held until 2126 by the founder's own hold, so the
  widget answers deterministically from the corpus or falls back to the contact line. It answers real
  questions — the pack is doing the work a model would otherwise be paid for.
- **No Arabic.** The FAQ and the support pack are 100% English. 172 Arabic rows exist in the corpus
  but all are internal, so an Arabic visitor on `/ar` gets the contact line. The site ships bilingual;
  the knowledge does not.
- **The signed-in assistant is a DIFFERENT agent and does not exist.** A logged-in customer asking
  "where is my quote for inquiry 412", or a supplier asking why their licence was rejected, is nobody's
  job today. The founder's own words, 8 September: *"once someone logs in either as a customer or
  supplier that is another agent which we will build later."*
