// intake_answers — how journey a reads the sales engineer's answer and replies to what it still asks (11 Nov 2026,
// sales_engineer). Kept apart from journeys.mjs (which loads a browser) so a check can run it with no browser.
//
// MEASURED, nightly run 077cbbfc (10 Nov 2026): journey a reported "8 turn(s), status=held, readiness=0". The 0 was the
// harness's: inquiry_intake answers readiness as an OBJECT ({filled, required, score}) beside readiness_score, and
// Number({...}) is NaN, so every run since that shape landed printed 0 (the run log said 75 on the held turn). The hold
// itself was the slot machinery's (slots.ts MAX_OPEN_TURNS = 3): six fixed sentences and a tap on the first chip never
// answered the question the intake was asking, so a required spec stayed open three turns and the intake held it, the
// portal never posted, and journey b's "routing" read a request routing never saw. A customer answers the question asked;
// the drawing harnesses already do (a reply per open question), and journey a now does the same: the held turn's own
// next_question (its text and, when it offers them, its options) is answered, a few times, inside the same budget.
// prevented by: scripts/checks/journey_a_reads_the_intake_and_answers_what_it_asks.test.mjs

/** The readiness the intake answered, 0..100: readiness_score, else readiness.score, else a bare number; prev otherwise. */
export function readinessOf(j, prev = 0) {
  for (const v of [j?.readiness_score, j?.readiness?.score, j?.readiness]) {
    if (v == null || typeof v === 'object') continue;
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return prev;
}

// The facts of journey a's request, worded the way the customer would say them. Matched on the question's own words.
const FACTS = [
  [/warrant/i, 'A 2 year warranty covering materials and workmanship.'],
  [/by when|date|deadline|deliver|timeline|start/i, 'Delivery needed by 30 November 2026.'],
  [/install|fix|fit/i, 'Supply and installation, including removal of the old windows.'],
  [/glass|glaz/i, 'Double glazed 6mm + 12mm air + 6mm glass.'],
  [/colou?r|finish|coat|ral/i, 'Powder coated white, RAL 9016.'],
  [/profile|system|frame|thermal|brand|series/i, 'Thermal break aluminium frames, Schuco AWS 70 or equal.'],
  [/size|dimension|width|height|mm/i, 'Each window is 1200 x 1500 mm.'],
  [/how many|quantity|number of|units|qty/i, '40 windows.'],
  [/type|sliding|casement|open/i, 'Sliding windows.'],
  [/where|location|emirate|area|site|floor|access/i, 'A private villa in Dubai Marina, ground and first floor, direct vehicle access.'],
  [/budget|price|cost/i, 'The budget is open.'],
];

/** What the customer types for the intake's next question: one of its own options when it offers them, else the fact it asks for. */
export function answerFor(nextQuestion) {
  const nq = nextQuestion && typeof nextQuestion === 'object' ? nextQuestion : null;
  const text = String(nq?.text ?? nextQuestion ?? '');
  const options = Array.isArray(nq?.options) ? nq.options.map(String).filter((o) => o.trim() && !/not sure|don.?t know|skip/i.test(o)) : [];
  for (const [re, said] of FACTS) {
    if (!re.test(text)) continue;
    // An option that says the same thing is what a customer would tap; otherwise the sentence.
    const picked = options.find((o) => said.toLowerCase().includes(o.toLowerCase()) || o.toLowerCase().includes(said.split(/[ ,.]/)[0].toLowerCase()));
    return picked || said;
  }
  return options[0] || (text ? 'Standard specification as described: 40 aluminium sliding windows, 1200 x 1500 mm, double glazed, powder coated RAL 9016, supply and installation.' : '');
}

/** Why a held intake was held, for the report: the harness subject's held_reason and the specs still open. */
export function heldDetail(j) {
  if (!j || j.status !== 'held') return '';
  const open = Array.isArray(j.missing_keys) ? j.missing_keys : Array.isArray(j.missing) ? j.missing : [];
  return `; held_reason=${j.held_reason ?? '-'}; open=${open.map(String).slice(0, 8).join(',') || '-'}; next=${String(j.next_question?.key ?? '-')}`;
}
