// A FINDING HAS ONE LIVE CHASE.
//
// 7 Oct 2026, wiring audit (founder gate, ledger 1162): fn_it_engineer_finding_chase opened a new
// '<issue>@<epoch>@chase<day>' handoff every day and never closed the one before, so 81 open findings
// carried 358 pending handoffs (support_reply_sla:email had 10). The fix closes every older pending
// chase of the same occurrence when today's is opened (scripts/sql/a_finding_chase_supersedes_the_chase_before_it.sql).
//
// Reads the routine body from the newest definition: a pending (applied-at-merge) scripts/sql file
// if one defines it, otherwise the live mirror supabase/schema/full_schema/. Fails if the chase opens
// a handoff without completing the older chases in the same body.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const NAME = 'fn_it_engineer_finding_chase';
const DEF = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${NAME}\\s*\\([\\s\\S]*?\\bas\\s+(\\$\\w*\\$)([\\s\\S]*?)\\1`, 'gi');

function lastBody(sql) {
  let body = null;
  for (const m of sql.matchAll(DEF)) body = m[2];
  return body;
}

function chaseBody() {
  const dir = new URL('../sql/', import.meta.url);
  let body = null;
  for (const note of readdirSync(new URL('pending/', dir)).filter((n) => n.endsWith('.txt')).sort()) {
    const f = new URL(note.replace(/\.txt$/, '.sql'), dir);
    if (existsSync(f)) body = lastBody(readFileSync(f, 'utf8')) ?? body;
  }
  return body ?? lastBody(readSchemaMirror());
}

export function supersedesOlderChases(body) {
  const opens = body.indexOf("'it.finding'") >= 0 && /fn_seat_handoff\s*\(/.test(body);
  const closes = /fn_seat_handoff_complete\s*\(/.test(body) && /'chase'/.test(body) && /occurrence_started_at/.test(body);
  return opens && closes;
}

test('the finding chase closes the older chase of the same occurrence when it opens a new one', () => {
  const body = chaseBody();
  assert.ok(body, `${NAME} not found in a pending scripts/sql file nor in the schema mirror`);
  assert.ok(supersedesOlderChases(body),
    `${NAME} opens a daily chase handoff but never completes the older pending chase of the same finding occurrence ` +
    '— each day adds a duplicate handoff (7 Oct 2026: 358 pending on 81 findings)');
});

test('the shape check fails on the 29 Sep body that only opened chases', () => {
  const old = "v_id := public.fn_seat_handoff('it_engineer', o.agent, 'it.finding', 'x', 'k', jsonb_build_object('chase', true));";
  assert.equal(supersedesOlderChases(old), false);
});
