// inquiry_intake/restated_questions.ts — the guard against the multi-trade re-ask pathology. Moved verbatim from handle.ts
// (19 Nov 2026, it_engineer; ledgers 1714/1715/1556: handle.ts was 1,418 lines), which runs it on every turn's reply.
// deno-lint-ignore-file no-explicit-any

// Guard against the multi-trade re-ask pathology: suppress any question/missing item that merely
// restates a fact the model itself listed in already_provided (or marked 'stated' in provenance).
export function dropRestatedQuestions(out: any): void {
  try {
    const provFacts: string[] = Array.isArray(out.already_provided) ? out.already_provided.map((s: any) => String(s).toLowerCase()) : [];
    const provKeys: string[] = (out.provenance && typeof out.provenance === 'object') ? Object.entries(out.provenance).filter(([, v]) => v === 'stated').map(([k]) => String(k).toLowerCase().replace(/_/g, ' ')) : [];
    const covered = new Set<string>();
    for (const p of provFacts.concat(provKeys)) for (const w of p.split(/[^a-z0-9]+/)) if (w.length > 3) covered.add(w);
    const isDup = (q: any) => { const toks = String(q).toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 3); if (toks.length < 2) return false; const hits = toks.filter((w) => covered.has(w)).length; return hits >= Math.ceil(toks.length * 0.6); };
    if (Array.isArray(out.questions)) out.questions = out.questions.filter((q: any) => !isDup(q));
    if (Array.isArray(out.missing)) out.missing = out.missing.filter((m: any) => !isDup(m));
    if (out.status === 'needs_info' && (!out.questions || out.questions.length === 0) && provKeys.length >= 5) { out.readiness = Math.max(Number(out.readiness) || 0, 80); }
  } catch (_e) { /* guard best-effort */ }
}
