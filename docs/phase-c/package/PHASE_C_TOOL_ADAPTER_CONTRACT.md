
# Tool Adapter Contract — Phase C

Phase C inventories and connects the tool boundary without paid provider calls.

Every adapter must define:

- stable tool ID and version;
- purpose;
- authorized role/action classes;
- input and output JSON Schema;
- read-only versus side-effecting;
- permission and authority check;
- idempotency key strategy;
- timeout and retry policy;
- explicit `success`, `empty`, `refused`, `timeout`, `provider_error`, `invalid_result` states;
- result ID/hash;
- trace/audit behavior;
- health check;
- mock or recorded fixture;
- secret location/name only.

Phase C acceptance uses mocks/fixtures and deterministic internal database tools. Any outbound request to a paid inference provider is a test failure.

A role cannot state that it used a tool when no stored tool-result record exists.
