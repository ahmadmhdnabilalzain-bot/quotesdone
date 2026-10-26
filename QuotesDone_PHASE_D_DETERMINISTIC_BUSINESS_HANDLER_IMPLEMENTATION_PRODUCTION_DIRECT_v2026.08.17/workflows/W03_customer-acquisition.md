# W03 — Customer acquisition

- **Domain:** growth
- **Criticality:** medium
- **Profile:** campaign_cycle
- **Primary object:** `growth_program`
- **Accountable role:** `chief_revenue_officer`
- **Start event:** Growth objective/campaign cycle
- **Required end state:** Qualified customer pipeline and measured acquisition
- **Founder boundary:** Founder-approved budgets and commercial rules

## Purpose

Create qualified customer demand and measure acquisition through to commercial outcomes.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W03-S01` | Set acquisition objective | decision | `chief_revenue_officer` | corporate_performance_director; crm_revenue_operations_manager |  | `W03-S02` |
| 2 | `W03-S02` | Develop audience and market evidence | analysis | `marketing_performance_analyst` | market_intelligence_analyst; crm_revenue_operations_manager |  | `W03-S03` |
| 3 | `W03-S03` | Create campaign plan | execution | `marketing_director` | brand_creative_manager; social_media_community_manager; business_development_manager |  | `W03-S04` |
| 4 | `W03-S04` | Create message and creative brief | execution | `brand_creative_manager` | content_strategy_copy_specialist; visual_design_specialist |  | `W03-S05` |
| 5 | `W03-S05` | Produce campaign assets | execution | `content_strategy_copy_specialist` | visual_design_specialist; social_media_community_manager |  | `W03-S06` |
| 6 | `W03-S06` | Review campaign assets | review | `ai_quality_assurance_reviewer` | brand_creative_manager; compliance_privacy_officer |  | `W03-S07` |
| 7 | `W03-S07` | Publish and capture lead events | execution | `social_media_community_manager` | lifecycle_channel_operations_specialist; crm_revenue_operations_manager |  | `W03-S08` |
| 8 | `W03-S08` | Measure performance and attribution | measurement | `marketing_performance_analyst` | crm_revenue_operations_manager; business_intelligence_analyst |  | `W03-S09` |
| 9 | `W03-S09` | Optimize or close the campaign | closure | `chief_revenue_officer` | marketing_director; marketing_performance_analyst |  | `WORKFLOW_COMPLETE` |

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
