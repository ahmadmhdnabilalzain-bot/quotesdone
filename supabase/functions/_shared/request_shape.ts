// _shared/request_shape.ts — the per-model shape of one OpenRouter chat request (23 Sep 2026,
// prompt audit findings 1, 3, 4 and 7).
//
// ai_gateway builds one payload per ladder attempt, and the ladder can cross model families, so
// what a request may carry is decided per attempt, not per caller:
//
//   * Claude (anthropic/*): Opus 4.7+, Opus 5.x, Sonnet 5 and Fable reject temperature / top_p /
//     top_k with a 400. The gateway drops them for every anthropic/ route rather than keep a list
//     of which older Claude still accepts them; no caller depends on sampling for correctness.
//   * Claude thinking cannot be disabled on Opus 5.5, and its effort defaults to medium. OpenRouter
//     documents the field as `reasoning: { effort }` (low|medium|high|xhigh|max for Claude) and says
//     max_tokens must be strictly higher than the reasoning budget, so Claude attempts get the
//     effort stated explicitly and THINKING_HEADROOM tokens on top of the answer budget - without
//     it thinking eats the answer and the reply comes back truncated.
//   * response_format is forwarded only when OpenRouter lists `response_format` among the model's
//     supported_parameters. It fails the request (not ignored) on a model that lacks it, so an
//     unknown list means "do not send"; callers keep their fence-stripping parser as the fallback.

export const THINKING_HEADROOM = 4000;
export const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'] as const;
export type Effort = typeof EFFORTS[number];

// Reasoning models outside Claude, used only when OpenRouter's catalogue could not be read for this attempt.
export const REASONING_ID = /^openai\/(gpt-6|o\d)/;

export function isClaude(model: string): boolean {
  return /^anthropic\/claude-/.test(model);
}

export interface ShapeIn {
  model: string;
  maxTokens: number;                  // the answer budget from model_policy
  temperature?: number | null;
  effort?: string | null;             // caller or policy; defaults to medium for Claude
  // deno-lint-ignore no-explicit-any
  responseFormat?: any;
  supported?: Set<string> | null;     // OpenRouter supported_parameters for this model; null = unknown
}

export function shapeRequest(s: ShapeIn): Record<string, unknown> {
  const out: Record<string, unknown> = { max_tokens: s.maxTokens };
  const claude = isClaude(s.model);
  if (s.temperature != null && !claude) out.temperature = s.temperature;
  if (claude) {
    const effort = (EFFORTS as readonly string[]).includes(String(s.effort)) ? String(s.effort) : 'medium';
    out.reasoning = { effort };
    out.max_tokens = s.maxTokens + THINKING_HEADROOM;
  } else if (s.supported ? s.supported.has('reasoning') : REASONING_ID.test(s.model)) {
    // an unknown catalogue (null) falls back to the model id (ceo, #1585: Luna Pro reviews came back empty at 600)
    // ANY REASONING MODEL, NOT ONLY CLAUDE (it_engineer, 19 Oct 2026). Matrix v3 (18 Oct) moved the internal classes to
    // GPT-6 Luna Pro, which reasons before it answers and spends that inside max_tokens. Measured in the model-on exam
    // (runs b2f80d4d, cdd95305): 6 of 60 seat answers held because the JSON answer was cut off mid-sentence at the
    // 900-token budget, and planner calls ran to the 45 s wall. The answer budget is the caller's; thinking gets its own.
    out.max_tokens = s.maxTokens + THINKING_HEADROOM;
    // A CALLER'S EXPLICIT EFFORT REACHES A REASONING MODEL OF ANOTHER FAMILY TOO (customer_support, 19 Oct 2026), only where
    // OpenRouter lists `reasoning` for it. Measured: a WhatsApp classification on Luna Pro wrote 800-1800 reasoning tokens
    // (10-20 s) at the default effort. No effort given = the model's own default, exactly as before.
    if (s.effort && (EFFORTS as readonly string[]).includes(String(s.effort))) out.reasoning = { effort: String(s.effort) };
  }
  if (s.responseFormat != null && s.supported?.has('response_format')) out.response_format = s.responseFormat;
  return out;
}
