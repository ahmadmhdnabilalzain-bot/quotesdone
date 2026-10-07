// The CEO's seat board must answer inside the 8 s statement timeout (it_engineer, 7 Oct 2026).
// fn_ceo_seat_board filtered agent_runs (~269k rows) by a seat-mapping function wrapped around the
// agent column, three times per seat: 31.0 s, so ceo_agent 'board' and 'seats' answered 500.
// The fix rolls agent_runs up per agent first. This fails if the row-by-row mapping comes back in the
// canonical file (the newest MANIFEST line, or the pending file before it is applied).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const FILE = 'scripts/sql/the_ceo_seat_board_counts_runs_per_agent_not_per_row.sql';

test('fn_ceo_seat_board maps agents to seats once per agent, not once per agent_runs row', () => {
  assert.ok(existsSync(FILE), FILE + ' is the canonical definition');
  const sql = readFileSync(FILE, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  assert.match(sql, /function public\.fn_ceo_seat_board\(/i);
  // the shape that took 31 s: a seat-mapping call on r.agent compared to the seat inside a WHERE
  assert.doesNotMatch(sql, /where\s+public\.fn_run_seat\(\s*r\.agent\s*\)\s*=/i);
  assert.match(sql, /from agent_runs r group by r\.agent/i);
});
