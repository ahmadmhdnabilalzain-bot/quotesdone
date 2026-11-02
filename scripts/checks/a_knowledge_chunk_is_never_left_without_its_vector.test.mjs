// A KNOWLEDGE CHUNK IS NEVER LEFT WITHOUT ITS VECTOR (customer_support, 3 Nov 2026).
//
//   node --test scripts/checks/a_knowledge_chunk_is_never_left_without_its_vector.test.mjs
//
// Measured 2 Nov 2026: the kb_chunks embedder ran once a day (pg_cron 'kb_embed_daily', 02:20) and harvested the pg_net
// answers of the previous day's dispatch, but pg_net keeps answers 6 hours, so a row sent by that job could never be
// filled. scripts/sql/a_knowledge_chunk_is_never_left_without_its_vector.sql runs the same tick every 10 minutes; its probe
// proves the behaviour on production in a rolled-back transaction. This reads only the repository: it fails if the
// cadence goes back to daily, or the stale-text guard, the retry bound, the in-flight guard or the beat rule is lost.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const F = 'scripts/sql/a_knowledge_chunk_is_never_left_without_its_vector.sql';
const code = read(F).split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n');
const TEXT = "md5\\(left\\(coalesce\\(k\\.title, ''\\) \\|\\| E'\\\\n' \\|\\| coalesce\\(k\\.content, ''\\), 1200\\)\\)";

test('the tick runs every 10 minutes in place of the daily job, registered and owned by customer_support, and the file is applied', () => {
  assert.match(code, /select cron\.unschedule\(jobid\) from cron\.job where jobname = 'kb_embed_daily';/);
  assert.match(code, /cron\.schedule\('kb_embed', '\*\/10 \* \* \* \*',\s+\$CRON\$set statement_timeout = '120s'; select public\.fn_kb_embed_scheduled_run\(\);\$CRON\$\)/);
  assert.match(code, /insert into public\.cron_registry[\s\S]*\('kb_embed', /);
  assert.match(code, /\('cron_job', 'kb_embed', 'customer_support'/);
  assert.ok(read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(F), 'not in MANIFEST.txt');
});

test('a vector is written only to a row still NULL whose text is what was sent, and only a 384-element one the gateway returned', () => {
  assert.match(code, new RegExp(`k\\.id = a\\.chunk_id and k\\.embedding_gte is null\\s+and ${TEXT} = a\\.text_md5`));
  assert.match(code, /pg_input_is_valid\(r\.content, 'jsonb'\)/);
  assert.match(code, /jsonb_array_length\(\(r\.content::jsonb ->> 'embedding'\)::jsonb\) = 384/);
  assert.match(code, /insert into public\.kb_embed_inflight \(request_id, chunk_id, text_md5\)/);
});

test('a row is never sent twice at once, and stops after 5 failed attempts on the same text', () => {
  assert.match(code, /v_tries\s+constant int := 5;/);
  assert.match(code, /not exists \(select 1 from public\.kb_embed_inflight f where f\.chunk_id = k\.id and f\.failed_at is null\)/);
  assert.match(code, new RegExp(`f\\.failed_at is not null\\s+and f\\.text_md5 = ${TEXT}\\) < v_tries`));
  assert.match(code, /set failed_at = now\(\)\s+where failed_at is null and queued_at < now\(\) - interval '1 hour'/);
});

test('a refused dispatch never beats; an idle tick beats at most once in 20 hours', () => {
  assert.match(code, /if coalesce\(\(v_t->'dispatch'->>'ok'\)::boolean, false\)\s+and \(v_work or [\s\S]*< now\(\) - interval '20 hours'\) then\s+perform public\.fn_it_duty_ran\('kb_embed'/);
});

test('the probe proves the fill, the stale-text refusal, the retry and its bound, and that no NULL row is left unsent', () => {
  const probe = read(F.replace(/\.sql$/, '_probe.sql'));
  for (const s of ["' 2:not_filled", "' 3:stale_vector_written", "' 3:not_resent", "' 4:failure_not_retried",
    "' 4:spent_row_not_held", "' 5:null_row_unsent", "raise exception 'CHK<<%>>'"]) {
    assert.ok(probe.includes(s), 'probe lacks ' + s);
  }
});
