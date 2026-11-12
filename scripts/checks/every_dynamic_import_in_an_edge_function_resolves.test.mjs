// EVERY LITERAL DYNAMIC IMPORT IN AN EDGE FUNCTION RESOLVES TO A FILE (it_engineer, 12 Nov 2026; final audit F3).
// deno check passes a dynamic import whose target is missing; resilience_ping's supportVoice step failed "Module not
// found" 115 times from 10 Nov because ticks/customer_support.ts imported '../_shared/duty_voice.ts' (one level short).
// The gate's deno-all step also checks these targets as roots (scripts/ci/local_gate.mjs); this is its fast half.
//   node --test scripts/checks/every_dynamic_import_in_an_edge_function_resolves.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { edgeDynamicImports } from '../lib/edge_dynamic_imports.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('every literal relative import(...) under supabase/functions names a file that exists', () => {
  const { missing, targets } = edgeDynamicImports(REPO);
  assert.deepEqual(missing.map((m) => `${m.file}:${m.line} import('${m.spec}')`), []);
  assert.ok(targets.includes('supabase/functions/_shared/duty_voice.ts'), 'the supportVoice step\'s module is a checked root');
});

test('the scan finds a missing target, and ignores one named in a comment', () => {
  const repo = mkdtempSync(join(tmpdir(), 'qd-dynimp-'));
  try {
    mkdirSync(join(repo, 'supabase/functions/f/ticks'), { recursive: true });
    mkdirSync(join(repo, 'supabase/functions/_shared'), { recursive: true });
    writeFileSync(join(repo, 'supabase/functions/_shared/v.ts'), 'export const v = 1;\n');
    writeFileSync(join(repo, 'supabase/functions/f/ticks/t.ts'),
      "const a = await import('../_shared/v.ts');\nconst b = await import('../../_shared/v.ts');\n// see import('./gone.ts')\n");
    const r = edgeDynamicImports(repo);
    assert.deepEqual(r.missing, [{ file: 'supabase/functions/f/ticks/t.ts', line: 1, spec: '../_shared/v.ts' }]);
    assert.deepEqual(r.targets, ['supabase/functions/_shared/v.ts']);
  } finally { rmSync(repo, { recursive: true, force: true }); }
});
