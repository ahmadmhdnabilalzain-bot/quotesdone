// nocheck_files_have_no_redeclarations.test.mjs — a `// @ts-nocheck` file still cannot declare a name twice.
// node --test src/components/nocheck_files_have_no_redeclarations.test.mjs
//
// Measured 14 Sep 2026 (PR #657): SupplierPortal.tsx declared `const [wa, setWa]` twice in one function,
// and the Vercel build died on it ("the name `wa` is defined multiple times"). Nothing local caught it:
// CustomerPortal.tsx and SupplierPortal.tsx start with `// @ts-nocheck`, so `tsc --noEmit` reports
// nothing for them at all, and a plain SWC transform accepts the file (the error comes from Turbopack's
// resolve pass). TypeScript's BINDER still sees a redeclaration in a nocheck file, so this asks it
// directly, for every nocheck file under src, and fails on exactly the errors a build would die on.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import ts from 'typescript-js-api'; // TypeScript 7 (the native compiler) ships no JS API; the parser stays on 5.x

const SRC = join(import.meta.dirname, '..');
// 2451 cannot redeclare a block-scoped variable; 2300 duplicate identifier; 2323 cannot redeclare an
// exported variable; 2393 duplicate function implementation.
export const REDECLARATION = new Set([2451, 2300, 2323, 2393]);

/** The redeclaration diagnostics TypeScript's binder reports for one file, ignoring @ts-nocheck. */
export function redeclarations(fileName, text) {
  const body = text.replace(/^\s*\/\/\s*@ts-nocheck[^\n]*\n/, '\n');
  const host = ts.createCompilerHost({ noResolve: true, noLib: true, jsx: ts.JsxEmit.Preserve, allowJs: true });
  const orig = host.getSourceFile;
  host.getSourceFile = (n, v) => (n === fileName ? ts.createSourceFile(n, body, v, true, ts.ScriptKind.TSX) : orig.call(host, n, v));
  const program = ts.createProgram([fileName], { noResolve: true, noLib: true, jsx: ts.JsxEmit.Preserve, allowJs: true, types: [] }, host);
  const sf = program.getSourceFile(fileName);
  return program.getSemanticDiagnostics(sf).filter((d) => REDECLARATION.has(d.code))
    .map((d) => { const { line } = sf.getLineAndCharacterOfPosition(d.start || 0); return `${line + 1}: ${ts.flattenDiagnosticMessageText(d.messageText, ' ')}`; });
}

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const nocheck = walk(SRC).filter((f) => /\.(tsx?|jsx?)$/.test(f) && /^\s*\/\/\s*@ts-nocheck/.test(readFileSync(f, 'utf8')));

test('the detector catches a name declared twice in one function, and passes a clean file', () => {
  assert.ok(redeclarations('x.tsx', "// @ts-nocheck\nfunction F(){ const [wa, setWa] = useState(1); const [wa, setWa] = useState(2); return wa; }\n").length >= 1);
  assert.deepEqual(redeclarations('y.tsx', '// @ts-nocheck\nfunction F(){ const [wa, setWa] = useState(1); return wa; }\n'), []);
});

test('there are nocheck files to guard', () => {
  assert.ok(nocheck.length >= 2, 'expected at least the two portals: ' + nocheck.map((f) => relative(SRC, f)).join(', '));
});

test('no @ts-nocheck file under src declares a name twice', () => {
  const bad = nocheck.flatMap((f) => redeclarations(f, readFileSync(f, 'utf8')).map((m) => relative(SRC, f) + ':' + m));
  assert.deepEqual(bad, []);
});
