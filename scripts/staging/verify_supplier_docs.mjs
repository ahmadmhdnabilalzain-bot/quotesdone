// verify_supplier_docs.mjs — supplier_api process_docs, end to end, for the first time.
//
// §3.1(a): "nothing writes to `supplier-docs` yet (0 objects) — the fixtures go through
// license_extract directly rather than through supplier_api process_docs, so the storage branch
// and the licence-gate write-back are still unexercised end to end."
//
// That is what this drives: a real supplier, holding a real JWT, uploading real PDF bytes to the
// real bucket through the deployed function, and the licence gate re-evaluating on what came back
// out of the model. Every previous licence fixture wrote a FAKE license_doc_path
// (`supplier-docs/demo/<tag>/licence.pdf`) naming an object that was never uploaded, so the
// storage branch, the sanitiser and the write-back had never run in either project.
//
// TWO DEFECTS THIS FOUND BEFORE IT EVER RAN, both of the same shape as §2.2's 118 leaked objects:
//
//   1. demo_factory's teardown had NO rule for `supplier-docs`. It derives drawing-files,
//      quote-files, signed-terms and agent-docs from the rows that name them and stops there.
//      Nothing noticed because the bucket held 0 objects. Fixed in demo_factory.mjs; the factory
//      selftest's baseline check is what proves it, not this file.
//
//   2. process_docs discards the result of its only database write. The storage uploads above it
//      check `up.error` and return 502; line 361 is a bare
//      `await admin.from('leads').update(upd).eq('id', sup.id)` with no error capture, and every
//      extracted licence field, the storage path and the company-name correction all route
//      through it. A failure there returns `{ok:true, extracted:{...}}` with a full-looking
//      payload and nothing written — §5's "a step that returns HTTP 200 is not a step that
//      worked", on the registration path. Checks 4-7 below assert the ROW, never the response.
//
//     node scripts/staging/verify_supplier_docs.mjs      2 model calls, ~0.1 AED
import { mgmtRead } from './qd_guard.mjs';
import { REF, call, q, num, withRun, makeSupplier } from './demo_factory.mjs';
import { VALID_LICENCE, validLicencePdf, illegibleLicencePdf } from './fixtures/licence_pdf.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(52)} ${detail}`);
};

const b64 = (buf) => buf.toString('base64');
const objects = async (prefix) => await mgmtRead(REF,
  `select name, coalesce(metadata->>'size','?') size, coalesce(metadata->>'mimetype','?') mime
     from storage.objects where bucket_id='supplier-docs' and name like ${q(prefix + '%')} order by name`);
const lead = async (id) => (await mgmtRead(REF, `
  select company_name, name_corrected_from, license_doc_path, trade_license_no, license_authority,
         license_city, license_expiry::text, emirate, trn, approval_status, licence_gate_reason,
         doc_extracted_at is not null as extracted_stamped
    from public.leads where id=${num(id)}`))[0];

await withRun(async (run) => {
  const before = Number((await mgmtRead(REF,
    "select count(*) n from storage.objects where bucket_id='supplier-docs'"))[0].n);

  // ---- the readable licence ---------------------------------------------------------------------
  const sup = await makeSupplier(run, { trade: 'aluminium' });
  const pre = await lead(sup.leadId);

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
  step('the licence is stored in supplier-docs — the first object ever written there',
    stored.length === 1,
    stored.length
      ? `${stored[0].name} (${stored[0].size} bytes, ${stored[0].mime}); bucket held ${before} object(s) before this run`
      : `no object under licenses/${sup.leadId}/ — bucket held ${before} before`);

  const a = await lead(sup.leadId);
  step('leads.license_doc_path names that exact object',
    !!a.license_doc_path && stored.some((o) => o.name === a.license_doc_path),
    `license_doc_path=${a.license_doc_path || 'null'}`);

  // The response is NOT the evidence — see defect 2 in the header. These read the row.
  step('the extraction is written BACK to the row, not merely returned',
    a.trade_license_no === VALID_LICENCE.license_number && !!a.license_authority
      && !!a.license_expiry && !!a.emirate && a.extracted_stamped,
    `no=${a.trade_license_no || '-'} authority="${(a.license_authority || '').slice(0, 34)}" ` +
    `expiry=${a.license_expiry || '-'} emirate=${a.emirate || '-'} trn=${a.trn || '-'}`);

  step('the licence expiry is normalised to a real date in the future',
    !!a.license_expiry && a.license_expiry === VALID_LICENCE.expiry_date
      && new Date(a.license_expiry) > new Date(),
    `${a.license_expiry} (document prints ${VALID_LICENCE.expiry_date} as DD/MM/YYYY)`);

  step('the legal name on the licence corrects the typed company name',
    a.company_name === VALID_LICENCE.legal_name && a.name_corrected_from === pre.company_name,
    `"${pre.company_name}" -> "${a.company_name}" (name_corrected_from stamped=${!!a.name_corrected_from})`);

  step('a readable licence does not open the licence gate',
    a.approval_status !== 'action_required',
    `approval_status=${a.approval_status} gate_reason=${a.licence_gate_reason || 'none'}`);

  // ---- the unreadable licence: evidence stored, no number, gate opens ---------------------------
  const bad = await makeSupplier(run, { trade: 'hvac' });
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
    r2.status === 200 && badStored.length === 1 && !!b.license_doc_path,
    `HTTP ${r2.status}, object=${badStored.length}, path=${b.license_doc_path ? 'set' : 'null'}`);

  step('an unreadable licence invents no licence number',
    !b.trade_license_no,
    `trade_license_no=${b.trade_license_no || 'null'} (was ${badPre.trade_license_no || 'null'})`);

  step('storing evidence with no readable number opens the licence gate',
    b.approval_status === 'action_required',
    `${badPre.approval_status} -> ${b.approval_status}, reason="${(b.licence_gate_reason || '').slice(0, 58)}"`);

  // ---- the sanitiser (AUDIT 9.1) ----------------------------------------------------------------
  // The defect this replaced: no type check at all, so an HTML document or an executable stored
  // cleanly as a supplier's trade licence and was later served back to an admin reviewer.
  const sup3 = await makeSupplier(run, { trade: 'electrical' });
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
    !after.license_doc_path,
    `license_doc_path=${after.license_doc_path || 'null'} approval_status=${after.approval_status}`);
}, { tag: process.env.QD_RUN_TAG });

const leftover = Number((await mgmtRead(REF,
  "select count(*) n from storage.objects where bucket_id='supplier-docs'"))[0].n);
step('teardown removes every supplier-docs object the run created',
  leftover === 0,
  `${leftover} object(s) left in supplier-docs — the bucket had no teardown rule at all before today`);

const bad = checks.filter((c) => !c.ok);
console.log(`\nSUPPLIER DOCS ${checks.length - bad.length}/${checks.length} on ${REF}`);
process.exit(bad.length ? 1 : 0);
