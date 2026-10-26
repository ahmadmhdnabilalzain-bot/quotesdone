# Acceptance checklist

## Package and data

- [ ] ZIP and file hashes pass.
- [ ] Every JSONL row validates.
- [ ] No duplicate stable IDs.
- [ ] Every source ID resolves.
- [ ] Every department folder is imported or explicitly skipped with reason.
- [ ] Implementation and validation statuses are preserved.
- [ ] No secrets or private identity documents were imported.

## Architecture

- [ ] Existing objects were reused where they own the same concept.
- [ ] No duplicate source of truth was created.
- [ ] Company core, department, live data and external knowledge are separate.
- [ ] Supplier-category corpus is linked by stable keys.
- [ ] Live data is retrieved at runtime, not copied into static knowledge.
- [ ] Deterministic rules own states, sequencing, gates and calculations.
- [ ] Narrative embeddings are limited to retrieval use cases.

## Governance

- [ ] Hard gates block unauthorized execution.
- [ ] Authority changes require approval.
- [ ] Legal, tax, privacy and security records remain review-gated.
- [ ] Audit records contain actor, entity, evidence, rule/policy, result and timestamp.
- [ ] Handoffs require receiver acceptance.
- [ ] Model routing and fallback are enforced.
- [ ] Knowledge changes are versioned and review dates are active.

## Testing

- [ ] Department scenarios pass.
- [ ] Cross-department workflow scenarios pass.
- [ ] Duplicate-event/idempotency tests pass.
- [ ] Provider outage tests pass.
- [ ] Recovery and rollback tests pass.
- [ ] Access and RLS tests pass.
- [ ] Current frontend states and permissions are tested.
- [ ] Arabic/English output tests pass where applicable.
- [ ] OpenRouter reduction report is produced.

## Production decision

- [ ] Department owner approvals obtained.
- [ ] Legal/Tax/Security reviews obtained.
- [ ] Activation starts with low-risk read/advisory use.
- [ ] Monitoring, kill switch and rollback are ready.
- [ ] No mass activation or status promotion.
