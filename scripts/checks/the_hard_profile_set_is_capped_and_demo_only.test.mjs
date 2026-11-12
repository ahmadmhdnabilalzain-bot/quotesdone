// The hard-profile set of supplier service profiling (scripts/e2e/services_hard_profiles/) refuses to spend without --paid and above
// its cap, writes nothing generated into the repository, and is ZZ DEMO only with no secret in it (sales_engineer, 12 Nov 2026;
// ruling 1647; docs/reports/2026-11-12-supplier-service-profiling.md). The pattern of the_prompt_diet_eval_is_capped_and_anonymised.
// Offline: no database, no model.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { CAP_USD, KEYS, PASS_BAR, plan } from '../e2e/services_hard_profiles/run.mjs';
import { PROFILES, SYNTHETIC } from '../e2e/services_hard_profiles/profiles_def.mjs';

const DIR = fileURLToPath(new URL('../e2e/services_hard_profiles/', import.meta.url));
const RUN = DIR + 'run.mjs', MAKE = DIR + 'make_profiles.mjs';
const REPO = fileURLToPath(new URL('../..', import.meta.url));

test('two full runs of the set are planned under the cap of one run, and the bar is the report\'s', () => {
  const p = plan({ runs: 2 });
  assert.equal(p.readings, 26);
  assert.ok(p.usd > 0 && p.usd <= CAP_USD, `USD ${p.usd}`);
  assert.ok(CAP_USD <= 0.60, 'never more than the workstream budget in one run');
  assert.ok(PASS_BAR.some((r) => /90% overall/.test(r) && /75% on every profile/.test(r)) && PASS_BAR.some((r) => /110 s/.test(r)));
});

test('the run refuses to spend without --paid, and refuses a cap above CAP_USD; read and run refuse to write answers into the repo', () => {
  const a = spawnSync(process.execPath, [RUN, 'run', '--dir', '/nonexistent'], { encoding: 'utf8' });
  assert.equal(a.status, 2); assert.match(a.stderr, /REFUSED: this spends money/);
  const b = spawnSync(process.execPath, [RUN, 'run', '--dir', '/nonexistent', '--paid', '--cap-usd', '5'], { encoding: 'utf8' });
  assert.equal(b.status, 2); assert.match(b.stderr, /cap-usd must be in/);
  const c = spawnSync(process.execPath, [RUN, 'run', '--dir', '/nonexistent', '--paid'], { encoding: 'utf8' });
  assert.equal(c.status, 2, 'no cap given is no permission to spend');
  const d = spawnSync(process.execPath, [RUN, 'read', '--dir', '/nonexistent', '--out', REPO + 'x.json'], { encoding: 'utf8' });
  assert.equal(d.status, 2); assert.match(d.stderr, /outside the repository/);
  const e = spawnSync(process.execPath, [MAKE, '--out', REPO + 'scripts/e2e/services_hard_profiles/pdfs'], { encoding: 'utf8' });
  assert.equal(e.status, 2); assert.match(e.stderr, /outside the repository/);
});

test('every company is ZZ DEMO, every licence number carries ZZ, every key file matches the definitions', () => {
  assert.equal(PROFILES.length, 12);
  for (const P of PROFILES) {
    assert.match(P.company, /^ZZ DEMO /, P.id); assert.match(P.licence.licence_no, /ZZ/, P.id);
    for (const f of ['must_trades', 'ok_trades', 'must_services', 'ok_services', 'partner', 'no_key', 'questions']) assert.ok(Array.isArray(P.key[f]), `${P.id}.${f}`);
  }
  assert.match(SYNTHETIC, /not a real company/);
  assert.deepEqual(KEYS.map((k) => k.id), ['H01', 'H02', 'H03', 'H04', 'H05', 'H06', 'H07', 'H08', 'H08D', 'H09', 'H10', 'H11', 'H12']);
  for (const k of KEYS) assert.deepEqual(k.key, PROFILES.find((P) => P.id === k.id.replace(/D$/, '')).key, `answer_keys.json ${k.id} is generated from profiles_def.mjs`);
});

test('no secret, no real address and no generated file in the folder', () => {
  const files = fs.readdirSync(DIR);
  assert.ok(files.every((f) => /\.(mjs|ts|json|md)$/.test(f)), files.join(', '));
  for (const f of files) {
    const s = fs.readFileSync(DIR + f, 'utf8');
    assert.doesNotMatch(s, /eyJ[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|sbp_[a-f0-9]{20,}/, f);
    for (const m of s.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g) || []) assert.match(m, /example\.invalid$/, `${f}: ${m}`);
  }
});
