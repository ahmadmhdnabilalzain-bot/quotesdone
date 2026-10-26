// verify_supplier_docs.mjs — supplier_api process_docs, end to end, and what the mandatory six decide.
//
// §3.1(a): "nothing writes to `supplier-docs` yet (0 objects) — the fixtures go through
// license_extract directly rather than through supplier_api process_docs, so the storage branch
// and the licence-gate write-back are still unexercised end to end."
//
// That is what this drives: a real supplier, holding a real JWT, uploading real PDF bytes to the
// real bucket through the deployed function. Every previous licence fixture wrote a FAKE
// license_doc_path (`supplier-docs/demo/<tag>/licence.pdf`) naming an object that was never
// uploaded, so the storage branch, the sanitiser and the write-back had never run in either project.
//
// TWO DEFECTS THIS FOUND BEFORE IT EVER RAN, both of the same shape as §2.2's 118 leaked objects:
//
//   1. demo_factory's teardown had NO rule for `supplier-docs`. Fixed in demo_factory.mjs; the
//      factory selftest's baseline check is what proves it, and check 16 below for this run.
//
//   2. process_docs discarded the result of its only database write, so a failed write returned
//      `{ok:true, extracted:{...}}` with nothing written. Fixed 5 Aug 2026. The checks assert the
//      ROW, never the response.
//
// REWRITTEN 15 SEP 2026 (it_engineer) — THE GATE IT ASSERTED IS GONE; THE SIX DECIDE NOW.
//   This file was written against fn_supplier_licence_gate and fn_leads_licence_gate_rerun, both
//   dropped 7 Sep 2026 (scripts/sql/DROPPED.txt, the two licence-gate lines). Since #698 approval is
//   trg_leads_e0_mandatory_six_gate + fn_sales_engineer_verifies_supplier, re-run by
//   z20_leads_mandatory_item_landed_reverifies whenever a mandatory column lands
//   (scripts/sql/the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql). And since
//   #705 makeSupplier hands back a supplier that already holds a licence and a profile, so
//   `objects('licenses/<id>/').length === 1` and `!after.license_doc_path` stopped meaning anything.
//   Every supplier here is now made with { approval: 'pending' }: inserted undecided, with NO
//   documents and no signed terms, so each document the run adds is the only one on the row.
//
//   Check "a readable licence does not open the licence gate" -> REWRITTEN as checks 7-10: the
//     licence landing moves the supplier to action_required on reg_profile (not reg_licence), the
//     profile landing moves it to reg_terms, the signed terms complete the six and the sales engineer
//     approves. Each one fails on a real regression: a licence the six do not count leaves reg_licence;
//     a dead z20 trigger leaves 'pending'; a verification that ignores storage approves early.
//   Check "storing evidence with no readable number opens the licence gate" -> RETIRED, its subject
//     was deleted. The six count the licence DOCUMENT (the founder's definition: "trade licence (a
//     DOCUMENT)"), not whether a model could read a number off it, so no gate opens on readability
//     any more. RETIRED RATHER THAN SOFTENED: rewritten to pass it would assert that an unreadable
//     licence does NOT open a gate — true of every build, including one where the six are gone.
//     What is still true and still checked: the evidence is stored and no number is invented (11-12),
//     and an incomplete supplier cannot be approved by writing the column (13, a negative probe).
//     TO REVIVE: build a readability rule into fn_supplier_mandatory_six, then assert it here.
//   Final check "teardown removes every supplier-docs object" asserted the bucket held 0 objects in
//     total. Production holds unrelated ones (24 on 15 Sep), so it could never pass. It now counts
//     THIS run's prefixes only (licenses/, profiles/, catalogs/ under this run's lead ids, plus the
//     signed-terms object), and first asserts the run actually created some, so 0 is not vacuous.
//
//     QD_FIXTURES=1 node scripts/staging/verify_supplier_docs.mjs      model calls: licence reads only
import { mgmtRead, mgmtFixture } from './qd_guard.mjs';
import { REF, call, q, num, withRun, makeSupplier, internalCred } from './demo_factory.mjs';
import { VALID_LICENCE, validLicencePdf, illegibleLicencePdf, pdfFromLines } from './fixtures/licence_pdf.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(62)} ${detail}`);
};

const b64 = (buf) => buf.toString('base64');
const objects = async (prefix) => await mgmtRead(REF,
  `select name, coalesce(metadata->>'size','?') size, coalesce(metadata->>'mimetype','?') mime
     from storage.objects where bucket_id='supplier-docs' and name like ${q(prefix + '%')} order by name`);
const lead = async (id) => (await mgmtRead(REF, `
  select company_name, name_corrected_from, license_doc_path, company_profile_doc_path, signed_terms_path,
         trade_license_no, license_authority, license_city, license_expiry::text, emirate, trn,
         approval_status, verified, approval_decided_by, licence_gate_reason,
         public.fn_supplier_mandatory_six(l) missing,
         doc_extracted_at is not null as extracted_stamped
    from public.leads l where id=${num(id)}`))[0];
const miss = (r) => JSON.stringify(r?.missing ?? null);
// Every storage object this run's suppliers can own, by the prefixes process_docs writes under.
const runObjects = async (ids) => ids.length ? Number((await mgmtRead(REF,
  `select count(*) n from storage.objects where bucket_id='supplier-docs' and (${ids.map((id) =>
    ['licenses', 'profiles', 'catalogs'].map((f) => `name like ${q(`${f}/${num(id)}/%`)}`).join(' or ')).join(' or ')})`))[0].n) : 0;

const leadIds = [];
const signedPaths = [];
let runTag = null;
let createdDuringRun = 0;

await withRun(async (run) => {
  runTag = run.tag;
  // ---- the readable licence, then the rest of the six ------------------------------------------
  const sup = await makeSupplier(run, { trade: 'aluminium', approval: 'pending' });
  leadIds.push(sup.leadId);
  const pre = await lead(sup.leadId);
  if (pre.license_doc_path || pre.company_profile_doc_path || pre.signed_terms_path) {
    throw new Error(`makeSupplier({approval:'pending'}) returned a supplier that already holds documents: ${JSON.stringify(pre)}`);
  }

  const r1 = await call('supplier_api', sup.jwt, {
    action: 'process_docs',
    license: {
      original_b64: b64(validLicencePdf()),      // the STORAGE branch
      file_b64: b64(validLicencePdf()),          // the EXTRACTION branch
      mime: 'application/pdf', filename: 'trade_licence_1145872.pdf',
    },
  }, 180000);

  step('a claimed supplier reaches process_docs with its own JWT',
    r1.status === 200 && r1.json?.ok === true,
    `HTTP ${r1.status} ${r1.status === 200 ? 'ok=' + r1.json?.ok : JSON.stringify(r1.json).slice(0, 160)}`);

  const stored = await objects(`licenses/${sup.leadId}/`);
  step('the licence is stored in supplier-docs — exactly one object for this supplier',
    stored.length === 1,
    stored.length ? `${stored.map((o) => `${o.name} (${o.size} bytes, ${o.mime})`).join('; ')}`
      : `no object under licenses/${sup.leadId}/`);

  const a = await lead(sup.leadId);
  step('leads.license_doc_path names that exact object',
    !!a.license_doc_path && stored.some((o) => o.name === a.license_doc_path),
    `license_doc_path=${a.license_doc_path || 'null'}`);

  // The response is NOT the evidence — see defect 2 in the header. These read the row.
  step('the extraction is written BACK to the row, not merely returned',
    a.trade_license_no === VALID_LICENCE.license_number && !!a.license_authority
      && !!a.license_expiry && !!a.emirate && a.extracted_stamped,
    `no=${a.trade_license_no || '-'} authority="${(a.license_authority || '').slice(0, 34)}" ` +
    `expiry=${a.license_expiry || '-'} emirate=${a.emirate || '-'} trn=${a.trn || '-'}` +
    (r1.json?.extracted?.license_error ? ` license_error=${r1.json.extracted.license_error}` : ''));

  step('the licence expiry is normalised to a real date in the future',
    !!a.license_expiry && a.license_expiry === VALID_LICENCE.expiry_date
      && new Date(a.license_expiry) > new Date(),
    `${a.license_expiry} (document prints ${VALID_LICENCE.expiry_date} as DD/MM/YYYY)`);

  step('the legal name on the licence corrects the typed company name',
    a.company_name === VALID_LICENCE.legal_name && a.name_corrected_from === pre.company_name,
    `"${pre.company_name}" -> "${a.company_name}" (name_corrected_from stamped=${!!a.name_corrected_from})`);

  // pending -> action_required is the z20 trigger re-running the sales engineer; reg_profile (not
  // reg_licence) is the six counting the stored licence. Either regression leaves a different value.
  step('the licence lands: the six count it, the profile is what is missing now',
    pre.approval_status === 'pending' && a.approval_status === 'action_required'
      && a.licence_gate_reason === 'reg_profile' && !(a.missing || []).includes('reg_licence'),
    `${pre.approval_status} ${miss(pre)} -> ${a.approval_status} reason=${a.licence_gate_reason || 'none'} missing=${miss(a)}`);

  const r2p = await call('supplier_api', sup.jwt, {
    action: 'process_docs',
    company_profile: {
      original_b64: b64(pdfFromLines(['COMPANY PROFILE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', a.company_name || '', `Run ${run.tag}`])),
      mime: 'application/pdf', filename: 'company_profile.pdf',
    },
  }, 90000);
  const profStored = await objects(`profiles/${sup.leadId}/`);
  const p = await lead(sup.leadId);
  step('the company profile lands: one object, named by the row, terms missing now',
    r2p.status === 200 && profStored.length === 1 && p.company_profile_doc_path === profStored[0]?.name
      && p.approval_status === 'action_required' && p.licence_gate_reason === 'reg_terms',
    `HTTP ${r2p.status} objects=${profStored.length} path=${p.company_profile_doc_path || 'null'} ` +
    `${p.approval_status} reason=${p.licence_gate_reason || 'none'} missing=${miss(p)}`);

  // The signed agreement: the same compliance_archive 'sign' qd_sign_supplier makes on acceptance.
  const auto = (await mgmtRead(REF, 'select coalesce(auto_approve_suppliers,false) a from public.pricing_config where id=1'))[0]?.a === true;
  const sg = await call('compliance_archive', null,
    { __secret: await internalCred(), action: 'sign', kind: 'supplier', id: Number(sup.leadId) });
  const s = await lead(sup.leadId);
  if (s.signed_terms_path) signedPaths.push(s.signed_terms_path);
  step('the signed terms land and the six are complete',
    sg.status === 200 && sg.json?.ok === true && !!s.signed_terms_path && Array.isArray(s.missing) && s.missing.length === 0,
    `sign HTTP ${sg.status} ok=${sg.json?.ok} signed_terms_path=${s.signed_terms_path ? 'set' : 'null'} missing=${miss(s)}`);

  const decisions = await mgmtRead(REF,
    `select detail->>'decision' d, detail->>'source' src from public.agent_actions
      where agent='sales_engineer' and kind='supplier_verification' and target_id=${q(String(sup.leadId))}
      order by created_at`);
  const want = auto ? 'approved' : 'pending';
  step('the sales engineer decides on the completed six, and records it',
    s.approval_status === want && s.verified === (want === 'approved') && s.approval_decided_by === 'sales_engineer'
      && !s.licence_gate_reason && decisions.at(-1)?.d === want,
    `${s.approval_status} verified=${s.verified} by=${s.approval_decided_by || '-'} (auto_approve=${auto}); ` +
    `decisions: ${decisions.map((d) => `${d.d}/${d.src}`).join(' -> ') || 'none'}`);

  // ---- the unreadable licence: evidence stored, no number invented ------------------------------
  const bad = await makeSupplier(run, { trade: 'hvac', approval: 'pending' });
  leadIds.push(bad.leadId);
  const badPre = await lead(bad.leadId);
  const r2 = await call('supplier_api', bad.jwt, {
    action: 'process_docs',
    license: {
      original_b64: b64(illegibleLicencePdf()), file_b64: b64(illegibleLicencePdf()),
      mime: 'application/pdf', filename: 'scan.pdf',
    },
  }, 180000);
  const b = await lead(bad.leadId);
  const badStored = await objects(`licenses/${bad.leadId}/`);

  step('an unreadable licence is still STORED — the evidence is kept, not discarded',
    r2.status === 200 && badStored.length === 1 && b.license_doc_path === badStored[0]?.name,
    `HTTP ${r2.status}, objects=${badStored.length}, path=${b.license_doc_path || 'null'}`);

  step('an unreadable licence invents no licence number',
    !b.trade_license_no,
    `trade_license_no=${b.trade_license_no || 'null'} (was ${badPre.trade_license_no || 'null'})`);

  // Negative probe: an incomplete supplier cannot be approved by writing the column. The gate is the
  // database's; if trg_leads_e0_mandatory_six_gate were dropped this UPDATE would succeed.
  let refusal = null;
  try {
    await mgmtFixture(REF, `update public.leads set approval_status='approved', verified=true where id=${num(bad.leadId)}`,
      'negative probe: approve an incomplete supplier');
  } catch (e) { refusal = String(e?.message || e); }
  const b2 = await lead(bad.leadId);
  step('the six gate refuses a direct approval while items are missing',
    !!refusal && /mandatory fields are incomplete/.test(refusal) && b2.approval_status !== 'approved' && !b2.verified,
    `${refusal ? 'refused: ' + refusal.replace(/\s+/g, ' ').slice(0, 90) : 'NOT refused'}; now ${b2.approval_status} missing=${miss(b2)}`);

  // ---- the sanitiser (AUDIT 9.1) ----------------------------------------------------------------
  // The defect this replaced: no type check at all, so an HTML document or an executable stored
  // cleanly as a supplier's trade licence and was later served back to an admin reviewer.
  const sup3 = await makeSupplier(run, { trade: 'electrical', approval: 'pending' });
  leadIds.push(sup3.leadId);
  const objBefore = (await objects(`licenses/${sup3.leadId}/`)).length;
  const r3 = await call('supplier_api', sup3.jwt, {
    action: 'process_docs',
    license: {
      original_b64: Buffer.from('<html><body><script>alert(1)</script></body></html>').toString('base64'),
      mime: 'application/pdf', filename: 'licence.pdf',
    },
  }, 90000);
  const objAfter = (await objects(`licenses/${sup3.leadId}/`)).length;
  step('a file whose bytes contradict its declared type is refused, and nothing is stored',
    r3.status === 415 && objAfter === objBefore,
    `HTTP ${r3.status} error=${r3.json?.error || '-'} objects ${objBefore} -> ${objAfter}`);

  const after = await lead(sup3.leadId);
  step('a refused upload leaves the row untouched',
    !after.license_doc_path && after.approval_status === 'pending',
    `license_doc_path=${after.license_doc_path || 'null'} approval_status=${after.approval_status}`);

  createdDuringRun = await runObjects(leadIds);
}, { tag: process.env.QD_RUN_TAG });

// ---- teardown, scoped to THIS run --------------------------------------------------------------
// Other rehearsals may be running against the same project, so nothing here reads a global total.
const leftObjects = await runObjects(leadIds);
const leftSigned = signedPaths.length ? Number((await mgmtRead(REF,
  `select count(*) n from storage.objects where bucket_id='signed-terms' and name in (${signedPaths.map(q).join(',')})`))[0].n) : 0;
step('teardown removes every storage object this run created',
  createdDuringRun >= 3 && leftObjects === 0 && signedPaths.length === 1 && leftSigned === 0,
  `supplier-docs under this run's ${leadIds.length} lead(s): ${createdDuringRun} during the run -> ${leftObjects} after; ` +
  `signed-terms ${signedPaths.length} -> ${leftSigned}`);

const leftLeads = leadIds.length ? Number((await mgmtRead(REF,
  `select count(*) n from public.leads where id in (${leadIds.map(num).join(',')}) or tags @> ARRAY[${q(`qd_run:${runTag}`)}]::text[]`))[0].n) : 0;
const leftUsers = Number((await mgmtRead(REF,
  `select count(*) n from auth.users where email like ${q(`qd-${runTag}-%`)}`))[0].n);
step('teardown removes this run\'s leads and auth users',
  leadIds.length === 3 && leftLeads === 0 && leftUsers === 0,
  `run ${runTag}: leads ${leftLeads} (ids ${leadIds.join(',')}), qd-${runTag}-% auth users ${leftUsers}`);

const failed = checks.filter((c) => !c.ok);
console.log(`\nSUPPLIER DOCS ${checks.length - failed.length}/${checks.length} on ${REF}`);
process.exit(failed.length ? 1 : 0);
