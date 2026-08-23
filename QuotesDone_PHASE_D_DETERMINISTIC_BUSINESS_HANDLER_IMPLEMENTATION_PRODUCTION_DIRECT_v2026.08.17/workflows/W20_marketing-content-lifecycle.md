# W20 — Marketing content lifecycle

- **Domain:** growth
- **Criticality:** high
- **Profile:** campaign_cycle
- **Primary object:** `content_campaign`
- **Accountable role:** `marketing_director`
- **Start event:** Campaign/content objective
- **Required end state:** Reviewed published asset and measured learning
- **Founder boundary:** Creator not sole reviewer; claims within policy

## Purpose

Plan, create, independently review, publish and learn from marketing content against commercial objectives.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W20-S01` | Define content objective and hypothesis | decision | `marketing_director` | marketing_performance_analyst; chief_revenue_officer |  | `W20-S02` |
| 2 | `W20-S02` | Develop content strategy and copy | execution | `content_strategy_copy_specialist` | brand_creative_manager; social_media_community_manager |  | `W20-S03` |
| 3 | `W20-S03` | Create visual assets | execution | `visual_design_specialist` | brand_creative_manager |  | `W20-S04` |
| 4 | `W20-S04` | Review brand and campaign alignment | review | `brand_creative_manager` | marketing_director |  | `W20-S05` |
| 5 | `W20-S05` | Independently review final artifact | review | `ai_quality_assurance_reviewer` | marketplace_content_privacy_reviewer; compliance_privacy_officer |  | `W20-S06` |
| 6 | `W20-S06` | Publish approved content | execution | `social_media_community_manager` | lifecycle_channel_operations_specialist |  | `W20-S07` |
| 7 | `W20-S07` | Collect performance evidence | measurement | `marketing_performance_analyst` | crm_revenue_operations_manager; business_intelligence_analyst |  | `W20-S08` |
| 8 | `W20-S08` | Diagnose performance | analysis | `marketing_performance_analyst` | marketing_director; content_strategy_copy_specialist |  | `W20-S09` |
| 9 | `W20-S09` | Validate learning and close cycle | closure | `marketing_director` |  | corporate_performance_director | `WORKFLOW_COMPLETE` |

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
