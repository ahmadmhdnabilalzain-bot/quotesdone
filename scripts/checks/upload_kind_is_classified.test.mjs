// The upload classifier in customer_api action='analyze_drawing' must keep telling a customer what
// to do about a file we cannot read.
//
// Spec #7 §3 names "a customer uploads a ZIP file instead of a PDF" and "a PDF is corrupted" as two
// of its sixteen exception scenarios. Measured 11 Aug 2026 before changing anything: neither
// crashed - both fell through to one generic note, 'no_readable_pages', which is true and useless.
// A compressed archive, a corrupt file and a password-protected file were indistinguishable to the
// person who has to fix them, and sending a ZIPPED DRAWING SET is normal practice in UAE
// construction.
//
// This check reads the predicates OUT OF THE DEPLOYED SOURCE rather than restating them, so it
// fails if someone edits the regexes in customer_api and not the expectations here. A check that
// carries its own copy of the logic it is checking cannot catch a change to that logic.
//
//   node scripts/checks/upload_kind_is_classified.test.mjs

import { readFileSync } from 'node:fs';

const SRC = 'supabase/functions/customer_api/index.ts';
const src = readFileSync(SRC, 'utf8');

function extract(label, re) {
  const m = src.match(re);
  if (!m) {
    console.error(`FAIL  could not find the ${label} predicate in ${SRC}.`);
    console.error('      It was renamed or removed. Update this check deliberately - do not delete it.');
    process.exit(1);
  }
  return m[1];
}

// eslint-disable-next-line no-new-func
const mk = (body) => new Function('name', 'mime', `return ${body};`);

const isCad = mk(extract('isCad', /const isCad\s*=\s*([^;]+);/));
const isArchive = mk(extract('isArchive', /const isArchive\s*=\s*([\s\S]*?);\s*\n\s*if \(!images\.length\)/));

const note = (name, mime) =>
  isCad(name, mime) ? 'cad_not_converted'
    : isArchive(name, mime) ? 'archive_not_supported'
      : 'no_readable_pages';

const CASES = [
  // the scenario that actually happens in this market
  ['drawings.zip', 'application/zip', 'archive_not_supported'],
  ['SET-A.RAR', 'application/x-rar-compressed', 'archive_not_supported'],
  ['plans.7z', 'application/x-7z-compressed', 'archive_not_supported'],
  ['bundle.tar.gz', 'application/gzip', 'archive_not_supported'],
  ['tender.tgz', 'application/octet-stream', 'archive_not_supported'],
  // CAD keeps its own advice - export to PDF, not "extract the archive"
  ['villa.dwg', 'application/acad', 'cad_not_converted'],
  ['section.dxf', 'application/octet-stream', 'cad_not_converted'],
  // everything else is the corrupt/unreadable branch
  ['plan.pdf', 'application/pdf', 'no_readable_pages'],
  ['scan.jpg', 'image/jpeg', 'no_readable_pages'],
  // FALSE-POSITIVE TRAPS. A real drawing must never be told to extract an archive.
  ['zipper-factory-layout.pdf', 'application/pdf', 'no_readable_pages'],
  ['gazebo.pdf', 'application/octet-stream', 'no_readable_pages'],
  ['rargate-elevation.pdf', 'application/pdf', 'no_readable_pages'],
];

let failed = 0;
for (const [name, mime, want] of CASES) {
  const got = note(name, mime);
  if (got !== want) {
    failed++;
    console.error(`FAIL  ${name} (${mime}) -> ${got}, expected ${want}`);
  }
}

if (failed) {
  console.error(`\n${failed} of ${CASES.length} misclassified.`);
  process.exit(1);
}
console.log(`upload classifier: ${CASES.length}/${CASES.length} correct (predicates read live from ${SRC})`);
