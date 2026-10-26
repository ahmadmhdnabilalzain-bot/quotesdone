# Zero-Cost and Provider Policy

Mandatory:

```text
NO_PAID_AI=true
OPENROUTER_DISABLED=true
AI_PROVIDER_MODE=mock
PHASE_D_EXTERNAL_EFFECT_MODE=mock
```

Prohibited: OpenRouter including metadata, all paid AI, live email/SMS/WhatsApp, live publishing, live payment/refund, auto top-up and fallback provider keys.

Use a central fail-closed gate and network deny. Gate read failure or empty/malformed state denies.

Required final evidence:

```text
OpenRouter HTTP requests: 0
Other paid AI requests: 0
llm_attempt rows: 0
Paid inference cost: USD 0.00
Live notifications/publications/payments/refunds: 0
```
