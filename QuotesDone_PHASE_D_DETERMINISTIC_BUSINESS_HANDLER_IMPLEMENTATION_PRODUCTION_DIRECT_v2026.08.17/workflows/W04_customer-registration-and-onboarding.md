# W04 — Customer registration and onboarding

- **Domain:** customer
- **Criticality:** high
- **Profile:** case_workflow
- **Primary object:** `customer_account`
- **Accountable role:** `customer_onboarding_specialist`
- **Start event:** New invited/organic customer
- **Required end state:** Verified, accepted, usable customer account
- **Founder boundary:** Terms/policy remain founder-approved

## Purpose

Create a verified customer account with valid acceptance evidence and guide the customer to a usable first inquiry.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W04-S01` | Start customer registration | intake | `customer_onboarding_specialist` |  |  | `W04-S02` |
| 2 | `W04-S02` | Verify customer identity channel | review | `customer_onboarding_specialist` | lifecycle_channel_operations_specialist |  | `W04-S03` |
| 3 | `W04-S03` | Capture customer profile | execution | `customer_onboarding_specialist` |  |  | `W04-S04` |
| 4 | `W04-S04` | Capture canonical terms acceptance | execution | `customer_onboarding_specialist` |  | compliance_privacy_officer | `W04-S05` |
| 5 | `W04-S05` | Activate usable customer account | decision | `customer_onboarding_specialist` |  |  | `W04-S06` |
| 6 | `W04-S06` | Deliver first-inquiry guidance | handoff | `customer_onboarding_specialist` | communications_manager; rfq_qualification_manager |  | `W04-S07` |
| 7 | `W04-S07` | Close onboarding | closure | `customer_onboarding_specialist` |  | customer_success_director | `WORKFLOW_COMPLETE` |

## Phase D requirement

For every step populate the handler matrix and prove actual caller, authoritative handler, typed contract, object mutations, rules/gates, state, idempotency, failure, review/handoff, trace and external-effect policy.

## Workflow acceptance

- deterministic happy path reaches required end state;
- failure/block path is visible;
- cancellation leaves no active derived work;
- replay creates no duplicate effect;
- no live external effect;
- no paid inference;
- no founder approval except a specific refund in W17.
