# Master acceptance gates

## Architecture
- [ ] No duplicate portal/OS architecture was introduced.
- [ ] All new tables and actions map to an owner OS and department.
- [ ] Every mutation emits or links to a canonical event and decision trace.
- [ ] Every workflow has a durable run and step record.

## Autonomy
- [ ] Routine low-risk work executes, rather than merely producing a recommendation.
- [ ] Every executor is registered, policy checked, idempotent and retry-safe.
- [ ] Failed actions enter a dead-letter/recovery path.
- [ ] Founder receives exceptions, not routine approvals.

## Privacy and security
- [ ] No pre-reveal customer identity is visible to suppliers.
- [ ] Control Mode is short-lived and MFA protected.
- [ ] Service-role endpoints enforce authentication and authorization.
- [ ] Destructive actions have rollback/undo where technically possible.

## AI cost
- [ ] Deterministic rules run without OpenRouter.
- [ ] Quote comparison has a model-free fallback.
- [ ] Model calls include task class, budget, cache and outcome logging.

## User experience
- [ ] Customer and supplier portals work on mobile web.
- [ ] Customer journey is complete in English and Arabic.
- [ ] Every score/recommendation has an explanation and source/freshness indicator.
- [ ] No mock metrics or invented market values are shown as facts.

## Production
- [ ] All staging E2E tests pass.
- [ ] Rollback tested.
- [ ] Monitoring and alerts configured.
- [ ] Founder approves release report.
