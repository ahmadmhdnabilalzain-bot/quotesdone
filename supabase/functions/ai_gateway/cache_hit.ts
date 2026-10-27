// A cached answer is served only if a model the route allows NOW wrote it.
// 19 Oct 2026 (run 0a717394, S19): matrix v3 moved intent_detection to openai/gpt-6-luna-pro, but the
// semantic cache (scoped by task class, not model, 24 h TTL) still held an openai/gpt-6-luna answer and
// replayed it 3 times, logged as model_used=openai/gpt-6-luna. A route change must take effect at once.
export function cacheHitServesRoute(hitModel: string | null | undefined, model: string, fallback: string | null): boolean {
  // A cached row with no recorded model cannot be shown to come from this route, so it is not served (fail closed).
  return !!hitModel && (hitModel === model || hitModel === fallback);
}
