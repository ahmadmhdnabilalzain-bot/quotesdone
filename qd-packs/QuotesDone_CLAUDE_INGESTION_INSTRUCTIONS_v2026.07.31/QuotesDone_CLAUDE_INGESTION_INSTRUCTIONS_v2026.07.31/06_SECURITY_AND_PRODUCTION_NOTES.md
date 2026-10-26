# Security and Production Notes

- Never paste the Supabase service-role key into Claude chat or commit it to Git.
- Use environment variables and a secrets manager.
- Run imports through a restricted admin/CI context.
- Keep an immutable log of ingestion runs.
- Use staging before production.
- Keep a database backup and tested rollback.
- Preserve RLS and execute grants.
- Do not expose source documents, private knowledge or internal rules through public endpoints.
- Do not automatically approve legal, regulatory, medical, engineering or safety records.
- Keep professional-boundary and escalation rules active.
- Put the new runtime behind a feature flag and roll out by category.
