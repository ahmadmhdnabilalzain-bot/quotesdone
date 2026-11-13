// scripts/e2e/journey_proof/record.mjs — the journey RECORD: what run.mjs writes as the journey happens and dossier.ts
// prints. Pure helpers only (no network), so the dossier's judgements are unit-tested. Seat: customer_support.
//
// THE RECORD (record.json beside the artefacts; every file named in it is relative to the journey folder)
//   journey     { key, title, how_made, run_tag, site, started, finished, mode: 'live' | 'stubbed', cap_usd, estimate_usd }
//   steps       [{ id: 's1'..'s10', title, start, end }]            the clock the cost is attributed by
//   sections    { s1..s10, co (inside the company, founder ledger 1685-1688): { verdicts: [{ expected, happened, as_expected: true | false | null }], gaps: [text], ... } }
//               each section also carries its own evidence (see dossier_body.ts for what each one prints)
//   findings    [{ severity: 'leak' | 'product' | 'looked_wrong' | 'harness', step, text }]
//   cost        { rows: [{ at, fn, model, usd }], by_step, total_usd }
//   stand_ins   [text]   every thing in the run that was NOT the product, said plainly
//   exhibits    [{ title, file, why }]   files appended to the dossier (PDFs) or attached to it (other files)

export const SECTION_TITLES = {
  s1: 'The customer exists: sign-up and his signed terms',
  s2: 'The inquiry as it was made',
  s3: 'The inquiry as it was shared with suppliers',
  s4: 'Who was asked, and were they the right suppliers',
  s5: 'The quotations',
  s6: 'Every notification the customer received',
  s7: 'The comparison report',
  s8: 'The choice, the reveal fee, the invoice and the confirmations',
  co: 'Inside the company: who knew, and what they did',
  s9: 'Where every document of this journey is filed',
  s10: 'What went wrong, what it cost, and what was not the product',
};

const SEVERITY = { leak: 0, product: 1, looked_wrong: 2, needs_model: 3, harness: 4 };
export const SEVERITY_WORDS = { leak: 'Anonymity leak', product: 'The product did not do it', looked_wrong: 'Looked wrong', needs_model: 'Could not happen with the models off (dry run)', harness: 'The test harness, not the product' };

/** Most serious first; inside one severity, in the order the journey met them. */
export function orderFindings(findings) {
  return (findings || []).map((f, i) => ({ ...f, i })).sort((a, b) => (SEVERITY[a.severity] ?? 9) - (SEVERITY[b.severity] ?? 9) || a.i - b.i).map(({ i: _i, ...f }) => f);
}

/**
 * Were the right suppliers asked? `fixtures` are the run's own demo suppliers with what they SHOULD be:
 *   [{ lead_id, label, trade, emirates, should: 'right' | 'wrong_emirate' | 'unrelated' | 'bench' }]
 * `matched` is what the live matcher wrote by itself (inquiry_matches): [{ lead_id, company, reason, is_demo }].
 * `added` is what the harness wrote, kept apart. Returns the three questions the founder asked, answered.
 */
export function matcherVerdict(fixtures, matched, added = []) {
  const byId = new Map((fixtures || []).map((f) => [String(f.lead_id), f]));
  const asked = (matched || []).map((m) => ({ ...m, should: byId.get(String(m.lead_id))?.should ?? (m.is_demo === false ? 'REAL' : 'outside_this_run'), label: byId.get(String(m.lead_id))?.label ?? m.company }));
  const askedIds = new Set(asked.map((m) => String(m.lead_id)));
  const right = (fixtures || []).filter((f) => f.should === 'right');
  return {
    asked,
    right_asked: asked.filter((m) => m.should === 'right'),
    wrong_asked: asked.filter((m) => m.should !== 'right'),
    right_missed: right.filter((f) => !askedIds.has(String(f.lead_id))),
    real_supplier_asked: asked.filter((m) => m.should === 'REAL'),
    added_by_test: (added || []).map((a) => ({ ...a, label: byId.get(String(a.lead_id))?.label ?? a.company })),
  };
}

/**
 * Each cost row belongs to the step whose clock window holds it; a row outside every window (a background job the
 * journey triggered, after its step ended) is counted under 'after the steps' and named.
 */
export function costByStep(rows, steps) {
  const out = new Map((steps || []).map((s) => [s.id, { step: s.id, title: s.title, calls: 0, usd: 0, fns: {} }]));
  const late = { step: 'other', title: 'outside any step window (background work the journey caused)', calls: 0, usd: 0, fns: {} };
  for (const r of rows || []) {
    const t = Date.parse(r.at);
    const s = (steps || []).find((x) => t >= Date.parse(x.start) && t <= Date.parse(x.end || '9999-12-31'));
    const b = s ? out.get(s.id) : late;
    b.calls++; b.usd += Number(r.usd) || 0; b.fns[r.fn] = (b.fns[r.fn] || 0) + 1;
  }
  const list = [...out.values(), late].filter((b) => b.calls > 0).map((b) => ({ ...b, usd: Math.round(b.usd * 10000) / 10000 }));
  return { by_step: list, total_usd: Math.round(list.reduce((a, b) => a + b.usd, 0) * 10000) / 10000, calls: list.reduce((a, b) => a + b.calls, 0) };
}

/** A step's clock, for cost attribution and for "how long it took". */
export function clock(record) {
  record.steps ||= [];
  return {
    start(id) { const s = { id, title: SECTION_TITLES[id] || id, start: new Date().toISOString(), end: null }; record.steps.push(s); return s; },
    end(s) { s.end = new Date().toISOString(); return s; },
  };
}

/** The verdict line, never "passed": what was expected and what happened. */
export const verdict = (expected, happened, asExpected) => ({ expected, happened, as_expected: asExpected === undefined ? null : asExpected });

/** Seconds between two ISO times, one decimal, for "the reply took 7.4 s". */
export const secondsBetween = (a, b) => (a && b ? Math.round((Date.parse(b) - Date.parse(a)) / 100) / 10 : null);
