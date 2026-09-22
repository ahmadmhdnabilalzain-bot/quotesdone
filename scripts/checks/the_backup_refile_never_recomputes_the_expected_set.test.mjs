// NO ROUTINE RECOMPUTES THE EXPECTED-BACKUP SET INSIDE A LOOP.
//
// 22 Sep 2026: the IT engineer's daily Dropbox check (fn_it_backup_check, called through PostgREST,
// cancelled at 8 s) took 24.6-29.0 s and died on "canceling statement due to statement timeout" from
// 20 Sep. The refile it hands over, fn_sales_engineer_refiles_backup, looked each never-queued file up
// in fn_it_backup_expected_status() -- a set function that enumerates all ~10,600 expected items
// (2.7 s, EXPLAIN ANALYZE) -- once PER FILE inside its FOR loop. Seven files, 19 s.
// Fixed in scripts/sql/the_backup_refile_looks_up_its_own_file_instead_of_recomputing_every_expected_file.sql.
//
// Reads supabase/schema/full_schema.sql (the live mirror). Scanning the whole set ONCE, in a FOR
// header (`for x in select ... from fn_it_backup_expected_status() ... loop`), is fine and is what the
// check itself does; a call between `loop` and its `end loop` is the shape that multiplied.
// The timing itself is proved by scripts/sql/the_backup_check_answers_inside_its_budget_probe.sql.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SCHEMA = readFileSync(new URL('../../supabase/schema/full_schema.sql', import.meta.url), 'utf8');

export function expectedSetCallsInsideLoops(fnBody) {
  const code = fnBody.replace(/--[^\n]*/g, '').toLowerCase();
  let depth = 0; let n = 0;
  for (const [tok] of code.matchAll(/\bend\s+loop\b|\bloop\b|\bfn_it_backup_expected(?:_status)?\s*\(/g)) {
    if (/^end\s+loop$/.test(tok)) depth = Math.max(0, depth - 1);
    else if (tok === 'loop') depth++;
    else if (depth > 0) n++;
  }
  return n;
}

test('the shape is recognised: a lookup in the expected set inside a FOR loop, not in its header', () => {
  const bad = `begin for s in select e from jsonb_array_elements(f) e loop
      select x.id into v from public.fn_it_backup_expected_status() x where x.item_key = s.e->>'k';
    end loop; end`;
  assert.equal(expectedSetCallsInsideLoops(bad), 1);
  const once = `begin for x in select * from public.fn_it_backup_expected_status() s where s.id is null loop
      f := f || x; end loop; end`;
  assert.equal(expectedSetCallsInsideLoops(once), 0);
});

test('no plpgsql routine in the live schema recomputes the expected-backup set once per loop iteration', () => {
  const found = [];
  const chunks = SCHEMA.split('CREATE OR REPLACE FUNCTION public.').slice(1);
  assert.ok(chunks.length > 500, `read only ${chunks.length} routines — the split is wrong, not the schema`);
  for (const c of chunks) {
    const head = c.slice(0, c.indexOf('$function$'));
    if (!/LANGUAGE plpgsql/.test(head)) continue;
    const n = expectedSetCallsInsideLoops(c.slice(head.length, c.indexOf('$function$', head.length + 10)));
    if (n) found.push(`${c.slice(0, c.indexOf('('))}: ${n} call(s) inside a loop`);
  }
  assert.deepEqual(found, [], 'each iteration re-enumerates ~10,600 expected items (2.7 s); look the one file up in doc_backups');
});
