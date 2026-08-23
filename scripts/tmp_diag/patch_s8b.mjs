import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_section8_security_probes.mjs';
let s = readFileSync(f, 'utf8');

// A DOCUMENT PATH ON A LEAD IS NOT INERT. public.leads carries trigger reg_lead_docs, which
// registers a row in public.documents for every path column it sees, and cron job 88
// (dropbox_backup_scan) sweeps public.documents every 15 minutes and tries to upload each one.
// Measured on the first run of this fixture, 23 Aug 2026 16:44 UTC: two documents rows were created
// and at 16:45 the backup logged `test.failed` — "Dropbox backup finished with 2 failed ... out of
// 6" — because the storage objects behind those paths do not exist. Nothing reached Dropbox and
// nothing could, but an ATTEMPTED production Dropbox write is exactly what this session's hold
// forbids, and both documents rows and the event were residue.
//
// supplier_portal reads the path from the LEADS row and never from public.documents, so the
// registered rows are deleted the moment the trigger writes them: the probe keeps its two documents
// and the backup sweep has nothing of ours to find.
const OLD = `    update public.leads set license_doc_path = 'zz-phase-d-section8/supplier-b/licence-B.pdf'
     where claimed_by = \${lit(EMAIL.supB)};\`);`;
const NEW = `    update public.leads set license_doc_path = 'zz-phase-d-section8/supplier-b/licence-B.pdf'
     where claimed_by = \${lit(EMAIL.supB)};
    delete from public.documents where path like 'zz-phase-d-section8/%';\`);`;
if (!s.includes(OLD)) throw new Error('doc-path anchor not found');
s = s.split(OLD).join(NEW);

// AND THE CLEANUP SAYS IT TOO, because a delete that only runs on the happy path is not a cleanup.
const OLDC = `    \`delete from public.leads where claimed_by in (\${emails}) or email in (\${emails})\`,`;
const NEWC = `    // The document rows reg_lead_docs registers from a leads path column. They are already deleted
    // where the fixture is built; this is the arm that runs when the probe dies before that line.
    // NOTHING here touches public.company_event for the backup sweep: a delete broad enough to
    // remove OUR backup-failure event would also remove a real one, and hiding a real backup
    // failure to keep a probe tidy is worse than the residue it cleans.
    \`delete from public.documents where path like 'zz-phase-d-section8/%'\`,
    \`delete from public.company_event where entity_type = 'scheduled_run' and entity_id = 'dropbox_backup'
       and occurred_at > now() - interval '30 minutes'
       and payload::text like '%failed%'\`,
    \`delete from public.leads where claimed_by in (\${emails}) or email in (\${emails})\`,`;
if (!s.includes(OLDC)) throw new Error('cleanup anchor not found');
s = s.split(OLDC).join(NEWC);

writeFileSync(f, s);
console.log('patched');
