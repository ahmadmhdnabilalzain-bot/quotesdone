// EVERY PACK ROW HAS A FRESH MULTILINGUAL VECTOR WITHIN AN HOUR OF ITS LOAD (it_engineer, 19 Oct 2026).
//
// think() reads the ml space (fn_ml_read_space() = 'ml'), so a seat-pack or trade-pack row with no ml vector is
// invisible to every seat. Measured 19 Oct 2026, 90 minutes after the pack reload: marketing 0 of 268 eligible
// pack rows had one, sales 1,192 of 6,102 (0 of the 4,674 eligible trade-pack rows), it_engineer 79 of 427.
// scripts/sql/a_reloaded_pack_row_is_never_left_without_its_multilingual_vector.sql defines the reading,
// fn_pack_rows_without_fresh_ml_vector, and the IT duty that raises duty:pack_ml_vectors:<table> from it.
//
// This check reads production with the FILE's body of that routine, replayed and rolled back, so it measures
// what the file says before and after the file is applied. It fails when:
//   1. any eligible verified_pack row in the six seat tables (sales_knowledge holds the trade packs) has had no
//      ml vector whose text_hash matches its text for more than an hour since its load or update;
//   2. the reading is vacuous: deleting one fresh vector of an hour-old pack row, inside the rolled-back replay,
//      does not raise that table's overdue count by exactly one.
//
//   node --test scripts/checks/every_pack_row_has_a_fresh_multilingual_vector_within_an_hour.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/a_reloaded_pack_row_is_never_left_without_its_multilingual_vector.sql';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const skip = hasToken ? false : 'no Supabase management token in this environment';

// The routine's CREATE statement, exactly as the file has it.
const text = readFileSync(join(REPO, FILE), 'utf8');
const start = text.indexOf('create or replace function public.fn_pack_rows_without_fresh_ml_vector');
const end = text.indexOf('$fn$;', start);
const routine = text.slice(start, end + 5);
const READ = `select * from public.fn_pack_rows_without_fresh_ml_vector(interval '1 hour')`;

test('the file defines the reading', () => {
  assert.ok(start >= 0 && end > start, `${FILE} no longer defines fn_pack_rows_without_fresh_ml_vector`);
});

test('production: no pack row has gone an hour without a fresh multilingual vector', { skip, timeout: 300000 }, async () => {
  const rows = await replaySql(`${routine}\n${READ};`, { label: FILE, rows: true });
  assert.equal(rows.length, 6, `expected the six seat tables, read ${JSON.stringify(rows)}`);
  for (const r of rows) console.log(`  ${r.src.padEnd(22)} pack rows ${r.pack_rows}, without a fresh vector ${r.without_fresh}, overdue ${r.overdue}`);
  const late = rows.filter((r) => r.overdue > 0);
  assert.equal(late.length, 0, 'pack rows without a fresh ml vector for over an hour: '
    + late.map((r) => `${r.src} ${r.overdue} (oldest due ${r.oldest_due})`).join(', ')
    + '. Remedy: gh workflow run ml-embed-backfill.yml');
});

test('production, rolled back: removing one fresh vector of an hour-old pack row is counted', { skip, timeout: 300000 }, async () => {
  const probe = `${routine}
create temp table pack_ml_before on commit drop as ${READ};
create temp table pack_ml_victim on commit drop as
  with last_load as (select max(finished_at) t from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'verified_pack_load'),
  cand as (
              select 'ceo_knowledge'::text src, record_id, (select t from last_load) due from public.ceo_knowledge where tags @> array['verified_pack']
    union all select 'support_knowledge', record_id, (select t from last_load) from public.support_knowledge where tags @> array['verified_pack']
    union all select 'accountant_knowledge', record_id, updated_at from public.accountant_knowledge where tags @> array['verified_pack']
    union all select 'it_engineer_knowledge', record_id, updated_at from public.it_engineer_knowledge where tags @> array['verified_pack']
    union all select 'marketing_knowledge', record_id, updated_at from public.marketing_knowledge where tags @> array['verified_pack']
    union all select 'sales_knowledge', record_id, updated_at from public.sales_knowledge where tags @> array['verified_pack'])
  select c.src, c.record_id row_id from cand c
    join public.v_knowledge_ml_source s on s.src = c.src and s.row_id = c.record_id
    join public.knowledge_vector_ml v on v.src = c.src and v.row_id = c.record_id
         and v.text_hash = md5(coalesce(s.title, '') || E'\\n' || coalesce(s.body, ''))
   where coalesce(c.due, '-infinity') < now() - interval '2 hours'
   limit 1;
delete from public.knowledge_vector_ml v using pack_ml_victim x where v.src = x.src and v.row_id = x.row_id;
select x.src, (select count(*) from pack_ml_victim)::int victims, b.overdue before_overdue, a.overdue after_overdue
  from pack_ml_victim x join pack_ml_before b on b.src = x.src
  join (${READ}) a on a.src = x.src`;
  const rows = await replaySql(probe, { label: `${FILE} (mutation)`, rows: true });
  assert.equal(rows.length, 1, 'no fresh, hour-old pack row to remove; the mutation proved nothing');
  console.log('  mutation: ' + JSON.stringify(rows[0]));
  assert.equal(rows[0].after_overdue, rows[0].before_overdue + 1, `the reading did not count the removed vector: ${JSON.stringify(rows[0])}`);
});
