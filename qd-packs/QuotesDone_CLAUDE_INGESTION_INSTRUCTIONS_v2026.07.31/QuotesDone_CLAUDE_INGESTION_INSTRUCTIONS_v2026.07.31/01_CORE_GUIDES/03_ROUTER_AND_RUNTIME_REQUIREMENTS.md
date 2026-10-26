# Router and Runtime Requirements

1. Preserve the customer’s original message.
2. Return ranked category/subcategory candidates, extracted fields, confidence and reasons.
3. Ask one short outcome-based clarification when confidence is below threshold or routes overlap.
4. Allow multi-category inquiries.
5. Use deterministic tables for next-question selection and completeness.
6. Reuse values already extracted from trusted documents; do not repeat questions unless a conflict exists.
7. Block supplier dispatch for missing critical fields, unresolved document conflicts, failed privacy/redaction or regulated/professional escalation.
8. Retrieve only relevant internal knowledge records and exact approved source extracts.
9. Log every route, rule, source, question, answer, correction, override and escalation.
10. Use premium AI only for low-confidence language, complex attachments, drawings or unresolved exceptions.
