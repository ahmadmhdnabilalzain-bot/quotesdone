#!/usr/bin/env node
// Writes the "Depends-on: #N" line the release train honours into the PRs that were opened as a
// chain before the train existed (it_engineer, 29 Sep 2026). Idempotent: a PR whose body already
// names a dependency on its Depends-on line is left alone for that number.
//   node scripts/archive/it/add_depends_on.mjs [--dry-run]
import { execFileSync } from 'node:child_process';
import { dependsOn } from '../../it/release_train.mjs';

const CHAINS = {
  1065: [964], 1070: [1065], 1066: [1036], 1063: [1013], 1055: [1052], 1064: [1004],
  1050: [1040, 1041], 1071: [1043], 1043: [1047], 1067: [1040, 1042, 1044],
};
const DRY = process.argv.includes('--dry-run');
const gh = (args, input) => execFileSync('gh', args, { encoding: 'utf8', input });

for (const [pr, deps] of Object.entries(CHAINS)) {
  const { body, state } = JSON.parse(gh(['pr', 'view', pr, '--json', 'body,state']));
  if (state !== 'OPEN') { console.log(`#${pr} is ${state}, skipped`); continue; }
  const missing = deps.filter((d) => !dependsOn(body).includes(d));
  if (!missing.length) { console.log(`#${pr} already depends on ${deps.map((d) => '#' + d).join(', ')}`); continue; }
  const line = `Depends-on: ${missing.map((d) => '#' + d).join(', ')}`;
  console.log(`#${pr} ${DRY ? 'would add' : 'adds'}: ${line}`);
  if (!DRY) gh(['pr', 'edit', pr, '--body-file', '-'], `${(body || '').trimEnd()}\n\n${line}\n`);
}
