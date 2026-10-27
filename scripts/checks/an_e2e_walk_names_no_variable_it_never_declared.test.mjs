// AN E2E WALK NAMES NO VARIABLE IT NEVER DECLARED (27 Oct 2026, it_engineer; independent review of PR #1654).
//
// PR #1654 added `step(m, 'the form shows the mobile verified', mobileOk)` to the INVITED leg of
// scripts/e2e/supplier_registration_walk.mjs, but `mobileOk` is declared only inside freshLeg(). `node --check` parses
// the file happily; the first invited leg then dies with "ReferenceError: mobileOk is not defined" before its profile,
// Services and teardown-confirm steps run. A walk is the founder's proof that a journey works, so a walk that cannot
// reach its own steps must fail here, offline, not at 03:00 against production.
//
// How: TypeScript's checker reads each walk as JavaScript (checkJs) and reports TS2304/TS2552 "Cannot find name" for
// every identifier with no declaration in scope. Only those two codes are read; type opinions about plain JS are not.
//   node --test scripts/checks/an_e2e_walk_names_no_variable_it_never_declared.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const root = fileURLToPath(new URL('../../', import.meta.url));
const UNDECLARED = new Set([2304, 2552]);

function undeclared(files) {
  const p = ts.createProgram(files, {
    allowJs: true, checkJs: true, noEmit: true, skipLibCheck: true, types: ['node'],
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
  });
  const want = new Set(files);
  return ts.getPreEmitDiagnostics(p)
    .filter((d) => d.file && want.has(d.file.fileName) && UNDECLARED.has(d.code))
    .map((d) => `${d.file.fileName.replace(root, '')}:${d.file.getLineAndCharacterOfPosition(d.start).line + 1} ${ts.flattenDiagnosticMessageText(d.messageText, ' ')}`);
}

test('the supplier registration walk declares every name it uses', () => {
  const found = undeclared([root + 'scripts/e2e/supplier_registration_walk.mjs']);
  assert.deepEqual(found, [], found.join('\n'));
});

test('known-bad control: a name used outside the function that declares it is caught', async () => {
  const { mkdtempSync, writeFileSync } = await import('node:fs');
  const { join } = await import('node:path');
  const { tmpdir } = await import('node:os');
  const f = join(mkdtempSync(join(tmpdir(), 'qd-undecl-')), 'bad.mjs');
  writeFileSync(f, 'function leg() { const mobileOk = true; return mobileOk; }\nleg();\nconsole.log(mobileOk);\n');
  const found = undeclared([f]);
  assert.equal(found.length, 1, found.join('\n'));
  assert.match(found[0], /mobileOk/);
});

test('the guarded walk is still at its path', () => {
  const walks = readdirSync(root + 'scripts/e2e').filter((n) => n.endsWith('_walk.mjs'));
  assert.ok(walks.includes('supplier_registration_walk.mjs'), 'the walk this check guards has moved; update the path');
});
