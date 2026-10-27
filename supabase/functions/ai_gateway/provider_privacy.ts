// Every request ai_gateway sends to OpenRouter refuses providers that collect or train on data.
// OpenRouter provider routing: data_collection "deny" restricts requests to providers that
// "do not collect user data" (https://openrouter.ai/docs/features/provider-routing).
//
// Measured 19 Oct 2026 against /api/v1/models/<id>/endpoints and /api/frontend/v1/all-providers
// (dataPolicy.training=false AND retainsPrompts=false): every matrix model has at least one such
// provider - Sonnet 5.5 and Opus 5.5 (Amazon Bedrock, Azure, Google Vertex), GPT-6 Luna Pro and
// GPT-6 Luna (Azure), Gemini 3.8 Flash (Google Vertex), DeepSeek v4.1 Flash (DeepInfra, Together,
// Fireworks, Nebius, Novita and more). So the exception list is empty. A model may join it only
// with a measurement showing it has no deny-compliant provider; provider_privacy.test.ts pins it.
export const DATA_COLLECTION_EXCEPTIONS: readonly string[] = [];

export function withDataDeny(payload: Record<string, unknown>, model: string): Record<string, unknown> {
  if (DATA_COLLECTION_EXCEPTIONS.includes(model.split(':')[0])) return payload;
  const prev = (payload.provider && typeof payload.provider === 'object') ? payload.provider as Record<string, unknown> : {};
  payload.provider = { ...prev, data_collection: 'deny' };
  return payload;
}
