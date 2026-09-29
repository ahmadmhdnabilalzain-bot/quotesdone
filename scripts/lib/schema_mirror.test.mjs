// The committed schema mirror is exactly what the writer would produce from its own joined text
// (29 Sep 2026, it_engineer). Fails when a part is hand-edited so content sits in the wrong part,
// when a section the cut rule relies on disappears, when the banner is not at the top, or when a
// cut lands anywhere but the start of a line. The 5 MiB ceiling per part is enforced separately,
// with no exemption, by scripts/checks/the_repository_root_holds_only_the_product.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PARTS, SCHEMA_MIRROR, readSchemaMirror, splitSchemaMirror } from './schema_mirror.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('the committed parts are the split of their own joined text', () => {
  const whole = readSchemaMirror();
  const split = splitSchemaMirror(whole);
  assert.equal(split.map((p) => p.text).join(''), whole, 'the parts do not rejoin to the mirror');
  for (const p of split) {
    const onDisk = readFileSync(join(REPO, SCHEMA_MIRROR, p.file), 'utf8');
    assert.equal(onDisk, p.text, `${p.file} does not hold what the cut rule puts there; regenerate the mirror`);
  }
});

test('the banner opens part 01 and every cut is at the start of a line', () => {
  const split = splitSchemaMirror(readSchemaMirror());
  assert.match(split[0].text, /^-- =+\n-- QuotesDone — FULL SCHEMA EXPORT\n/);
  split.slice(0, -1).forEach((p, i) => {
    if (p.text) assert.ok(p.text.endsWith('\n'), `${p.file} ends mid-line, so ${split[i + 1].file} starts mid-line`);
  });
});

test('each routine part holds only the routines its name range names', () => {
  const split = splitSchemaMirror(readSchemaMirror());
  const bounds = PARTS.map((p) => p.fn ?? (p.section === 'FUNCTIONS' ? '' : null));
  split.forEach((p, i) => {
    if (bounds[i] === null) return;
    const lo = bounds[i], hi = bounds[i + 1] ?? null;
    for (const m of p.text.matchAll(/^CREATE OR REPLACE FUNCTION public\.("?)([A-Za-z0-9_]+)\1\(/gm)) {
      assert.ok(m[2] >= lo && (hi === null || m[2] < hi), `${m[2]} is in ${p.file}, outside [${lo}, ${hi ?? 'end'})`);
    }
  });
});

test('a split of an export with no routine in a range leaves that part empty, not misplaced', () => {
  const text = '-- banner\n-- ===== VIEWS =====\nv\n-- ===== FUNCTIONS =====\n'
    + 'CREATE OR REPLACE FUNCTION public.a()\n\n\nCREATE OR REPLACE FUNCTION public.fn_zz()\n'
    + '-- ===== TRIGGERS =====\nt\n';
  const parts = splitSchemaMirror(text);
  assert.equal(parts.map((p) => p.text).join(''), text);
  assert.equal(parts.find((p) => p.file.startsWith('04_')).text, '');
  assert.match(parts.find((p) => p.file.startsWith('10_')).text, /^CREATE OR REPLACE FUNCTION public\.fn_zz\(\)\n$/);
  assert.throws(() => splitSchemaMirror('-- no sections\n'), /no "-- ===== TRIGGERS =====" section/);
});
