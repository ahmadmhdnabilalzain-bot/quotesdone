# OpenRouter and premium-model reduction plan

## Goal

Reduce external model calls without reducing quality or safety.

## Replace with deterministic code

- workflow state transitions;
- authority and threshold checks;
- mandatory-field completeness;
- question sequencing where rules exist;
- eligibility and routing filters;
- fee, tax-display and SLA calculations from approved configuration;
- duplicate suppression and idempotency;
- template generation from structured data;
- KPI queries and alerts;
- event subscriptions and handoffs.

## Replace with internal retrieval plus a small model

- ordinary-language intent and field extraction;
- short bilingual rephrasing;
- email and message classification;
- summarisation of already structured records;
- matching synonyms to approved taxonomy;
- generating a natural question from an approved question record.

## Keep premium models for justified cases

- complex multi-document synthesis;
- materially ambiguous text after clarification;
- advanced quotation-comparison narrative;
- difficult Arabic/English technical correspondence;
- unusual cross-department planning;
- high-quality controlled content drafts;
- fallback when the approved small model fails quality tests.

## Keep multimodal models or specialist tools for

- drawings;
- images;
- poor scans;
- visual redaction;
- complex layout extraction;
- voice or video where deterministic parsers cannot recover the content.

## Never delegate final binding decisions to a model alone

- legal positions;
- tax filings;
- security breach notifications;
- structural or engineering design;
- authority approvals;
- material money movement;
- identity and access changes.

## Measurement

Create a monthly report with:

- calls by task class and route;
- cost per completed inquiry, quote comparison and support case;
- percentage deterministic;
- percentage small/local model;
- percentage premium;
- fallback and error rates;
- human override rate;
- quality by route;
- estimated avoided cost.

Only replace a higher-quality route when benchmark and production evidence show the cheaper route satisfies the required standard.
