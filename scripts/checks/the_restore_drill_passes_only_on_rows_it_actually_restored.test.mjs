// THE RESTORE DRILL PASSES ONLY ON ROWS IT ACTUALLY RESTORED.
//
// scripts/sql/the_restore_drill_passes_only_on_rows_it_actually_restored.sql. Runs the file and the drill's two
// routines inside ONE transaction that ends in raise exception 'CHK<<...>>', so nothing is kept (not the pick's
// agent_runs row, not the drill result, not a finding). This fails when:
//   1. an empty export page is recorded as a pass (the 15 Sep 2026 run #70: restored 0, ok true);
//   2. the pick chooses a table whose export page has no rows while another drill table's page has rows;
//   3. a real page (the picked one, restored from the rows the manifest says exist) does not pass.
//
//   node --test scripts/checks/the_restore_drill_passes_only_on_rows_it_actually_restored.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_restore_drill_passes_only_on_rows_it_actually_restored.sql';
const ddl = readFileSync(join(REPO, FILE), 'utf8').split('\n-- PROBE')[0];

// A production probe: CI's checks job has no management token, so it skips there (the credential job runs it).
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('an empty page fails, the pick prefers a page with rows, and live rows restore', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare pick jsonb; tab text; r jsonb; o jsonb; live jsonb; begin
      pick := public.fn_it_restore_table_pick();
      tab := pick->'table'->>'table';
      o := jsonb_build_object('picked', tab, 'picked_rows',
             (select (r.manifest->'tables'->tab->>'rows')::bigint from public.table_export_run r
               where r.status = 'done' and r.manifest is not null order by r.stamp desc limit 1));
      r := public.fn_it_restore_table_record(jsonb_build_object('newest_export_day', pick->>'newest_export_day',
             'table', jsonb_build_object('table', 'quotes', 'path', 'x/quotes/page_0000.json', 'rows_in_file', 0, 'rows', '[]'::jsonb)));
      o := o || jsonb_build_object('empty_ok', (select ok from public.it_restore_drill_result order by id desc limit 1),
                                   'empty_error', r->'drill'->>'error');
      -- a real page: 5 live rows of the picked table, exactly as the export would hand them over
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from (select * from public.%I limit 5) x', tab) into live;
      r := public.fn_it_restore_table_record(jsonb_build_object('newest_export_day', pick->>'newest_export_day',
             'table', jsonb_build_object('table', tab, 'path', 'x', 'rows_in_file', jsonb_array_length(live), 'rows', live)));
      o := o || jsonb_build_object('real_restored', r->'drill'->'restored', 'real_identical', r->'drill'->'identical_to_live',
                                   'real_error', r->'drill'->>'error');
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await sql('begin;\n' + ddl + '\n' + body); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(r.empty_ok, false, 'an empty page is not a pass');
  assert.match(r.empty_error ?? '', /0 rows/);
  assert.ok(Number(r.picked_rows) > 0, `the pick chose ${r.picked} whose export page has ${r.picked_rows} rows`);
  assert.ok(Number(r.real_restored) > 0 && Number(r.real_identical) > 0, JSON.stringify(r));
  assert.equal(r.real_error, null);
});
