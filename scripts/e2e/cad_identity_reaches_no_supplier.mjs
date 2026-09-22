// scripts/e2e/cad_identity_reaches_no_supplier.mjs — a customer's CAD file reaches the matched supplier as a
// take-off with none of the file's own names in it. ON PRODUCTION, with ZZ DEMO only. Assigned: sales_engineer.
//
// WHY IT EXISTS (founder, 22 Sep 2026: "have you checked if the sales engineer is removing the project details
// from the drawings perfectly without affecting them?"). A DXF or DWG is never pictured for a supplier; what
// reaches them is the take-off, and the take-off was written from the file's layer names, block names and
// title-block text. Measured in process before the fix (supabase/functions/_shared/cad_identity.ts header):
// a consultant's firm, the project name, a layer prefix and a logo block were all served. This walks it live:
//   1. a ZZ DEMO customer and a ZZ DEMO HVAC supplier (scripts/e2e/fixtures.mjs);
//   2. a SYNTHETIC ZZ DXF whose title block names a consultant and a project that are NOT the customer;
//   3. customer_api analyze_document (the portal's route for .dxf) -> the BOQ the portal will send;
//   4. the intake, customer_api create_inquiry -> the live matcher;
//   5. the supplier's inbox and its inquiry PDF, read back for every identity string;
// then everything is torn down and the teardown is proved. Before customer_api / supplier_api carry
// cad_identity, steps 3 and 5 FAIL on the identity checks — that is the evidence of the leak.
//
//   node scripts/e2e/cad_identity_reaches_no_supplier.mjs          run, report, tear down
//
// NOTHING HERE CAN REACH A REAL PERSON: identities are ZZ DEMO / @example.invalid / +9715000000xx, and a
// demo request is never matched to a real supplier (the database's demo guards).
import { openRun, closeRun, leftovers, makeDemoCustomer, makeDemoSupplier, read, call, waitFor } from './fixtures.mjs';
import { runIntake } from '../staging/demo_factory.mjs';

const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`); return !!ok; };

// The same drawing as consultantDxf() in supabase/functions/_shared/cad_identity.test.ts.
export const IDENTITY = ['ORBIT', 'HARBOUR', 'KEYSTONE', 'ORBITENG', 'ZZORBIT', 'ZZ.DRAFTER'];
const pairs = (p) => p.map(([c, v]) => `${String(c).padStart(3)}\n${v}`).join('\n') + '\n';
const sec = (name, body) => [[0, 'SECTION'], [2, name], ...body, [0, 'ENDSEC']];
const line = (layer, x1, y1, x2, y2) => [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
const ins = (b, x) => [[0, 'INSERT'], [8, 'M-EQPM'], [2, b], [10, x], [20, 0], [30, 0]];
export function consultantDxf() {
  return Buffer.from(pairs([
    ...sec('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$PROJECTNAME'], [1, 'ZZ HARBOUR TOWER'], [9, '$LASTSAVEDBY'], [1, 'zz.drafter'], [9, '$INSUNITS'], [70, 4]]),
    ...sec('BLOCKS', [[0, 'BLOCK'], [8, '0'], [2, 'KEYSTONE_TITLEBLOCK_A1'], [70, 0], [10, 0], [20, 0], [30, 0],
      [0, 'TEXT'], [8, '0'], [10, 0], [20, 0], [40, 100], [1, 'ZZ ORBIT CONSULTING ENGINEERS'], [0, 'ENDBLK']]),
    ...sec('ENTITIES', [
      ...line('ZZORBIT-M-DUCT', 0, 0, 12000, 0), ...line('ZZORBIT-M-DUCT', 0, 500, 12000, 500),
      ...ins('SMOKE_DET', 100), ...ins('SMOKE_DET', 200), ...ins('ORBITENG_LOGO', 0),
      [0, 'INSERT'], [8, 'TITLE'], [2, 'KEYSTONE_TITLEBLOCK_A1'], [66, 1], [10, 0], [20, 0],
      [0, 'ATTRIB'], [8, 'TITLE'], [10, 0], [20, -600], [40, 100], [1, 'ZZ HARBOUR TOWER'], [2, 'PROJ_NAME'],
      [0, 'SEQEND'], [8, 'TITLE'],
      [0, 'TEXT'], [8, 'A-ANNO'], [10, 0], [20, -700], [40, 100], [1, 'ZZ HARBOUR TOWER - 24 NOS FCU'],
      [0, 'MTEXT'], [8, 'M-ANNO'], [10, 0], [20, -900], [40, 100], [1, 'SUPPLY 12 NOS DIFFUSERS AS PER ZZ ORBIT CONSULTING ENGINEERS SPEC\\P6 NOS EXHAUST FANS'],
    ]),
    [0, 'EOF'],
  ]), 'utf8');
}
const leaked = (v) => { const s = JSON.stringify(v ?? '').toUpperCase(); return IDENTITY.filter((x) => s.includes(x)); };

const run = await openRun();
let exitCode = 1;
try {
  const hvac = await makeDemoSupplier(run, { trade: 'hvac', label: 'HVAC' });
  check('a ZZ DEMO HVAC supplier approved with the mandatory six', hvac.row?.approval_status === 'approved', String(hvac.leadId));
  const cust = await makeDemoCustomer(run, { label: 'CAD' });
  check('a ZZ DEMO customer with a complete account', !!cust.customerId, cust.email);

  const dxf = consultantDxf();
  const an = await call('customer_api', cust.jwt, { action: 'analyze_document', file_b64: dxf.toString('base64'), mime: 'image/vnd.dxf', file_name: 'ZZ mechanical layout.dxf', hint: 'HVAC ductwork, Dubai' }, 120000);
  const res = an.json || {};
  const lines = res?.boq?.boq || [];
  check('analyze_document read the DXF', an.status === 200 && res.ok === true && lines.length > 0, `HTTP ${an.status}, ${lines.length} lines ${res.error || ''}`);
  console.log('INFO  the BOQ the portal holds:\n' + lines.map((l) => `        ${l.section} | ${l.description} | ${l.qty} ${l.unit}`).join('\n'));
  check('no name from the file in the BOQ the portal will send', leaked(lines).length === 0, JSON.stringify(leaked(lines)));
  const q = (re) => lines.filter((l) => re.test(String(l.description))).map((l) => l.qty);
  check('every quantity survives (FCU 24, diffusers 12, fans 6)', q(/FCU/)[0] === 24 && q(/DIFFUSERS/)[0] === 12 && q(/EXHAUST FANS/)[0] === 6, JSON.stringify([q(/FCU/), q(/DIFFUSERS/), q(/EXHAUST FANS/)]));
  check('the customer is told the CAD file itself is not shared', res.drawing_held === true && res.share_redacted === false, `drawing_held ${res.drawing_held}`);

  const answers = [
    'Budget around AED 90,000. HVAC only: supply and install ductwork, fan coil units, diffusers and exhaust fans in an existing office in Dubai, as per the attached CAD take-off.',
    'Quantities are in the attached take-off: 24 FCU, 12 supply diffusers, 6 exhaust fans, 24 m of duct.',
    'Scope: supply and install, including testing, balancing and commissioning. No ceiling works.',
    'Materials: galvanised steel ductwork, standard commercial grade. Warranty: 12 months minimum.',
    'Needed by 30 November 2026. Ground floor, direct vehicle access.',
  ];
  const reply = (m) => /warranty/i.test(m) ? '12 months warranty at least.' : /by when|date|deliver/i.test(m) ? 'Needed by 30 November 2026.'
    : /ceiling|partition/i.test(m) ? 'None.' : /air conditioning|split|ducted|cassette/i.test(m) ? 'Ducted fan coil units, as drawn.'
    : /used for|how big|size of|area/i.test(m) ? 'Offices, about 600 square metres.' : /install/i.test(m) ? 'Supply and installation.' : 'Standard commercial specification.';
  let intake = await runIntake({ ...cust, jwt: cust.jwt, email: cust.email }, answers, answers.length);
  for (let turn = 0; turn < 6 && intake.status !== 'ready' && intake.intakeId; turn++) {
    const r = await call('inquiry_intake', cust.jwt, { intake_id: intake.intakeId, text: intake.missing.map(reply).join(' '), email: cust.email, drawing_boq: res.boq });
    intake = { ...intake, status: r.json?.status ?? intake.status, missing: Array.isArray(r.json?.missing) ? r.json.missing.map(String) : [], turns: intake.turns + 1 };
  }
  check('the intake reached ready', intake.status === 'ready', `${intake.status}, missing ${intake.missing.join(', ')}`);
  const drawing = { drawing_file_path: res.drawing_file_path, drawing_file_name: res.drawing_file_name, drawing_redacted_paths: [], boq: res.boq, brief_source: 'drawing', share_redacted: false };
  const ci = await call('customer_api', cust.jwt, { action: 'create_inquiry', intake_id: intake.intakeId, category: 'hvac', emirate: 'Dubai', trades: ['hvac'], scope_type: 'single', summary: 'ZZ DEMO HVAC per CAD take-off', raw_input: answers.join('\n'), spec: {}, drawing }, 120000);
  const iid = ci.json?.id ?? ci.json?.inquiry_id ?? null;
  check('create_inquiry posted the request', !!iid, `HTTP ${ci.status} ${ci.text?.slice(0, 200)}`);
  if (iid) {
    run.ids.inquiries.add(iid);
    const matched = await waitFor(async () => { const m = await read(`select m.supplier_id, l.is_demo from public.inquiry_matches m join public.leads l on l.id = m.supplier_id where m.inquiry_id = '${iid}'`); return m.some((x) => String(x.supplier_id) === String(hvac.leadId)) ? m : null; }, { timeoutMs: 90000, everyMs: 15000 }).catch(() => null);
    check('the live matcher matched the ZZ DEMO HVAC supplier, and only demo suppliers', !!matched && matched.every((m) => m.is_demo === true));
    const inbox = await call('supplier_api', hvac.jwt, { action: 'inbox', inquiry_id: iid });
    const item = (inbox.json?.inquiries || [])[0];
    check('the supplier sees the request', !!item, `HTTP ${inbox.status}`);
    check('no name from the file anywhere in what the supplier is served', !!item && leaked(item).length === 0, JSON.stringify(leaked(item)));
    check('the supplier is told a file exists that is not shown', item?.drawing_withheld === true, `drawing_withheld ${item?.drawing_withheld}`);
    check('the supplier still receives the take-off', Array.isArray(item?.boq?.boq) && item.boq.boq.length > 0, `${item?.boq?.boq?.length ?? 0} lines, withheld ${item?.boq_withheld}`);
    const pdfR = await call('supplier_api', hvac.jwt, { action: 'inquiry_pdf', inquiry_id: iid, lang: 'en' }, 120000);
    if (pdfR.json?.url) {
      const bytes = Buffer.from(await (await fetch(pdfR.json.url)).arrayBuffer());
      const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
      const doc = await pdfjs.getDocument({ data: new Uint8Array(bytes), verbosity: 0 }).promise;
      let text = '';
      for (let p = 1; p <= doc.numPages; p++) text += (await (await doc.getPage(p)).getTextContent()).items.map((x) => x.str).join(' ') + '\n';
      check('no name from the file in the inquiry PDF the supplier downloads', leaked(text).length === 0, JSON.stringify(leaked(text)));
    } else check('the supplier downloads the inquiry PDF', false, `HTTP ${pdfR.status} ${pdfR.text?.slice(0, 200)}`);
  }
  exitCode = results.every((r) => r.ok) ? 0 : 1;
} catch (e) {
  check('the run completed', false, String(e?.stack || e).slice(0, 600));
} finally {
  try { await closeRun(run); } catch (e) { console.log(`teardown throttled (${e?.status || e}); retrying in 60 s`); await new Promise((r) => setTimeout(r, 60000)); await closeRun(run); }
  const left = await leftovers(run); check('teardown left nothing behind', left.total === 0, JSON.stringify(left)); if (left.total) exitCode = 1;
  console.log(`\n${results.filter((r) => r.ok).length}/${results.length} checks passed`);
  process.exit(exitCode);
}
