// Recover the Stage B.6 migrations from supabase_migrations.schema_migrations into
// supabase/migrations/, and verify every file against the SHA-256 in
// supabase/migrations/STAGE_B6_RECOVERY_MANIFEST.md.
//
// The SQL never passes through an assistant's context: this runs on the machine that owns the repo.
//
//   node scripts/recover_stage_b6.mjs
//
// Requires a Supabase personal access token at %USERPROFILE%\.supabase\access-token
// (or the SUPABASE_ACCESS_TOKEN environment variable). Create one at
// https://supabase.com/dashboard/account/tokens
//
// The token is read, used, and never written anywhere.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';
const FROM = '20260802181006';
const TO = '20260802183212';
const OUT_DIR = join(process.cwd(), 'supabase', 'migrations');

// Repo filenames use a 2026080222* prefix, in the original execution order.
const EXPECTED = [
  ['20260802181006', 'p2_c1_stage_b6_frozen_holdout_schema', 'f0e8659ea527ea7f4e5e538490724fe5aa2976392a00fdc7a7dee692cef445e3'],
  ['20260802181147', 'p2_c1_stage_b6_frozen_holdout_cases', 'e785329adb291c1efb69e6d38b00f56c9551f256105187c9cd1fe4a38b5c6beb'],
  ['20260802181351', 'p2_c1_stage_b6_scope_disposition_schema', '9027eb00f0d9dda56421ddee2cb9b15bd98027c826b0c1df0a0a16ccd0138e76'],
  ['20260802181524', 'p2_c1_stage_b6_scope_detection_and_resolution', '8f750626c1f688efb9cc0d4a2ac80c5767b4707c1a910a25f8c48990f120012a'],
  ['20260802181729', 'p2_c1_stage_b6_fix_trade_aggregation_and_english_plurals', '4974901c57c353b74aec2cfb33a6a243adbabab8f60a8d812801d12832a98ce8'],
  ['20260802181851', 'p2_c1_stage_b6_dispatch_integration_and_tests', 'fb60097f411ed91a010b6172837f4eb30b781094a96434385b224f9126f490bc'],
  ['20260802181932', 'p2_c1_stage_b6_fix_arabic_internal_definite_article', '41bff6141f4f177e700f761874a578800cf33bbff0957fd0bde28f33d6be4196'],
  ['20260802182107', 'p2_c1_stage_b6_fix_regex_aware_term_position', '7d7a5bb4be82b0e9e63ef21b4ee271749589874eb64d68fcf774fe869678d9e7'],
  ['20260802182230', 'p2_c1_stage_b6_blocker_rename_compat', '3b66e052956c42d6bf22c25f0be9bdf5bc557989b78976ea9e37c70300435b71'],
  ['20260802182259', 'p2_c1_stage_b6_holdout_runner', 'cba0bb644ec36baae1269575c21b019e12594404bb8f73a0d536d23e7425435b'],
  ['20260802182423', 'p2_c1_stage_b6_fix_scope_adjacency_separator', '179c9b90ce342fcf6b752bfa486f9f6e930e0a7490635ef3299dc83202418a68'],
  ['20260802182544', 'p2_c1_stage_b6_operator_rollback', '57e61e516b9cb0a909e305dbdd49376b2240a91e8e6e4240dbbd4a468b65ae77'],
  // Applied after the original manifest window; found by the "nothing in production absent from
  // the repository" check. Creates p2c1_holdout_result_of_record (immutable by trigger).
  ['20260802183212', 'p2_c1_holdout_v1_result_of_record', '33be6f4351e857f32d5ab795d2b23689b3dabafa3d6bec8d280ec6d527ee1a75'],
];

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  console.error('No Supabase access token.');
  console.error('Create one at https://supabase.com/dashboard/account/tokens and save it to:');
  console.error('  ' + p);
  process.exit(2);
}

async function query(sql) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!res.ok) {
    console.error(`Management API ${res.status}: ${await res.text()}`);
    process.exit(3);
  }
  return res.json();
}

const rows = await query(`
  select version, name, array_to_string(statements, E';\\n') || ';' as sql
    from supabase_migrations.schema_migrations
   where version between '${FROM}' and '${TO}'
   order by version`);

if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

let ok = 0, bad = 0;
console.log('idx  repo file                                                       sha256   bytes');
rows.forEach((r, i) => {
  const exp = EXPECTED[i];
  const sha = createHash('sha256').update(r.sql, 'utf8').digest('hex');
  const seq = String(i + 1).padStart(2, '0');
  const file = `2026080222${seq}_${r.name}.sql`;

  if (!exp || exp[0] !== r.version || exp[1] !== r.name) {
    console.error(`DRIFT: position ${i + 1} is ${r.version}/${r.name}, manifest says ${exp ? exp[0] + '/' + exp[1] : '(nothing)'}`);
    bad++; return;
  }
  if (sha !== exp[2]) {
    console.error(`DRIFT: ${r.name} hashes ${sha}, manifest says ${exp[2]}`);
    bad++; return;
  }

  const header =
    `-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.\n` +
    `-- Applied version: ${r.version}   name: ${r.name}\n` +
    `-- SHA-256 of the applied SQL: ${sha}\n` +
    `-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;\n` +
    `-- only this header was added, and it is excluded from the checksum.\n\n`;

  writeFileSync(join(OUT_DIR, file), header + r.sql, 'utf8');
  console.log(`${seq}   ${file.padEnd(62)} ${sha.slice(0, 8)} ${r.sql.length}`);
  ok++;
});

console.log(`\n${ok} recovered and checksum-verified, ${bad} drifted, ${rows.length} returned.`);
if (bad > 0 || rows.length !== EXPECTED.length) {
  console.error('RECOVERY INCOMPLETE - do not commit. Report the drift above.');
  process.exit(1);
}
console.log('All twelve match the manifest. Safe to commit.');
