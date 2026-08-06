const fs = require('fs');
const s = fs.readFileSync('docs/phases/PHASE1_INDEPENDENT_AUDIT.md', 'utf8');
const want = process.argv[2];
const i = s.indexOf(want);
if (i < 0) { console.log('NOT FOUND: ' + want); process.exit(0); }
const end = s.indexOf('\n### ', i + 5);
console.log(s.slice(i, end > 0 ? Math.min(end, i + 3200) : i + 3200));
