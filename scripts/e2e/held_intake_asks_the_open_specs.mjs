// scripts/e2e/held_intake_asks_the_open_specs.mjs — a held intake asks, and an answered one reaches suppliers.
// Assigned: sales_engineer (the intake and the take-off) with customer_support (the conversation). 27 Oct 2026.
//
// THE DEFECT (founder ledger 580, run 6dd2316c, 27 Oct 2026). A ZZ DEMO customer posted a drawing in the portal.
// The take-off and the redaction worked, then the intake answered `held` for every turn from the 4th on with
// questions=0, missing=[] and next_question=null (agent_runs inquiry_intake 07:52:38-07:53:44 UTC: three
// needs_info turns asking 4, 4 and 3 questions, then seven held turns asking none). create_inquiry answered 428
// intake_required, so there was no inquiry id and no BOQ PDF. A real customer would have been stuck the same way:
// the portal renders next_question / remaining_questions, and there were none to render.
//
// WHAT THIS RUN DOES, against the deployed functions or a local `deno run` of inquiry_intake (--local <url>):
//   1. the customer states the job the way run 6dd2316c did (with the drawing's take-off attached) and does not
//      answer the trade's core questions, so required keys stay open for three turns (slots.ts MAX_OPEN_TURNS);
//   2. every turn is recorded; a HELD turn with no question, no open key or no next_question is the defect;
//   3. the customer then answers exactly what the intake asks (a tap on an offered option, or plain words), until
//      the intake is ready;
//   4. create_inquiry posts the request with the drawing's BOQ; the ZZ DEMO HVAC supplier sees it and downloads
//      the BOQ PDF; every match is a demo supplier and no notice is addressed outside @example.invalid;
//   5. teardown, and a count that proves nothing was left.
//
//   node scripts/e2e/held_intake_asks_the_open_specs.mjs                       deployed functions
//   node scripts/e2e/held_intake_asks_the_open_specs.mjs --local http://127.0.0.1:8000   local inquiry_intake
//   ... --json <file>   the numbers; --keep   leave the fixtures standing
//
// NOTHING HERE CAN REACH A REAL PERSON: ZZ DEMO names, @example.invalid addresses, the fixture mobile block, and
// the database's demo guards (a demo account is never matched to a real one; its notices are captured). Models
// stay on (ruling 1260) inside a USD 3 rehearsal window.
import { openRun, closeRun, leftovers, makeDemoCustomer, makeDemoSupplier, openTradeForDemo, read, call, waitFor } from './fixtures.mjs';
import { keys, internalCred, BASE } from '../lib/demo_factory.mjs';

const arg = (k) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : null);
const LOCAL = arg('--local');
const JSON_OUT = arg('--json');
const KEEP = process.argv.includes('--keep');
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`); return !!ok; };
const summary = { ledger: 580, measured_at: new Date().toISOString(), intake_door: LOCAL ? `local ${LOCAL}` : 'deployed', turns: [] };

/** inquiry_intake, deployed or local. The local door gets the same headers the deployed one does. */
async function intake(jwt, body) {
  if (!LOCAL) return call('inquiry_intake', jwt, body, 120000);
  const { ANON } = await keys();
  const r = await fetch(LOCAL, { method: 'POST', signal: AbortSignal.timeout(120000),
    headers: { apikey: ANON, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json',
      ...(process.env.QD_E2E_RUN_TAG ? { 'x-qd-e2e-run': process.env.QD_E2E_RUN_TAG, 'x-qd-e2e-secret': await internalCred() } : {}) },
    body: JSON.stringify(body) });
  const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch { /* the body is the finding */ }
  return { status: r.status, json, text: text.slice(0, 200) };
}

// The drawing's take-off, as analyze_drawing returns it for the 8-sheet ZZ DEMO mechanical set (read by code).
const BOQ = { category: 'hvac', method: 'drawing_set', boq: [
  { item: 'EF-1', description: 'Exhaust fan EF-1', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'EF-2', description: 'Exhaust fan EF-2', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'RTU-1', description: 'Rooftop unit RTU-1', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'IRH-1', description: 'Infrared heater IRH-1', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'WC/L-1', description: 'Wall cap / louvre WC/L-1', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'Air device type A', description: 'Air device type A', qty: 2400, unit: 'nos', qty_status: 'counted' },
  { item: 'Duct 26x18', description: 'Supply ductwork 26x18', qty: 16432.8, unit: 'm', qty_status: 'measured' },
] };
// A customer who points at the drawings and answers nothing else for four turns, so the trade's required specs stay
// open through slots.ts MAX_OPEN_TURNS and the intake MUST hold. Run 6dd2316c's own wording (budget, take-off, scope,
// materials) reached the hold on 27 Oct 07:52 UTC, but whether a model files a key from it varies run to run: the
// same four messages, replayed on the deployed function at 10:05 UTC, had new_or_replace filed on turn 4 and never
// held. The case under test is the hold, so the opening is written to reach it every time.
const OPENING = [
  'HVAC works for our building, as per the attached drawings. Please quote.',
  'Everything is in the attached drawings.',
  'Please refer to the drawings, the take-off is attached.',
  'As per the drawings.',
];
// Plain answers by the key the intake names, for a question that offers no options to tap.
const BY_KEY = {
  application_area: 'Offices and storage, about 1,200 square metres, ceiling height 3 metres.',
  location: 'Dubai, Al Quoz, ground floor. The outdoor units go on the roof.',
};
const answerFor = (nq) => {
  const opts = Array.isArray(nq?.options) ? nq.options.filter((o) => !/not sure|survey|recommend|advise/i.test(o)) : [];
  if (nq?.key === 'system_type') return opts.find((o) => /package/i.test(o)) || opts[0];
  if (nq?.key === 'new_or_replace') return opts.find((o) => /new/i.test(o)) || opts[0];
  if (nq?.key === 'scope') return opts.find((o) => /supply and install/i.test(o)) || opts[0];
  if (nq?.key && BY_KEY[nq.key]) return BY_KEY[nq.key];
  if (opts.length) return opts.find((o) => /12|yes|supply and install|steel/i.test(o)) || opts[0];
  return 'Standard commercial specification, as drawn.';
};

const run = await openRun({ capUsd: 3, minutes: 60 });
summary.run_tag = run.tag;
let exitCode = 0;
try {
  const hvac = await makeDemoSupplier(run, { trade: 'hvac', label: 'HVAC' });
  // The request is posted in HVAC: the trade must be open for a demo customer first (fixtures.mjs openTradeForDemo).
  const opened = await openTradeForDemo(run, 'hvac', 1);
  check('HVAC is open for the demo customer at the trade-opening floor', opened.counted >= opened.floor, `${opened.counted} counted, floor ${opened.floor}, ${opened.bench.length} bench supplier(s) outside Dubai`);
  const cust = await makeDemoCustomer(run, { label: 'Held intake' });
  check('fixtures are demo identities', /@example\.invalid$/.test(cust.email) && /@example\.invalid$/.test(hvac.email || 'x@example.invalid'), `${cust.email}`);

  let intakeId = null, last = null;
  const turn = async (text) => {
    const r = await intake(cust.jwt, { ...(intakeId ? { intake_id: intakeId } : {}), text, email: cust.email, drawing_boq: BOQ });
    last = r.json || {};
    intakeId = last.intake_id || intakeId;
    const t = { n: summary.turns.length + 1, http: r.status, said: text.slice(0, 90), status: last.status ?? null, questions: (last.questions || []).length,
      next_key: last.next_question?.key ?? null, options: (last.next_question?.options || []).length, missing_keys: last.missing_keys || [],
      remaining: (last.remaining_questions || []).length, held_reason: last.held_reason ?? null };
    summary.turns.push(t);
    console.log(`turn ${t.n}: HTTP ${t.http} ${t.status} q=${t.questions} next=${t.next_key} opts=${t.options} open=[${t.missing_keys.join(',')}]${t.held_reason ? ' ' + t.held_reason : ''}`);
    return r;
  };

  for (const text of OPENING) { await turn(text); if (last.status === 'ready') break; }
  for (let i = 0; i < 14 && last.status !== 'ready' && intakeId; i++) {
    const nq = last.next_question;
    if (last.status === 'held' && !nq) break;          // the defect: nothing to answer
    await turn(nq ? answerFor(nq) : 'Standard commercial specification, as drawn.');
  }

  const held = summary.turns.filter((t) => t.status === 'held');
  summary.held_turns = held.length;
  summary.held_with_no_question = held.filter((t) => !t.questions || !t.next_key || !t.missing_keys.length).length;
  check('the intake was held for open specs at least once (the case under test)', held.length > 0, `${held.length} held turn(s)`);
  check('every held turn asks a specific open-spec question (questions, next_question.key, missing_keys)', held.length > 0 && summary.held_with_no_question === 0,
    `${summary.held_with_no_question} of ${held.length} held turns asked nothing`);
  check('every held question names a key the hold is waiting on', held.every((t) => t.next_key && t.missing_keys.includes(t.next_key)));
  check('the intake reached ready once the asked specs were answered', last.status === 'ready', `${last.status} after ${summary.turns.length} turns`);
  summary.final_status = last.status; summary.intake_id = intakeId;

  if (last.status === 'ready') {
    const ci = await call('customer_api', cust.jwt, { action: 'create_inquiry', intake_id: intakeId, emirate: 'Dubai', raw_input: OPENING.join('\n'),
      drawing: { boq: BOQ, brief_source: 'drawing', drawing_file_name: 'ZZ DEMO mechanical set.pdf' } }, 120000);
    const iid = ci.json?.id ?? ci.json?.inquiry_id ?? null;
    summary.create_inquiry_http = ci.status;
    check('create_inquiry posted the request (no 428)', !!iid, `HTTP ${ci.status} ${ci.text}`);
    if (iid) {
      run.ids.inquiries.add(iid); summary.inquiry_id = iid;
      const row = (await read(`select rfq_no, status, category, jsonb_array_length(coalesce(boq->'boq','[]'::jsonb)) n from public.inquiries where id = '${iid}'`))[0] || {};
      summary.rfq_no = row.rfq_no ?? null;
      check('the inquiry carries the drawing take-off', Number(row.n) === BOQ.boq.length, `rfq ${row.rfq_no}, ${row.n} lines, category ${row.category}, status ${row.status}`);
      const matched = await waitFor(async () => {
        const m = await read(`select m.supplier_id, l.is_demo, l.email from public.inquiry_matches m join public.leads l on l.id = m.supplier_id where m.inquiry_id = '${iid}'`);
        return m.some((x) => String(x.supplier_id) === String(hvac.leadId)) ? m : null;
      }, { timeoutMs: 120000, everyMs: 15000 }).catch(() => null);
      const all = matched || await read(`select m.supplier_id, l.is_demo, l.email from public.inquiry_matches m join public.leads l on l.id = m.supplier_id where m.inquiry_id = '${iid}'`);
      summary.matches = all.length; summary.real_matches = all.filter((x) => !x.is_demo).length;
      check('routed to the ZZ DEMO HVAC supplier', !!matched, `${all.length} match(es)`);
      check('no real supplier was matched to the demo inquiry', summary.real_matches === 0, `${summary.real_matches} non-demo of ${all.length}`);
      const out = (await read(`select count(*)::int n from public.notifications where inquiry_id = '${iid}' and coalesce(to_email,'') <> '' and to_email not ilike '%@example.invalid'`))[0];
      summary.notices_outside_demo = out.n;
      check('no notice about the inquiry is addressed outside @example.invalid', out.n === 0, `${out.n}`);
      const pdf = await call('supplier_api', hvac.jwt, { action: 'inquiry_pdf', inquiry_id: iid, lang: 'en' }, 120000);
      const m = /\/object\/sign\/([^/]+)\/([^?]+)/.exec(String(pdf.json?.url || ''));
      summary.boq_pdf = m ? { bucket: m[1], name: decodeURIComponent(m[2]) } : null;
      let bytes = 0;
      if (pdf.json?.url) { const b = Buffer.from(await (await fetch(pdf.json.url)).arrayBuffer()); bytes = b.length; summary.boq_pdf_ok = b.slice(0, 5).toString() === '%PDF-'; }
      check('the supplier downloads the BOQ PDF', !!summary.boq_pdf_ok, `HTTP ${pdf.status}, ${bytes} bytes`);
    }
  }
  const spend = (await read(`select round(coalesce(sum(cost_aed),0)/3.6725, 4) usd, count(*)::int calls from public.ai_cost_log where e2e_run_tag = '${run.tag}'`))[0];
  summary.spend_usd = Number(spend.usd); summary.model_calls = spend.calls;
  console.log(`INFO  model spend USD ${spend.usd} over ${spend.calls} calls`);
} catch (e) {
  check('the run completed', false, String(e?.stack || e).slice(0, 400)); exitCode = 1;
} finally {
  // The run's storage objects are named by the customer or the inquiry, not the tag; remove the BOQ PDF by name.
  if (!KEEP && summary.boq_pdf?.name) {
    const { SERVICE } = await keys();
    await fetch(`${BASE}/storage/v1/object/${summary.boq_pdf.bucket}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: [summary.boq_pdf.name] }) });
  }
  const closed = await closeRun(run, { keep: KEEP });
  if (!KEEP) {
    const left = closed.leftovers || await leftovers(run);
    summary.teardown = left;
    check('teardown left nothing behind', left.total === 0, JSON.stringify(left));
    if (summary.boq_pdf?.name) {
      const n = (await read(`select count(*)::int n from storage.objects where bucket_id = '${summary.boq_pdf.bucket}' and name = '${summary.boq_pdf.name.replace(/'/g, "''")}'`))[0].n;
      summary.boq_pdf_left = n;
      check('the BOQ PDF is gone from storage', n === 0, `${n}`);
    }
  }
  summary.checks = `${results.filter((r) => r.ok).length}/${results.length}`;
  summary.failed = results.filter((r) => !r.ok).map((r) => `${r.name}: ${r.detail}`);
  if (JSON_OUT) { const { writeFileSync } = await import('node:fs'); writeFileSync(JSON_OUT, JSON.stringify(summary, null, 1)); }
  console.log(`\n${summary.checks} checks passed`);
  if (results.some((r) => !r.ok)) exitCode = 1;
  process.exit(exitCode);
}
