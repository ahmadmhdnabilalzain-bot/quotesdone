// ai_gateway/confidence.ts — reads the model's own reported confidence out of its output. Moved verbatim from index.ts (9 Nov 2026).

// THE QUALITY AXIS. ai_cost_log.confidence was null on all 1,614 model calls in 30 days because
// fn_llm_log had no parameter for it, so "compare models on quality, latency and cost" could only
// ever have two of the three. This reads the model's OWN reported confidence out of its output when
// the output is JSON and carries one, and returns null otherwise.
//
// It does not derive, estimate or default a score. A model that says nothing about its confidence
// keeps a null, and the comparison stays honestly incomplete for it -- which is the point. A number
// invented here would be indistinguishable from a measured one the moment it reached the column.
// deno-lint-ignore no-explicit-any
// IT REQUIRED THE WHOLE OUTPUT TO BE JSON, AND ALMOST NOTHING HERE IS (measured 11 Aug 2026).
// 1,746 model calls in 7 days, SEVEN with a confidence: 6 from knowledge_exam and 1 from
// quality_axis_probe, the only two callers whose entire reply is a JSON document. Every employee
// path — agent_brain 594 calls, exec_agents 262, action_worker 229 — returns PROSE, so `body
// .startsWith('{')` was false and the column stayed null for 99.6% of the company's thinking.
//
// The trailing-object arm below reads the LAST balanced {...} in the reply. That is exactly where
// agent_brain has always put its machine-readable tail (`@@ACTIONS@@ {json}`, stripped from the
// visible text by splitActions), so one parser change gives every prose caller a place to report a
// confidence without inventing a second format for them to get wrong.
//
// It still does not derive, estimate or default a score. A model that says nothing keeps a null.
// deno-lint-ignore no-explicit-any
export function selfReportedConfidence(text: any): number | null {
  if (typeof text !== 'string' || text.length === 0 || text.length > 200_000) return null;
  const readFrom = (v: unknown): number | null => {
    const root = Array.isArray(v) ? v[0] : v;
    if (!root || typeof root !== 'object') return null;
    const raw = (root as Record<string, unknown>).confidence;
    const n = typeof raw === 'number' ? raw : (typeof raw === 'string' ? Number(raw) : NaN);
    // fn_llm_log normalises a percentage and discards anything outside 0..100, so the only job here
    // is to reject what is not a number at all.
    return Number.isFinite(n) ? n : null;
  };

  // 1. The whole reply is a JSON document. Models fence JSON in ```json … ``` about as often as
  //    they emit it bare.
  const body = text.replace(/^\s*```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
  if (body.startsWith('{') || body.startsWith('[')) {
    try { const hit = readFrom(JSON.parse(body)); if (hit !== null) return hit; } catch { /* fall through */ }
  }

  // 2. A prose reply with a JSON tail. Candidate starts are tried nearest-first against the last
  //    '}', widening until one parses — JSON.parse itself is the validator, so a '{' inside a
  //    quoted value or a nested object costs one failed attempt rather than a hand-rolled scanner
  //    to get subtly wrong. A greedy /\{[\s\S]*\}/ is what NOT to do here: it would start at the
  //    first '{' anywhere in the prose (a code sample, a schema the employee quoted) and fail.
  const end = body.lastIndexOf('}');
  if (end < 0) return null;
  for (let i = body.lastIndexOf('{'); i >= 0; i = body.lastIndexOf('{', i - 1)) {
    if (i > end) continue;
    if (end - i > 20_000) break;      // the tail is a small object, never the whole document
    try { return readFrom(JSON.parse(body.slice(i, end + 1))); } catch { /* widen and retry */ }
  }
  return null;
}
