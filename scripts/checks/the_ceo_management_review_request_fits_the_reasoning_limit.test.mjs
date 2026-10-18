// THE CEO'S MANAGEMENT REVIEW REQUEST FITS THE REASONING LIMIT (5 Oct 2026, ceo).
//
// reasoning_held_question.request is checked at <= 60,000 characters. On 1 Oct 2026 fn_ceo_management_review
// embedded every seat_duty.last_result whole (56,219 characters over 84 duties) and the September review was never
// written. WHAT FAILS IF THE CAUSE RETURNS:
//   * static: the canonical body (the pending file, else the last MANIFEST file defining the routine) puts
//     d.last_result into the facts uncapped, or loses the 45,000-character second pass;
//   * production, rolled back: the routine runs on today's facts and its request is not an object of <= 60,000
//     characters, or it no longer carries every duty.
//
//   node --test scripts/checks/the_ceo_management_review_request_fits_the_reasoning_limit.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FIX = 'scripts/sql/the_ceo_management_review_request_fits_the_reasoning_limit.sql';
const PROBE = FIX.replace(/\.sql$/, '_probe.sql');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const DEF = /create or replace function public\.fn_ceo_management_review\(\)[\s\S]*?end \$fn\$;/;

function canonicalBody() {
  const listed = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).filter((l) => l.startsWith('scripts/sql/'));
  const files = pending(FIX) ? [...listed, FIX] : listed;
  for (const f of files.reverse()) {
    if (!existsSync(join(REPO, f))) continue;
    const m = read(f).match(DEF);
    if (m) return { f, body: m[0].split('\n').map((l) => l.replace(/--.*$/, '')).join('\n') };
  }
  assert.fail('no file defines fn_ceo_management_review');
}

test('static: the canonical review caps each duty result and has a second pass under 45,000', () => {
  const { f, body } = canonicalBody();
  assert.ok(!/'last_result',\s*d\.last_result\s*\)/.test(body), `${f} puts last_result into the facts whole`);
  assert.match(body, /left\(d\.last_result::text, v_cap\)/, `${f} does not cut last_result to v_cap`);
  assert.match(body, /foreach v_cap in array array\[\d+, 0\]/, `${f} has no pass that drops the results`);
  assert.match(body, /exit when length\(v_facts::text\) <= 45000/, `${f} does not bound the facts at 45,000`);
  assert.ok(pending(FIX) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FIX), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, rolled back: the review files a request that fits', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const text = (pending(FIX) ? read(FIX) + '\n' : '') + read(PROBE);
  try { await replaySql(text, { retry: false, label: 'management review request' }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    assert.match(m[1], /^PROBE OK/, m[1]);
    return;
  }
  assert.fail('the probe committed instead of rolling back');
});
