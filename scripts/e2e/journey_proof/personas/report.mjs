// scripts/e2e/journey_proof/personas/report.mjs — "WOULD A REAL PERSON HAVE GOT THROUGH?" Pure: the persona's turns and the
// supplier personas' records in, the dossier section out. Seat: customer_support. The founder asked, 15 Nov 2026, whether
// the journey's customers were realistic; this section answers it for the person who played the journey: where they left
// (or that they got through), what the platform asked twice, the slowest replies, what they could not answer and what the
// platform did with each "not sure", what they did not understand, and what each supplier persona met.
//
//   peopleSection({ persona, turns, abandoned, outcome, final_details, suppliers, mode, latency_source, spend })
//     -> the record's sections.people: { title, headline, got_through, verdicts, ... } (dossier_body.ts prints it)
//   peopleText(section) -> the same in plain text (the dry run prints it; the hand-back quotes it)

export const PEOPLE_TITLE = 'Would a real person have got through?';
const short = (s, n = 140) => { const t = String(s ?? '').replace(/\s+/g, ' ').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t; };
const qOf = (t) => t?.question ? (t.question.text || t.question.key || '') : '';
const sameAsked = (a, b) => !!(a?.question && b?.question && ((a.question.key && a.question.key === b.question.key) || (a.question.topics || []).some((x) => (b.question.topics || []).includes(x))));

/** What the platform did after the person said "not sure" at turn t: its next message, read from the next turn. */
export function afterNotSure(turns, i, outcome) {
  const t = turns[i]; const next = turns[i + 1];
  if (!next) return outcome === 'abandoned' ? 'the person had left' : (/ready/.test(outcome || '') ? 'it went on to the summary: the request was ready' : 'nothing came after it');
  if (sameAsked(t, next)) return `asked the same thing again at turn ${next.n}: "${short(qOf(next), 90)}"`;
  if (!next.question) return /ready/.test(next.status || '') ? 'it accepted the "not sure" and the request was ready' : `answered without a new question (status ${next.status || '?'})`;
  return `accepted it and moved on to: "${short(qOf(next), 90)}"`;
}

export function peopleSection({ persona, turns = [], abandoned = null, outcome = null, final_details = null, suppliers = [], mode = 'live', latency_source = null, spend = null }) {
  const T = turns;
  const asked = T.filter((t) => t.question);
  const repeats = T.filter((t) => t.repeat).map((t) => ({ n: t.n, question: short(qOf(t), 160), first_asked_at: t.repeat_of, why: t.repeat_why }));
  const slowest = T.filter((t) => t.latency_s != null).sort((a, b) => b.latency_s - a.latency_s).slice(0, 3).map((t) => ({ n: t.n, seconds: t.latency_s, question: short(qOf(t), 120) || '(no question)' }));
  const notSure = [];
  T.forEach((t, i) => { for (const id of t.not_sure || []) {
    const fact = (persona.facts || []).find((f) => f.id === id);
    const key = t.question?.key;
    notSure.push({ n: t.n, topic: fact ? fact.about : id.replace(/^unknown:/, 'not in what this person knows: '), question: short(qOf(t), 120), said: short(t.reply, 120), file: t.file || null,
      platform_did: afterNotSure(T, i, outcome), recorded_as: key && final_details && final_details[key] != null ? short(final_details[key], 120) : null });
  } });
  const misunderstood = T.filter((t) => t.understood === false).map((t) => ({ n: t.n, question: short(qOf(t), 140), said: short(t.reply, 100) }));
  const files = T.filter((t) => t.file).map((t) => ({ n: t.n, file: t.file, caption: (persona.files || []).find((f) => f.id === t.file)?.caption || t.file }));
  const problems = T.flatMap((t) => (t.problems || []).map((p) => ({ n: t.n, text: p })));
  const gotThrough = !abandoned && /ready/.test(outcome || '');
  const headline = abandoned
    ? `No. ${persona.label} left at turn ${abandoned.at}: ${abandoned.reason}.`
    : gotThrough ? `Yes. ${persona.label} got through in ${asked.length} question${asked.length === 1 ? '' : 's'}${repeats.length ? `, though ${repeats.length} of them asked again what was already answered` : ''}.`
    : `Not within the run. ${persona.label} answered ${asked.length} question${asked.length === 1 ? '' : 's'} and the request was not ready (${outcome || 'no outcome recorded'}).`;
  const P = persona.patience || {};
  const verdicts = [
    { expected: `a person like this (${persona.short}) reaches "Send to suppliers" without giving up`, happened: headline.replace(/\.$/, ''), as_expected: abandoned ? false : gotThrough ? true : false },
    { expected: 'nothing the person already answered is asked again', happened: repeats.length ? `${repeats.length} repeat${repeats.length > 1 ? 's' : ''}: ${repeats.map((r) => `turn ${r.n} (${r.why}${r.first_asked_at ? `, first at turn ${r.first_asked_at}` : ''})`).join('; ')}` : 'nothing was asked twice', as_expected: repeats.length === 0 },
    { expected: `no reply slower than this person's patience (${P.slow_s ?? '?'} s)`, happened: slowest.length ? `slowest: ${slowest.map((s) => `${s.seconds} s at turn ${s.n}`).join(', ')}${latency_source ? ` (${latency_source})` : ''}` : 'no reply was timed', as_expected: slowest.length ? slowest[0].seconds <= (P.slow_s ?? Infinity) : null },
    { expected: 'a "not sure" is accepted and the request goes on without it (the supplier advises)', happened: notSure.length ? `${notSure.length} "not sure": ${notSure.filter((x) => /asked the same/.test(x.platform_did)).length} asked again, ${notSure.filter((x) => /moved on|accepted/.test(x.platform_did)).length} accepted` : 'the person was never unsure', as_expected: notSure.length ? notSure.every((x) => !/asked the same/.test(x.platform_did)) : null },
    { expected: 'every question is in words this person understands', happened: misunderstood.length ? `${misunderstood.length} not understood: ${misunderstood.map((m) => `turn ${m.n} "${short(m.question, 60)}"`).join('; ')}` : 'every question was understood', as_expected: misunderstood.length === 0 },
  ];
  const sup = (suppliers || []).map((s) => ({ label: s.label, behaviour: s.behaviour_words || s.behaviour, outcome: s.outcome, steps: (s.steps || []).map((x) => x.outcome), question: s.question || null, range: s.range || null, quote_id: s.quote_id || null }));
  if (sup.length) verdicts.push({ expected: 'each kind of real supplier gets a fair hearing: a question is answered, a range or a photo is read or asked about, silence is chased', happened: sup.map((s) => `${s.label}: ${s.outcome}`).join('; '), as_expected: null });
  return {
    title: PEOPLE_TITLE, mode, latency_source,
    persona: { key: persona.key, label: persona.label, short: persona.short, lang: persona.lang, patience: P, knows: (persona.facts || []).filter((f) => f.knows).map((f) => f.about), does_not_know: (persona.facts || []).filter((f) => !f.knows).map((f) => f.about), files: (persona.files || []).map((f) => f.caption) },
    headline, got_through: gotThrough, abandoned, outcome,
    turns: T.map((t) => ({ n: t.n, question: short(qOf(t), 150) || `(no question; status ${t.status || '?'})`, key: t.question?.key ?? null, latency_s: t.latency_s, repeat: !!t.repeat, understood: t.understood, reply: t.abandoned ? `(left: ${t.abandoned.reason})` : (t.tap ? `(tapped "${t.tap}")` : short(t.reply, 150)) + (t.file ? ` [sent ${t.file}]` : ''), answered: t.answered || [], not_sure: t.not_sure || [] })),
    repeats, slowest, not_sure: notSure, misunderstood, files, problems, suppliers: sup, verdicts,
    spend: spend ? { calls: spend.calls, usd: Math.round((spend.usd || 0) * 10000) / 10000, models: [...(spend.models || [])] } : null,
  };
}

/** The section in plain text. */
export function peopleText(s) {
  const L = [`${s.title}`, `${s.persona.label} (${s.persona.short}); ${s.mode}${s.latency_source ? `; reply times: ${s.latency_source}` : ''}`, '', s.headline, ''];
  L.push('Turn by turn:'); for (const t of s.turns) L.push(`  ${t.n}. ${t.latency_s != null ? `[${t.latency_s} s] ` : ''}${t.repeat ? '[REPEAT] ' : ''}${t.understood === false ? '[not understood] ' : ''}Q: ${t.question}  ->  ${t.reply}`);
  if (s.abandoned) L.push('', `Abandoned at turn ${s.abandoned.at} (${s.abandoned.rule}): ${s.abandoned.reason}`);
  L.push('', `Asked again: ${s.repeats.length ? s.repeats.map((r) => `turn ${r.n} "${r.question}" (${r.why}${r.first_asked_at ? `, first at ${r.first_asked_at}` : ''})`).join('; ') : 'none'}`);
  L.push(`Slowest replies: ${s.slowest.map((x) => `${x.seconds} s (turn ${x.n})`).join(', ') || 'not timed'}`);
  L.push('Could not answer:'); for (const x of s.not_sure) L.push(`  turn ${x.n}: ${x.topic}. Said "${x.said}"${x.file ? ` and sent ${x.file}` : ''}. The platform ${x.platform_did}${x.recorded_as ? `; recorded "${x.recorded_as}"` : ''}.`);
  if (!s.not_sure.length) L.push('  nothing');
  if (s.misunderstood.length) { L.push('Did not understand:'); for (const m of s.misunderstood) L.push(`  turn ${m.n}: "${m.question}" -> "${m.said}"`); }
  if (s.problems.length) { L.push('The player\'s own problems (the test, not the platform):'); for (const p of s.problems) L.push(`  turn ${p.n}: ${p.text}`); }
  if (s.suppliers.length) { L.push('Suppliers:'); for (const x of s.suppliers) L.push(`  ${x.label} (${x.behaviour}): ${x.outcome}`); }
  if (s.spend) L.push(`The person's model calls: ${s.spend.calls}, USD ${s.spend.usd} (${s.spend.models.join(', ') || 'none'})`);
  return L.join('\n');
}
