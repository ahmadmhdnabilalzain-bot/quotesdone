// THE ANSWER ai_gateway GIVES TO {action:'embed'}. Seat: it_engineer. 22 Sep 2026 (instruction 645).
//
// Measured 22 Sep 2026: scripts/checks/a_catalogue_line_is_understood_by_meaning.test.mjs failed once in a
// full production-token run with "the free embed path refused (HTTP 200)" and passed 3/3 alone. The
// gateway's embed() catches every gte-small error and returns null -- correct for the semantic cache,
// where a vector is an optimisation -- but the embed action then answered {ok:true, embedding:null}
// with HTTP 200. A success status over no vector: nothing a caller could retry on, nothing the logs
// could count.
//
// A missing vector is now a 503 {ok:false, error:'embed_failed'}: the model is temporarily unable,
// which is what 503 means, and every caller that already treated !res.ok or a missing embedding as a
// refusal keeps doing so (the callers and what each does are listed in the PR that added this file).
// Pure, so scripts/checks/a_failed_embedding_is_never_answered_as_ok.test.mjs can prove it from Node.
export function embedAnswer(v: string | null): { status: number; body: Record<string, unknown> } {
  return typeof v === 'string' && v.length > 2
    ? { status: 200, body: { ok: true, embedding: v } }
    : { status: 503, body: { ok: false, error: 'embed_failed', embedding: null } };
}
