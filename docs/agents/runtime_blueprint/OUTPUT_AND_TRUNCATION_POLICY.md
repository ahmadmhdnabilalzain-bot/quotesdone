# Output, Context and Truncation Policy

## Structured outputs

Every task class has a concise JSON schema. Narrative explanation is optional and bounded; operational fields are mandatory.

## Truncation

Treat any of these as failure:

- `finish_reason=length`;
- missing closing JSON/schema fields;
- output validator failure;
- incomplete mandatory sections;
- provider stream ending without usage/final status.

A truncated consequential result is never executed.

## Recovery

1. Mark the first attempt `truncated` in the trace.
2. Reduce irrelevant context and retrieve only priority evidence.
3. Ask the same role for the missing structured fields, not a duplicated full essay.
4. Preserve both attempts.
5. Allow at most one controlled repair call unless the task policy permits more.
6. Escalate persistent truncation or use a higher-output policy only within cost limits.

## Default output limits

- routine: 1,200–1,400 tokens;
- professional specialist: 1,800–2,200;
- manager: 2,800;
- independent reviewer: 2,400;
- critical escalation: 3,600.

The 1M-token model context is not permission to send 1M tokens. Default total context remains 12K–48K by task class.
