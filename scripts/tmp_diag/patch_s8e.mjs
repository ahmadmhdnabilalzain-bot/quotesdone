import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_section8_security_probes.mjs';
let s = readFileSync(f, 'utf8');

// THE DOCUMENT ROW WAS NOT THE END OF THE CHAIN. public.documents feeds
// public.fn_enqueue_doc_backups, which writes public.doc_backups, and THAT is the queue cron job 88
// drains — it retries a row up to five times and survives the deletion of the document that
// produced it. Measured 23 Aug 2026: deleting the two documents rows at 17:06 did not stop the
// sweeps at 17:15 and 17:30, because doc_backups 46209 and 46210 were still queued with
// "download Object not found" and attempts 4 of 5. Cleaning the table you happened to write is not
// cleaning up; the chain has to be followed to its end.
//
// iban_doc_path means no documents row is registered and nothing is ever enqueued, so this delete
// should find nothing. It is here because the version that reasoned "the documents row is gone,
// therefore nothing downstream holds it" was wrong once already.
const OLDC = `    \`delete from public.documents where path like 'zz-phase-d-section8/%'\`,`;
const NEWC = `    \`delete from public.doc_backups where path like 'zz-phase-d-section8/%'\`,
    \`delete from public.documents where path like 'zz-phase-d-section8/%'\`,`;
if (!s.includes(OLDC)) throw new Error('cleanup anchor not found');
s = s.split(OLDC).join(NEWC);

// and the zero-effect assertion counts it, so a survivor is a stop rather than a note
const OLDW = `  (select count(*) from public.leads)                       as leads,`;
const NEWW = `  (select count(*) from public.doc_backups)                 as docbackups,
  (select count(*) from public.leads)                       as leads,`;
if (s.includes(OLDW)) s = s.split(OLDW).join(NEWW);

writeFileSync(f, s);
console.log('patched');
