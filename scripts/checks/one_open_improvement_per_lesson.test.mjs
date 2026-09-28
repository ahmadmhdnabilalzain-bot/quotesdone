// The CEO's improvement sweep keys a lesson on the LESSON, never on the case. Seat: ceo. 28 Sep 2026.
//
// On 24 Sep the lesson branch keyed each improvement on the case-memory row id, so one recurring IT
// closure lesson became 51 improvements and 51 handoffs (367 to it_engineer in one sweep). This reads
// the newest definition of the sweep (MANIFEST order, then files still pending apply) and fails if the
// lesson key goes back to a per-case id, or if the lesson close waits on case_kind alone again.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const DEF = /create\s+or\s+replace\s+function\s+public\.fn_ceo_improvement_sweep\s*\(/i;
const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
const pending = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt'))
  .map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
const newest = [...manifest, ...pending].filter((f) => existsSync(f) && DEF.test(readFileSync(f, 'utf8'))).pop();

test('the lesson improvement is keyed on seat and lesson, and closes on re-verification', () => {
  assert.ok(newest, 'no file defines fn_ceo_improvement_sweep');
  const body = readFileSync(newest, 'utf8').split(DEF)[1].split('$function$;')[0];
  const openCall = body.match(/fn_ceo_improvement_open\(\s*'lesson'\s*,([^,]+),/);
  assert.ok(openCall, `${newest}: the sweep opens no lesson improvement`);
  assert.match(openCall[1], /md5\(/, `${newest}: the lesson key must be a hash of the lesson`);
  assert.doesNotMatch(openCall[1], /seat_case_memory:|\.id\b/, `${newest}: the lesson key names a case, one improvement per case`);
  assert.match(body, /group by 1, 2, 3/, `${newest}: cases with the same lesson must be grouped before opening`);
  assert.match(body, /replied_at/, `${newest}: the lesson close must re-verify an ANSWERED handoff`);
});
