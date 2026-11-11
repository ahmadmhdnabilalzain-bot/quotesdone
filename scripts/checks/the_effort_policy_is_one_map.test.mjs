// Reasoning effort by consequence (founder ruling 1630, 11 Nov 2026) lives in ONE map:
// supabase/functions/_shared/effort_policy.ts. This fails if
//   - the SQL that mirrors it onto model_policy differs from it by one class or one value;
//   - any edge function asks 'low' by literal again (six did before 11 Nov, none behind a side-by-side);
//   - the gateway stops applying the map to a call that names no effort, or aiReply stops deepening a hard turn.
// Offline: no database, no model. Assigned: it_engineer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const FN = join(ROOT, 'supabase/functions');
const policy = await import(join(FN, '_shared/effort_policy.ts'));

test('the model_policy SQL states exactly the code map', () => {
  const sql = readFileSync(join(ROOT, 'scripts/sql/model_policy_states_the_effort_of_every_task_class.sql'), 'utf8');
  const fromSql = Object.fromEntries([...sql.matchAll(/^\s+\('([a-z0-9_]+)', '(low|medium|high)'\)/gm)].map((m) => [m[1], m[2]]));
  const fromCode = { ...policy.EFFORT_BY_CLASS };
  delete fromCode.case_summary;   // its policy row is created, with its effort, by the case-model file
  assert.deepEqual(fromSql, fromCode);
  assert.equal(Object.keys(fromSql).length, 100, 'model_policy held 100 classes on 11 Nov 2026');
  const caseSql = readFileSync(join(ROOT, 'scripts/sql/every_support_case_keeps_a_summary_and_the_reply_reads_it.sql'), 'utf8');
  assert.match(caseSql, new RegExp(`values \\('case_summary'[\\s\\S]*?true, 0, '${policy.EFFORT_BY_CLASS.case_summary}'\\)`), 'the case_summary row carries the map\'s effort');
});

const tsFiles = (dir) => readdirSync(dir).flatMap((f) => {
  const p = join(dir, f);
  return statSync(p).isDirectory() ? tsFiles(p) : (/\.ts$/.test(f) && !/\.test\.ts$/.test(f) ? [p] : []);
});

test('no edge function asks for low effort by literal: low comes only from the policy, and only where proven', () => {
  const offenders = tsFiles(FN).filter((p) => !p.endsWith('effort_policy.ts'))
    .filter((p) => /effort\s*:\s*'low'|effort\s*=\s*'low'|EFFORT\s*=\s*'low'/.test(readFileSync(p, 'utf8')));
  assert.deepEqual(offenders.map((p) => p.slice(FN.length + 1)), []);
  const proven = Object.entries(policy.SURFACES).filter(([, s]) => s.provenLow).map(([k]) => k);
  assert.deepEqual(proven, [], 'flip provenLow only with a passed scripts/eval/effort_low_vs_high.mjs verdict');
});

test('the gateway applies the class effort, and every conversation surface deepens a hard turn', () => {
  const gw = readFileSync(join(FN, 'ai_gateway/handle.ts'), 'utf8');
  assert.match(gw, /effort: effortFor\(route\.task_class \?\? body\.task_class \?\? null, body\.effort \?\? null\)/);
  assert.match(readFileSync(join(FN, '_shared/ai_reply.ts'), 'utf8'), /r\.effort \?\? conversationEffort\(r\.message/);
  for (const f of ['sales_engineer/actions/portal.ts', 'site_assistant/index.ts']) {
    assert.match(readFileSync(join(FN, f), 'utf8'), /effort: conversationEffort\(message\)/, f);
  }
  assert.match(readFileSync(join(FN, '_shared/brief_answer.ts'), 'utf8'), /effort: 'high', input: correction\(/, 'a failed draft is re-thought at high');
});

test('the low-vs-high side-by-side stays under its USD 0.50 cap and anonymises what it replays', async () => {
  const ev = await import(join(ROOT, 'scripts/eval/effort_low_vs_high.mjs'));
  const p = ev.plan();
  assert.ok(p.total > 0 && p.total < ev.CAP_USD, `USD ${p.total}`);
  assert.deepEqual(p.parts.map((x) => x.surface).sort(), Object.keys(policy.SURFACES).filter((s) => s !== 'marketing_social.needs_a_person' && s !== 'support.case_match' && s !== 'wa_inbound.problem_state').sort());
  assert.equal(ev.anonymise('mail me at a.b@x.ae or +971 50 123 4567, my name is Sara Ali'), 'mail me at person@example.invalid or +971500000000, my name is ZZ DEMO Person');
});
