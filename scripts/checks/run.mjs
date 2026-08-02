// Runs every *.test.mjs in this directory with the Node built-in test runner.
//
// Deliberately no test framework. The repository had zero tests and no runner; adding Vitest or
// Jest to get these four files running would mean a dependency tree, a config file and a version to
// keep current, for something `node --test` already does. When the suite grows past what this can
// express - browser E2E, snapshot testing - that is the moment to add a framework, not before.
//
//   npm test            - run everything
//   node scripts/checks/run.mjs
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const files = fs.readdirSync(HERE).filter((f) => f.endsWith('.test.mjs')).sort()
  .map((f) => path.join(HERE, f));

if (!files.length) {
  console.error('no test files found in scripts/checks - that is itself a failure');
  process.exit(1);
}

console.log(`running ${files.length} check file(s):\n  ${files.map((f) => path.basename(f)).join('\n  ')}\n`);
const res = spawnSync(process.execPath, ['--test', ...files], { stdio: 'inherit' });
process.exit(res.status ?? 1);
