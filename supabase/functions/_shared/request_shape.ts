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
  }
  if (s.responseFormat != null && s.supported?.has('response_format')) out.response_format = s.responseFormat;
  return out;
}
