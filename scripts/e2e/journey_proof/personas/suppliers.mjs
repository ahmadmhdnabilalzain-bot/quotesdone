// scripts/e2e/journey_proof/personas/suppliers.mjs — THE SUPPLIERS WHO ANSWER A REQUEST, as people. Seat: customer_support.
// Founder, 15 Nov 2026: the journey's suppliers were fixtures that all got approved by the test, and three of five quoted
// within minutes with clean PDFs. Real suppliers do not. Five ZZ DEMO personas, each through the platform's real supplier
// doors (supplier_api, as the portal calls it, with the supplier's own session, the same doors the harness used for its
// fixtures):
//
//   silent       ignores the request: never opens it, never answers. What the platform then does is the finding.
//   asker        asks a clarification question first (the quotation chat: review_start + review_message), waits for the
//                platform's answer, and quotes only after it (a typed PDF through the upload door)
//   range        quotes a price RANGE "subject to site visit" in a plain PDF (upload door: extract_quote + submit_quote)
//   handwritten  sends a phone photo of a handwritten quotation (the same upload door, a JPEG)
//   proper       sends a proper typed PDF quotation (the upload door)
//
// playSupplier() is the behaviour; the doors are handed in, so the dry run and the unit tests hand stand-ins and the live
// run hands supplier_api (run.mjs). It never decides what the platform did: it records what each door answered.
import { quotePdf, handwrittenPhoto, pricedLines, HVAC_RATE } from './artefacts.mjs';

const card = (key, label, behaviour, extra = {}) => ({ key, label, behaviour, letterhead: `${label} LLC`, phone: '+971 50 000 0097', email: `zz-demo-${key}@example.invalid`, trn: '100000000000003', ...extra });
export const SUPPLIERS = {
  silent: card('silent', 'ZZ DEMO Quiet Air', 'ignores'),
  asker: card('asker', 'ZZ DEMO Ask First Cooling', 'clarifies_first', {
    question: 'Before I price it: are the outdoor units on the roof, and can my team reach them by stairs? Is a site visit possible this week?', factor: 1.0 }),
  range: card('range', 'ZZ DEMO Site Visit HVAC', 'range_subject_to_site_visit', { low: 0.85, high: 1.3, factor: 1.0 }),
  handwritten: card('handwritten', 'ZZ DEMO Handwritten AC Works', 'handwritten_photo', { factor: 0.82 }),
  proper: card('proper', 'ZZ DEMO Proper Quote HVAC', 'proper_pdf', { factor: 1.08, lead: '5 days from LPO', warranty: '2 years on installation, 5 years on compressor' }),
};
export const BEHAVIOUR_WORDS = {
  ignores: 'ignores the request',
  clarifies_first: 'asks a question before quoting',
  range_subject_to_site_visit: 'quotes a range "subject to site visit"',
  handwritten_photo: 'sends a phone photo of a handwritten quotation',
  proper_pdf: 'sends a proper typed PDF',
};

/**
 * One supplier persona answers one request. `doors` (all async, all optional except what the behaviour uses):
 *   message(text)        -> { http, said, state }            the quotation chat (review_start, then review_message)
 *   upload(file)         -> { http, read_amount, quote_id, accepted, held, code, missing, typed_by_supplier }
 *   afterSilence()       -> [{ at, what }]                   what the platform sent the silent supplier within the run
 * `job` is { rfq, lines } (the request's lines the supplier prices). `now` is a clock (tests pass a fixed one).
 * Returns { key, label, behaviour, steps: [{ at, door, http, outcome }], files: [{ name, mime, bytes }], quote_id, outcome }.
 */
export async function playSupplier(sp, { doors, job, now = () => new Date().toISOString(), save = null }) {
  const rec = { key: sp.key, label: sp.label, behaviour: sp.behaviour, behaviour_words: BEHAVIOUR_WORDS[sp.behaviour], steps: [], files: [], quote_id: null, outcome: null, started: now() };
  const step = (door, r, outcome) => { rec.steps.push({ at: now(), door, http: r?.http ?? null, outcome }); };
  const lines = pricedLines(job.lines, HVAC_RATE, sp.factor ?? 1);
  const ref = `ZZQ-${String(job.rfq || 'RFQ').slice(0, 8).toUpperCase()}-${sp.key.slice(0, 3).toUpperCase()}`;
  const keep = async (name, mime, bytes) => { const f = { name, mime, bytes: bytes.length }; rec.files.push(f); if (save) f.file = await save(name, bytes); return bytes; };
  const upload = async (name, mime, bytes, what) => {
    const r = await doors.upload({ b64: bytes.toString('base64'), filename: name, mime, bytes });
    const read = r?.read_amount != null ? `the platform read AED ${r.read_amount}` : 'the platform read no amount';
    const fate = r?.quote_id ? (r.accepted ? 'the quotation went live' : r.held ? `the quotation was held${r.missing?.length ? ` (asked for: ${r.missing.join(', ')})` : ''}` : 'the quotation was stored') : `no quotation was made${r?.code ? ` (${r.code})` : ''}`;
    step('upload', r, `${what}: ${read}${r?.typed_by_supplier ? ' (the supplier typed his total into the form)' : ''}; ${fate}`);
    rec.quote_id = r?.quote_id ?? null; return r;
  };
  if (sp.behaviour === 'ignores') {
    step('none', null, 'never opened the request and never answered');
    const after = doors.afterSilence ? await doors.afterSilence() : null;
    rec.platform_after_silence = after;
    rec.outcome = after == null ? 'ignored the request; what the platform did about it was not read in this mode' : after.length ? `ignored the request; the platform then: ${after.map((a) => a.what).join('; ')}` : 'ignored the request; the platform did nothing about it within the run';
    return rec;
  }
  if (sp.behaviour === 'clarifies_first') {
    const t0 = Date.now();
    const r = await doors.message(sp.question);
    const took = Math.round((Date.now() - t0) / 100) / 10;
    rec.question = { asked: sp.question, answer: r?.said ?? null, took_s: r?.not_run ? null : took, not_run: !!r?.not_run };
    if (r?.not_run) step('message', r, `asked "${sp.question}"; the quotation chat is not run in this mode, so no answer is claimed`);
    else step('message', r, r?.said ? `asked "${sp.question}" and the platform answered in ${took} s: "${String(r.said).slice(0, 240)}"` : `asked "${sp.question}" and got no answer${r?.http && r.http !== 200 ? ` (HTTP ${r.http})` : ''}`);
    if (!r?.said && !r?.not_run) { rec.outcome = 'asked a question first and got no answer, so did not quote'; return rec; }
    const pdf = await keep(`${sp.letterhead} - Quotation ${ref}.pdf`, 'application/pdf', quotePdf({ supplier: sp, rfq: job.rfq, ref, lines }));
    const u = await upload(`${sp.letterhead} - Quotation ${ref}.pdf`, 'application/pdf', pdf, 'after the answer, sent a typed PDF');
    rec.outcome = `asked first, ${r?.not_run ? 'the chat not run' : 'was answered'}, then quoted: ${u?.quote_id ? (u.accepted ? 'live' : u.held ? 'held' : 'stored') : 'no quotation made'}`;
    return rec;
  }
  if (sp.behaviour === 'range_subject_to_site_visit') {
    const sub = lines.reduce((a, l) => a + l.amount, 0); const low = Math.round(sub * sp.low / 100) * 100, high = Math.round(sub * sp.high / 100) * 100;
    rec.range = { low, high };
    const pdf = await keep(`${sp.letterhead} - Budget quotation ${ref}.pdf`, 'application/pdf', quotePdf({ supplier: sp, rfq: job.rfq, ref, lines, kind: 'range', low, high }));
    const u = await upload(`${sp.letterhead} - Budget quotation ${ref}.pdf`, 'application/pdf', pdf, `sent AED ${low.toLocaleString('en-US')} to ${high.toLocaleString('en-US')} "subject to site visit"`);
    rec.outcome = `a range subject to site visit: ${u?.quote_id ? (u.accepted ? `went live as AED ${u.read_amount ?? '?'} with nothing telling the customer it is a range` : u.held ? 'held' : 'stored') : `no quotation made${u?.code ? ' (' + u.code + ')' : ''}`}`;
    rec.range_reached_customer_as = u?.accepted ? (u.read_amount != null ? `AED ${u.read_amount}` : 'an amount') : null;
    return rec;
  }
  if (sp.behaviour === 'handwritten_photo') {
    const jpg = await keep(`IMG_${ref.replace(/\W/g, '')}.jpg`, 'image/jpeg', await handwrittenPhoto({ supplier: sp, lines, ref }));
    const u = await upload(`IMG_${ref.replace(/\W/g, '')}.jpg`, 'image/jpeg', jpg, 'sent a phone photo of his handwritten quotation');
    rec.outcome = `a handwritten photo: ${u?.quote_id ? (u.accepted ? 'live' : u.held ? 'held' : 'stored') : 'no quotation made'}${u?.read_amount != null ? ` (read AED ${u.read_amount}; he wrote ${Math.round(lines.reduce((a, l) => a + l.amount, 0))})` : ''}`;
    return rec;
  }
  if (sp.behaviour === 'proper_pdf') {
    const pdf = await keep(`${sp.letterhead} - Quotation ${ref}.pdf`, 'application/pdf', quotePdf({ supplier: sp, rfq: job.rfq, ref, lines }));
    const u = await upload(`${sp.letterhead} - Quotation ${ref}.pdf`, 'application/pdf', pdf, 'sent a typed PDF');
    rec.outcome = `a proper PDF: ${u?.quote_id ? (u.accepted ? 'live' : u.held ? 'held' : 'stored') : 'no quotation made'}`;
    return rec;
  }
  throw new Error(`unknown supplier behaviour ${sp.behaviour}`);
}
