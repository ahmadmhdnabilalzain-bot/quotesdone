import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_section8_security_probes.mjs';
let s = readFileSync(f, 'utf8');

s = s.split('license_doc_path').join('iban_doc_path');

const DEL = "    delete from public.documents where path like 'zz-phase-d-section8/%';";
s = s.split(DEL + '\n').join('');
s = s.split('\n' + DEL).join('');

const OLDC = '  // uploaded, and no new table is written.';
const NEWC = [
  '  // uploaded, and no new table is written.',
  '  //',
  '  // THE COLUMN CHOSEN IS THE WHOLE FIX. public.leads carries',
  '  //   AFTER UPDATE OF (license_doc_path, company_profile_doc_path, egr_doc_path, catalog_doc_paths)',
  '  //   trigger reg_lead_docs',
  '  // which registers a row in public.documents for every path it sees, and cron job 88',
  '  // (dropbox_backup_scan) sweeps public.documents every 15 minutes and tries to upload each one.',
  '  // Measured on the first two runs of this fixture: two documents rows appeared and the backup',
  '  // logged a Dropbox backup finishing with 2 failed documents, at 16:45 and again at 17:00:05 UTC',
  '  // on 23 Aug 2026. Nothing reached Dropbox and nothing could -- the storage objects behind those',
  '  // paths do not exist -- but an ATTEMPTED production Dropbox write is exactly what the automation',
  '  // hold forbids. Deleting the registered rows in the next statement was tried and is not enough:',
  '  // the management endpoint commits each statement on its own and the sweep ran inside that window.',
  '  //',
  '  // iban_doc_path is in no watch list of that trigger, so no public.documents row is registered at',
  '  // all and there is no window. supplier_portal exposes it through DOC_KINDS exactly as it exposes',
  '  // the licence, so the probe loses nothing: each supplier still holds one document of its own.',
].join('\n');
if (!s.includes(OLDC)) throw new Error('comment anchor not found');
s = s.split(OLDC).join(NEWC);

writeFileSync(f, s);
console.log('patched; iban_doc_path:', s.includes('iban_doc_path'), '| delete gone:', !s.includes(DEL));
