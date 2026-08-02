// Two-directional check between supabase/migrations and the applied record in
// supabase_migrations.schema_migrations.
//
//   A. every applied production migration has a repository counterpart
//   B. every repository migration intended as applied exists in production
//   C. every recovered file is byte-identical to the applied SQL (SHA-256)
//   D. no two repository files claim the same applied version
//
// Recovered files carry a header line "-- Applied version: <14 digits>"; the body
// after the header block is the verbatim applied SQL. Files without that header
// are matched by filename version only - the Supabase CLI rewrites what it records
// for hand-authored files, so a checksum there would be meaningless.
//
// Results are split into the P2-C1 window and everything else, because the wider
// repository has a long-standing gap that this work item did not create and must
// not be allowed to hide.
//
//   node scripts/verify_repo_production_parity.mjs
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const MIG = join(process.cwd(), 'supabase', 'migrations');
const WIN_FROM = '20260802165328', WIN_TO = '20260802183212';
const inWindow = v => v >= WIN_FROM && v <= WIN_TO;

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  console.error('No Supabase access token.'); process.exit(2);
}

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: `select version, name,
                   encode(extensions.digest(array_to_string(statements, E';\\n') || ';', 'sha256'), 'hex') as sha
              from supabase_migrations.schema_migrations order by version`,
  }),
});
if (!res.ok) { console.error(`Management API ${res.status}: ${await res.text()}`); process.exit(3); }
const prod = await res.json();
const prodByVersion = new Map(prod.map(r => [r.version, r]));
const prodByName = new Map(prod.map(r => [r.name, r]));

const files = readdirSync(MIG).filter(f => f.endsWith('.sql')).sort();
const claimed = new Map();
const A = { win: [], other: [] };
const B = { win: [], other: [], unversioned: [] };
const C = [];
const D = [];
const E = [];   // applied, but under a version different from the repository filename
let recovered = 0, plain = 0;

for (const f of files) {
  const raw = readFileSync(join(MIG, f), 'utf8');
  const m = raw.match(/^-- Applied version: (\d{14})/m);
  const version = m ? m[1] : (f.match(/^(\d{14})_/) || [])[1];
  if (!version) { B.unversioned.push(f); continue; }

  if (!claimed.has(version)) claimed.set(version, []);
  claimed.get(version).push(f);

  const p = prodByVersion.get(version);
  if (!p) {
    const byName = prodByName.get(f.replace(/^\d{14}_/, '').replace(/\.sql$/, ''));
    if (byName) {
      E.push(`${f} -> applied as version ${byName.version} (${byName.name}); filename version ${version} is not the applied one`);
    } else {
      (inWindow(version) ? B.win : B.other).push(`${f} -> claims applied version ${version}, not in production by version or by name`);
    }
    continue;
  }

  if (m) {
    recovered++;
    const shaIdx = raw.indexOf('-- SHA-256 of the applied SQL:');
    const blank = shaIdx < 0 ? -1 : raw.indexOf('\n\n', shaIdx);
    if (blank < 0) { C.push(`${f}: recovery header not parseable`); continue; }
    const body = raw.slice(blank + 2);
    const sha = createHash('sha256').update(body, 'utf8').digest('hex');
    if (sha !== p.sha) C.push(`${f}: body sha ${sha} != applied sha ${p.sha}`);
  } else {
    plain++;
  }
}

for (const [v, fs] of claimed) if (fs.length > 1) D.push(`applied version ${v} claimed by ${fs.join(', ')}`);
for (const r of prod) if (!claimed.has(r.version)) (inWindow(r.version) ? A.win : A.other).push(`${r.version} ${r.name}`);

const P2 = prod.filter(r => inWindow(r.version));
console.log(`production migrations, all             : ${prod.length}`);
console.log(`production migrations, P2-C1 window    : ${P2.length}   (${WIN_FROM} .. ${WIN_TO})`);
console.log(`repository files in supabase/migrations: ${files.length}`);
console.log(`  recovered, checksum-verifiable       : ${recovered}`);
console.log(`  hand-authored, version match only    : ${plain}`);
console.log(`  no version at all                    : ${B.unversioned.length}`);
console.log('');
console.log('=== P2-C1 WINDOW (this work item) ===');
console.log(`A. applied in production, absent from repository : ${A.win.length}`);
A.win.forEach(x => console.log(`   - ${x}`));
console.log(`B. in repository, not applied in production      : ${B.win.length}`);
B.win.forEach(x => console.log(`   - ${x}`));
console.log(`C. checksum drift in recovered files             : ${C.length}`);
C.forEach(x => console.log(`   - ${x}`));
console.log(`D. duplicate claims on one applied version       : ${D.length}`);
D.forEach(x => console.log(`   - ${x}`));
const winTotal = A.win.length + B.win.length + C.length + D.length;
console.log(`E. applied under a different version than the filename : ${E.length}`);
E.forEach(x => console.log(`   - ${x}`));
console.log(`\nP2-C1 window: ${winTotal === 0 ? 'PARITY OK - zero drift in either direction.' : `${winTotal} PROBLEM(S).`}`);
console.log('');
console.log('=== PRE-EXISTING, OUTSIDE THIS WORK ITEM ===');
console.log(`applied in production, absent from repository : ${A.other.length}`);
console.log(`in repository, not applied in production      : ${B.other.length}`);
B.other.forEach(x => console.log(`   - ${x}`));
console.log(`repository files with no version prefix       : ${B.unversioned.length}`);
process.exit(winTotal === 0 ? 0 : 1);
