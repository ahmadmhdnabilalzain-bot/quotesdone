# Acceptance Checklist

Claude should mark each item PASS, FAIL or BLOCKED and provide evidence.

## Files and validation

- [ ] Both archives are readable.
- [ ] Knowledge ZIP checksum recorded.
- [ ] 66 broad package ZIPs found.
- [ ] Lifts and escalators supplement found.
- [ ] 86 route manifests found.
- [ ] All JSONL records validate or rejected rows are reported.
- [ ] All source IDs resolve.

## Database

- [ ] Import ran in staging first.
- [ ] Migration is reversible.
- [ ] Knowledge records are versioned.
- [ ] Every import has an ingestion-run record.
- [ ] Rerunning import creates no duplicates.
- [ ] Interrupted import can resume.
- [ ] Rollback by ingestion run/version works.
- [ ] Private knowledge is not exposed to anonymous roles.

## Operational routes

- [ ] Live catalogue contains 86 routes.
- [ ] All 86 routes are mapped.
- [ ] No route has zero mapped subcategories.
- [ ] Signage and printing route is mapped.
- [ ] Lifts and escalators route is mapped.
- [ ] Multi-category inquiries remain possible.

## Inquiry behavior

- [ ] Informal English wording routes correctly.
- [ ] Informal Arabic wording routes correctly.
- [ ] Ambiguous requests receive one clarification.
- [ ] Existing extracted values prevent duplicate questions.
- [ ] Missing critical values block dispatch.
- [ ] Applicable deterministic rules control sequence and completeness.
- [ ] Regulatory/professional matters escalate instead of being invented.
- [ ] Privacy/redaction gate remains fail-closed.

## Testing

- [ ] 258 operational route tests run.
- [ ] Category scenario tests run.
- [ ] Existing customer registration still works.
- [ ] Existing supplier registration still works.
- [ ] Inquiry creation still works.
- [ ] Supplier matching still works.
- [ ] Quote comparison still works.

## Cost reduction

- [ ] Current OpenRouter calls inventoried.
- [ ] Calls replaceable by SQL/rules identified.
- [ ] Calls replaceable by internal retrieval identified.
- [ ] Calls suitable for a small local model identified.
- [ ] Premium-model fallbacks retained for complex cases.
- [ ] No production AI path removed without tests and feature flag.
