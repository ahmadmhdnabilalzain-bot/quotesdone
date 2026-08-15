# Current Model Source Notes — checked 14 August 2026

The exact model IDs in this package were checked against official OpenRouter model pages:

- `anthropic/claude-haiku-4.5` — https://openrouter.ai/anthropic/claude-haiku-4.5
- `anthropic/claude-sonnet-5` — https://openrouter.ai/anthropic/claude-sonnet-5
- `anthropic/claude-opus-5` — https://openrouter.ai/anthropic/claude-opus-5
- `openai/gpt-5.2` — https://openrouter.ai/openai/gpt-5.2
- `google/gemini-3.6-flash` — https://openrouter.ai/google/gemini-3.6-flash
- `openai/text-embedding-3-small` — https://openrouter.ai/openai/text-embedding-3-small
- `google/gemini-embedding-2` — https://openrouter.ai/google/gemini-embedding-2
- `cohere/rerank-4-fast` — https://openrouter.ai/cohere/rerank-4-fast
- `cohere/rerank-4-pro` — https://openrouter.ai/cohere/rerank-4-pro

Supporting operational controls:

- Guardrails and budget caps — https://openrouter.ai/docs/guides/features/guardrails/overview
- Usage accounting — https://openrouter.ai/docs/cookbook/administration/usage-accounting
- Prompt caching — https://openrouter.ai/docs/guides/best-practices/prompt-caching
- Exacto tool-quality routing — https://openrouter.ai/docs/guides/routing/model-variants/exacto

Model availability and prices can change. Claude must verify model IDs through the OpenRouter Models API before migration, record the verified timestamp, and refuse silent substitution.
