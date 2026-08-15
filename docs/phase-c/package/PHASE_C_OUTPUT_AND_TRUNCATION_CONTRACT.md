
# Output Validation and Truncation Contract

Every runtime handler and future agent task must have a versioned output schema.

Before state mutation:

- required fields present;
- output parses;
- status and action class allowed;
- owner/authority/reviewer valid;
- no explicit truncation marker;
- no stop reason indicating token/output limit;
- no incomplete continuation state;
- no unresolved critical field.

A truncated or invalid consequential output is `failed_incomplete`, creates no side effect and opens a retry/remediation task according to policy.

Phase C proves this with deterministic fixtures, including outputs cut at every field boundary. No paid model call is required.
