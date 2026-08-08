// verify_customer_documents.mjs — SPEC §14, the Document Intelligence Vault, proven by EXECUTION.
//
// It builds TWO real customers on staging with real auth users, gives each documents that only
// they should see, and then tries to read each customer's vault as the OTHER customer — through
// PostgREST directly (which is where the RLS policy either holds or does not) and through the
// customer_documents endpoint. Everything it creates is torn down on the way out, including on a
// throw, because withRun() has the finally.
//
// It also proves the two things a "customer sees only their own" check cannot: that the SUPPLIER'S
// NAME on a quotation file stays null until the reveal fee is paid, and that expiry / coverage come
// out of the extraction rather than out of a filename.
//
//   node scripts/staging/verify_customer_documents.mjs
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, makeReveal,
         uploadObject, keys, q, jb, BASE, REF } from './demo_factory.mjs';
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';

const out = [];
let failures = 0;
const check = (name, ok, evidence) => {
  out.push(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(46)} ${evidence}`);
  if (!ok) failures++;
};

// A document read straight from PostgREST with the customer's own JWT. This is the RLS policy on
// its own, with no edge function in the way — if the policy is wrong, this is where it shows.
async function restDocs(jwt) {
  const { ANON } = await keys();
  const r = await fetch(`${BASE}/rest/v1/documents?select=id,kind,ref_table,ref_id&order=id`, {
    headers: { apikey: ANON, Authorization: 'Bearer ' + (jwt || ANON) },
  });
  const t = await r.text();
  let j = null; try { j = JSON.parse(t); } catch { /* the body is the finding */ }
  return { status: r.status, rows: Array.isArray(j) ? j : [], raw: t.slice(0, 200) };
}

async function fn(jwt, body) {
  const { ANON } = await keys();
  const r = await fetch(`${BASE}/functions/v1/customer_documents`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: 'Bearer ' + (jwt || ANON), 'Content-Type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(60000),
  });
  const t = await r.text();
  let j = null; try { j = JSON.parse(t); } catch { /* */ }
  return { status: r.status, json: j, raw: t.slice(0, 300) };
}

// license_extract's cert mode really returns this shape; doc_extract's returns the other one.
// Both are read by fn_customer_documents, so the fixtures carry one of each.
const CERT_EXTRACTION = {
  doc_type: 'manufacturer', issuer: 'Falcon Climate Systems FZE', reference: 'WTY-2026-8841',
  issue_date: '2026-06-01', expiry_date: '2031-05-31', covers: 'Full system', confidence: 'high',
};
const DOCX_EXTRACTION = {
  text: 'Ground floor mechanical layout. Duct runs and diffuser positions for the villa. '
      + 'Chilled water risers shown in section B.',
  specifications: ['galvanised steel duct 0.8mm', 'insulated 25mm'], brands: [], models: [],
  dates: ['2026-06-14'], quantities: ['180 sqm'], certifications: [],
};
const PLUMB_EXTRACTION = {
  text: 'Public liability insurance schedule covering plumbing and drainage works in Sharjah.',
  specifications: [], brands: [], models: [], dates: ['2027-01-31'], quantities: [],
  certifications: ['ISO 9001'],
};

await withRun(async (run) => {
  console.log(`staging ${REF}`);

  // ---- fixtures ------------------------------------------------------------------------------
  const A = await makeCustomer(run, {});
  const B = await makeCustomer(run, {});
  if (!A.jwt || !B.jwt) throw new Error('a fixture customer has no JWT; nothing below would mean anything');

  const inqA = await makeInquiry(run, {
    customer: A, trade: 'aluminium', emirate: 'Dubai',
    summary: 'Supply and install HVAC ducting and aluminium louvres for a villa in Dubai',
    raw_input: 'We need HVAC ducting, air conditioning diffusers and aluminium louvres supplied and installed for a private villa in Dubai.',
  });
  const inqB = await makeInquiry(run, {
    customer: B, trade: 'carpentry', emirate: 'Sharjah',
    summary: 'Supply and install kitchen joinery for an apartment in Sharjah',
    raw_input: 'We need kitchen cabinets and wardrobes supplied and installed for an apartment in Sharjah.',
  });

  const sup = await makeSupplier(run, { trade: 'aluminium', withAuth: false });
  const quoteA = await makeQuote(run, { inquiry: inqA, supplier: sup, amount: 96000 });

  // ---- 0. THE REAL CALLER. fn_register_document was replaced in place, and three deployed
  // triggers depend on it. Calling it directly proves the new body; only an INSERT that fires
  // trg_reg_inquiry_doc proves the callers still bind to it.
  const trigPath = `qd-${run.tag}/villa-floorplan.png`;
  await uploadObject('drawing-files', trigPath, new TextEncoder().encode('\x89PNG demo'), 'image/png');
  const inqT = await makeInquiry(run, {
    customer: A, trade: 'aluminium', emirate: 'Dubai',
    drawing_file_path: trigPath, drawing_file_name: 'villa-floorplan.png',
  });
  const trigRow = (await mgmtRead(REF,
    `select kind, ref_table, ref_id, file_name from public.documents
      where bucket='drawing-files' and path=${q(trigPath)}`))[0];
  check('trg_reg_inquiry_doc still registers through the new body',
    !!trigRow && trigRow.kind === 'drawing' && trigRow.ref_table === 'inquiries' && trigRow.ref_id === String(inqT.id),
    trigRow ? `inquiry ${inqT.id} insert produced documents row kind=${trigRow.kind} ref=${trigRow.ref_table}:${trigRow.ref_id} file=${trigRow.file_name}`
            : 'the trigger produced NO documents row — the registrar path is broken');

  // ---- 1. fn_register_document: one spelling per kind ----------------------------------------
  // The six kinds the spec names, entered through the aliases a caller would actually type, plus
  // every kind the three deployed registrars already pass — those must come out unchanged.
  const bucket = 'agent-docs';
  const p = (n) => `qd-${run.tag}/${n}`;
  const REG = [
    ['agreement',  p('hvac-warranty-agreement.pdf'), 'inquiries', inqA.id, 'contract'],
    ['Quotation',  p('quotation.pdf'),               'quotes',    quoteA.id, 'quote'],
    ['BILL',       p('invoice.pdf'),                 'inquiries', inqA.id, 'invoice'],
    ['PO',         p('purchase-order.pdf'),          'inquiries', inqA.id, 'purchase_order'],
    ['cert',       p('insurance-schedule.pdf'),      'inquiries', inqB.id, 'certificate'],
    ['dwg',        p('mech-layout.pdf'),             'inquiries', inqA.id, 'drawing'],
    ['licence',    p('trade-licence.pdf'),           'leads',     sup.leadId, 'licence'],
    ['catalog',    p('catalogue.pdf'),               'leads',     sup.leadId, 'catalog'],
    ['profile',    p('profile.pdf'),                 'leads',     sup.leadId, 'profile'],
    ['egr',        p('egr.pdf'),                     'leads',     sup.leadId, 'egr'],
  ];
  for (const [kind, path] of REG) await uploadObject(bucket, path, new TextEncoder().encode('%PDF-1.4 demo\n'), 'application/pdf');
  await mgmtWrite(REF, REG.map(([kind, path, rt, rid]) =>
    `select public.fn_register_document(${q(bucket)}, ${q(path)}, ${q(kind)}, ${q(rt)}, ${q(String(rid))}, ${q(path.split('/').pop())});`).join('\n'),
    'register fixture documents');

  const kinds = await mgmtRead(REF,
    `select path, kind from public.documents where bucket=${q(bucket)} and path like ${q(`qd-${run.tag}/%`)} order by path`);
  const kindOf = Object.fromEntries(kinds.map((r) => [r.path, r.kind]));
  const wrong = REG.filter(([, path, , , want]) => kindOf[path] !== want)
    .map(([kindIn, path, , , want]) => `${kindIn}->${kindOf[path] ?? 'MISSING'} (want ${want})`);
  check('fn_register_document canonical kinds', wrong.length === 0,
    `${REG.length} aliases in, ${REG.length - wrong.length} landed on the canonical kind` +
    (wrong.length ? `; wrong: ${wrong.join(', ')}` : `: ${REG.map(([k, path]) => `${k}=${kindOf[path]}`).join(', ')}`));

  // ---- 2. give the extraction something real to be searched ----------------------------------
  const setEx = async (path, ex) => mgmtWrite(REF,
    `upd${''}ate public.documents set status='done', extracted=${jb(ex)}, indexed=false,
       processed_at=now(), mime='application/pdf'
     where bucket=${q(bucket)} and path=${q(path)}`, 'fixture extraction');
  await setEx(p('hvac-warranty-agreement.pdf'), CERT_EXTRACTION);
  await setEx(p('mech-layout.pdf'), DOCX_EXTRACTION);
  await setEx(p('insurance-schedule.pdf'), PLUMB_EXTRACTION);

  const idOf = Object.fromEntries((await mgmtRead(REF,
    `select id, path from public.documents where bucket=${q(bucket)} and path like ${q(`qd-${run.tag}/%`)}`))
    .map((r) => [r.path, Number(r.id)]));
  const aWarranty = idOf[p('hvac-warranty-agreement.pdf')];
  const bInsurance = idOf[p('insurance-schedule.pdf')];
  const supLicence = idOf[p('trade-licence.pdf')];

  // ---- 3. THE ISOLATION, at the policy ---------------------------------------------------------
  const rA = await restDocs(A.jwt);
  const rB = await restDocs(B.jwt);
  const rAnon = await restDocs(null);
  const aIds = new Set(rA.rows.map((r) => Number(r.id)));
  const bIds = new Set(rB.rows.map((r) => Number(r.id)));

  check('customer A reads its own documents', rA.status === 200 && aIds.has(aWarranty),
    `HTTP ${rA.status}, ${rA.rows.length} row(s): ${[...aIds].join(',') || 'none'} (A's warranty doc is ${aWarranty})`);
  check('customer A CANNOT read B document', !aIds.has(bInsurance),
    `B's insurance doc ${bInsurance} ${aIds.has(bInsurance) ? 'IS VISIBLE TO A — LEAK' : 'is not in A\'s ' + rA.rows.length + ' row(s)'}`);
  check('customer B CANNOT read A document', rB.status === 200 && !bIds.has(aWarranty),
    `HTTP ${rB.status}, B sees ${rB.rows.length} row(s): ${[...bIds].join(',') || 'none'}; A's warranty doc ${aWarranty} ${bIds.has(aWarranty) ? 'IS VISIBLE — LEAK' : 'is absent'}`);
  check('anon reads nothing', rAnon.rows.length === 0,
    `HTTP ${rAnon.status}, ${rAnon.rows.length} row(s) ${rAnon.rows.length ? 'LEAK' : ''}`.trim());
  const total = Number((await mgmtRead(REF, 'select count(*)::int n from public.documents'))[0]?.n || 0);
  check('the table is bigger than either vault', rA.rows.length < total && rB.rows.length < total,
    `documents holds ${total} row(s); A sees ${rA.rows.length}, B sees ${rB.rows.length}`);

  // ---- 4. THE ENDPOINT: list ------------------------------------------------------------------
  const listA = await fn(A.jwt, { action: 'list' });
  const listB = await fn(B.jwt, { action: 'list' });
  const listAIds = new Set((listA.json?.documents || []).map((d) => Number(d.id)));
  check('endpoint list is scoped', listA.status === 200 && listAIds.has(aWarranty) && !listAIds.has(bInsurance),
    `A: HTTP ${listA.status} ${listA.json?.count} doc(s) kinds=[${(listA.json?.kinds || []).join(',')}]; ` +
    `B: HTTP ${listB.status} ${listB.json?.count} doc(s); A sees B's insurance doc: ${listAIds.has(bInsurance)}`);

  // ---- 5. THE ENDPOINT: the spec's own question ------------------------------------------------
  const askA = await fn(A.jwt, { action: 'ask', q: 'Find warranty documents for HVAC' });
  const hits = askA.json?.documents || [];
  const w = hits.find((d) => Number(d.id) === aWarranty);
  check('ask returns the warranty document', askA.status === 200 && !!w,
    `HTTP ${askA.status}, ${hits.length} hit(s): ${hits.map((d) => `${d.id}:${d.kind}:${d.match_reason}`).join(', ') || 'none'}`);
  check('ask answers with supplier / expiry / coverage',
    !!w && w.expiry_date === '2031-05-31' && w.covers === 'Full system',
    w ? `expiry_date=${w.expiry_date} (${w.expiry_source}), covers=${JSON.stringify(w.covers)} (${w.covers_source}); answer: ${(askA.json?.answer || [])[0] || 'none'}`
      : 'the warranty document did not come back at all');
  const related = hits.filter((d) => d.match_reason === 'related_request').map((d) => d.id);
  check('NL widening reaches documents whose own text never says HVAC', related.length > 0,
    `matched_by=${JSON.stringify(askA.json?.matched_by)}, related refs matched=${askA.json?.searched?.related_requests_matched}; ` +
    `related-only hits: ${related.join(',') || 'none'} (the mechanical drawing is ${idOf[p('mech-layout.pdf')]})`);

  const askB = await fn(B.jwt, { action: 'ask', q: 'Find warranty documents for HVAC' });
  const bHits = (askB.json?.documents || []).map((d) => Number(d.id));
  check('the same question from B returns nothing of A\'s', !bHits.includes(aWarranty),
    `HTTP ${askB.status}, ${bHits.length} hit(s): ${bHits.join(',') || 'none'}; empty_reason=${askB.json?.empty_reason}`);

  // ---- 6. THE ENDPOINT: get, and the cross-customer refusal -------------------------------------
  const getA = await fn(A.jwt, { action: 'get', id: aWarranty });
  check('get returns the file to its owner', getA.status === 200 && !!getA.json?.document?.file_url,
    `HTTP ${getA.status}, file_url=${getA.json?.document?.file_url ? 'signed' : 'null'}, ` +
    `expiry=${getA.json?.document?.expiry_date}, covers=${JSON.stringify(getA.json?.document?.covers)}`);
  const getCross = await fn(B.jwt, { action: 'get', id: aWarranty });
  check('get REFUSES another customer\'s document', getCross.status === 404,
    `B asked for A's document ${aWarranty}: HTTP ${getCross.status} ${JSON.stringify(getCross.json?.error || getCross.raw)}`);

  // ---- 7. THE REVEAL GATE ----------------------------------------------------------------------
  // Pre-reveal the quotation file is A's to read, but the company behind it is not A's to know.
  const preQuote = (listA.json?.documents || []).find((d) => d.source === 'quote');
  const preLicence = listAIds.has(supLicence);
  check('pre-reveal: quotation file visible, supplier name is not',
    !!preQuote && preQuote.supplier === null && preQuote.supplier_revealed === false && !preLicence,
    preQuote ? `quote doc ${preQuote.id}: supplier=${JSON.stringify(preQuote.supplier)}, revealed=${preQuote.supplier_revealed}; ` +
               `supplier's own trade licence ${supLicence} in A's vault: ${preLicence}`
             : 'the quotation document was not in A\'s vault at all');

  await makeReveal(run, { quote: quoteA, inquiry: inqA, supplier: sup, customer: A });
  const listA2 = await fn(A.jwt, { action: 'list', limit: 100 });
  const postDocs = listA2.json?.documents || [];
  const postQuote = postDocs.find((d) => d.source === 'quote');
  const postLicence = postDocs.find((d) => Number(d.id) === supLicence);
  check('post-reveal: the supplier is named and their licence appears',
    !!postQuote && postQuote.supplier_revealed === true && !!postQuote.supplier && !!postLicence,
    `quote doc supplier=${JSON.stringify(postQuote?.supplier)} revealed=${postQuote?.supplier_revealed}; ` +
    `supplier documents now in A's vault: ${postDocs.filter((d) => d.source === 'supplier').map((d) => `${d.id}:${d.kind}`).join(',') || 'none'}; ` +
    `A's vault went from ${listA.json?.count} to ${listA2.json?.count} document(s)`);

  const rB2 = await restDocs(B.jwt);
  check('B is unaffected by A\'s reveal', !rB2.rows.map((r) => Number(r.id)).includes(supLicence),
    `B still sees ${rB2.rows.length} row(s): ${rB2.rows.map((r) => r.id).join(',') || 'none'}`);
}, { tag: process.env.QD_RUN_TAG || undefined });

console.log('');
for (const l of out) console.log(l);
console.log('');
console.log(failures === 0 ? `ALL GOOD — ${out.length}/${out.length} checks passed` : `FAILURES: ${failures}/${out.length}`);
process.exit(failures === 0 ? 0 : 1);
