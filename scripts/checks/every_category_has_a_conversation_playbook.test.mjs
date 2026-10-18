// Every category (food & beverage is not one) has a senior expert's conversation playbook in the compiled brief,
// each playbook states no money figure, and the whole brief fits the cached context (< 100k tokens).
// sales_engineer, 12 Oct 2026, founder rulings 1195-1200.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { compileBrief } from '../kb/compile_brief.mjs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const dir = 'knowledge/brief/conversation/';
const files = readdirSync(new URL(dir, ROOT)).filter((f) => f.endsWith('.md'));

test('every category code is covered by exactly one playbook', () => {
  const codes = JSON.parse(read('src/content/categories.json')).items.map((i) => i.code);
  const owner = new Map();
  for (const f of files) {
    const line = read(dir + f).match(/^\*\*Categories:\*\*\s*(.+)$/m);
    assert.ok(line, `${f} has no **Categories:** line`);
    for (const c of line[1].split(',').map((s) => s.trim()).filter(Boolean)) {
      assert.ok(!owner.has(c), `${c} is claimed by ${owner.get(c)} and ${f}`);
      owner.set(c, f);
      assert.match(read(dir + f), new RegExp(`\\(${c}[),]|\\b${c}\\b.*\\)`), `${f} lists ${c} but has no section for it`);
    }
  }
  const missing = codes.filter((c) => !owner.has(c));
  assert.deepEqual(missing, [], 'categories with no playbook');
});

test('no playbook states a money figure (suppliers price the work)', () => {
  for (const f of files) assert.doesNotMatch(read(dir + f), /\b(AED|USD|dirhams?)\b|\d\s?%/i, f);
});

test('the compiled brief includes the style and every playbook, under 100k tokens', () => {
  const b = compileBrief();
  assert.ok(b.files.includes('conversation_style.md'));
  for (const f of files) assert.ok(b.files.includes('conversation/' + f), f);
  assert.ok(b.approxTokens < 100_000, `~${b.approxTokens} tokens`);
});
