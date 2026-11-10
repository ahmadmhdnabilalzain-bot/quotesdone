---
name: the-inquiry-agent-advises-like-an-expert-in-every-trade
description: 10 Nov 2026, ledger 1572/1579/1586. Diagnose -> advise -> qualify on the request chat, portal and WhatsApp; the whole 223-trade taxonomy places the job; the trade's pack drives the questions; the chosen option names the services matching uses.
metadata:
  type: project
---
Founder ledger 1572 (MDF partition -> PVC or wrap, ask budget and dimensions), 1579 ("only an example ... every trade, product and service"), 1586 (every UAE trade but food and beverage, location rules, never test the narrow case).

**What exists (phase 2, branch sales_engineer-expert-advice, stacked on phase 1):**
- `_shared/solution_catalogue.json` + `.ts`: 30 families x 61 problems x 169 options (135 distinct service keys over 44 taxonomy trades; 50 intake slugs), each option with taxonomy service keys; no price, figure, brand or supplier (the test fails on a digit). `ADVISE_RULE` is the one instruction all three surfaces give. Selection is BY TRADE and the held problem, never by the customer's words (ruling 890); with no trade, `problemIndex()`. The catalogue is seed knowledge, not the boundary: an option outside it is kept by its words with no service key.
- `_shared/inquiry_trades.ts`: the whole taxonomy (`taxonomy_trade`, cached), and for the job's codes their services, `trade_spec_checklist`, `authority_required` (3 trades) and the verified `kind:standard` pack entry (location rules). The request chat runs a trade's checklist as its slots when no category_specs slug covers it (`withPack`: first 6 specs required under `general`), so a bus rental is held until a bus can be quoted.
- `_shared/inquiry_reading.ts`: the portal/WhatsApp reader, one bounded json_extraction per customer turn, never awaited by the reply, writes trade_codes / options / choice / budget / service keys to the state.
- `inquiry_state` phase-2 columns (`condition`, `options_offered`, `chosen_option`, `budget`) in the phase-1 SQL file (both pending); service keys under `specs.service_keys`. `inquiry_create` copies `brief.service_keys` to `inquiries.service_keys` and adds `brief.trade_codes` to a single-trade request's trades.
- Job conversations on the portal and WhatsApp answer on `inquiry_qualification_conversation` (consumers listed by the pending `the_expert_inquiry_turns_on_the_portal_and_whatsapp_are_listed_model_consumers.sql`).

**Why:** the audit (A1 NOT MET) found "Do not pitch / do NOT lecture" in the intake prompt and only 25 of 223 trades reachable from the intake's 32 mapped slugs.

**How to apply:** a new trade needs no code: it has a pack and services. Add a catalogue family only for common problems; every option's keys must be seeded services (scripts/checks/every_solution_option_names_a_taxonomy_service.test.mjs). The real-model check is scripts/eval/expert_advice_eval.mjs (27 openings x 5 registers, all 12 groups; ~USD 13.6 on Sonnet). Not done here: trade adjacency in the matcher (audit G7), supplier-side licence check (G8).
