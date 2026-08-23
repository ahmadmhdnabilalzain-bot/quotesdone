import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/tmp_diag/patch_rscl2.mjs';
let p = readFileSync(f, 'utf8');
// The real file ends the DO block with `end $case$;` followed by the backtick; the patch was
// written without the semicolon.
const BAD = 'end $case$\\`;\n}';
const GOOD = 'end $case$;\\`;\n}';
const n = p.split(BAD).length - 1;
p = p.split(BAD).join(GOOD);
writeFileSync(f, p);
console.log('replaced', n);
