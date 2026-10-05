// The copy-and-swap's pure parts: the run window and the index rewrite (scripts/kb/kb_chunks_copy_swap.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import { inRunWindow, indexForCopy, fitsRunWindow, trimRefusal, rollbackRefusal } from './kb_chunks_copy_swap.mjs';

const dubai = (hhmm) => new Date(`2026-10-06T${hhmm}:00+04:00`);

test('runs only 02:00-05:00 Dubai, never 02:50-03:10', () => {
  for (const t of ['02:00', '02:49', '03:10', '04:59']) assert.equal(inRunWindow(dubai(t)), true, t);
  for (const t of ['01:59', '02:50', '03:00', '03:09', '05:00', '23:30', '12:00']) assert.equal(inRunWindow(dubai(t)), false, t);
});

test('every live index shape is rebuilt on the copy under a suffixed name', () => {
  assert.equal(indexForCopy('CREATE INDEX kb_chunks_emb_hnsw ON public.kb_chunks USING hnsw (embedding_gte vector_cosine_ops)'),
    'CREATE INDEX IF NOT EXISTS kb_chunks_emb_hnsw_cs ON public.kb_chunks_new USING hnsw (embedding_gte vector_cosine_ops)');
  assert.equal(indexForCopy("CREATE UNIQUE INDEX kb_chunks_qdkb_source_uidx ON public.kb_chunks USING btree (source_id) WHERE (source_kind = 'qd_kb_pack'::text)"),
    "CREATE UNIQUE INDEX IF NOT EXISTS kb_chunks_qdkb_source_uidx_cs ON public.kb_chunks_new USING btree (source_id) WHERE (source_kind = 'qd_kb_pack'::text)");
  // an index of another table, or a shape it does not know, stops the run instead of building the wrong thing
  assert.throws(() => indexForCopy('CREATE INDEX x ON public.kb_chunks_old USING btree (id)'));
  assert.throws(() => indexForCopy('CREATE INDEX x ON public.other USING btree (id)'));
});

test('every statement must finish, at its full budget, before 02:50 or 05:00', () => {
  assert.equal(fitsRunWindow(100000, dubai('02:10')), true);
  assert.equal(fitsRunWindow(125000, dubai('02:48')), false, 'would cross 02:50');
  assert.equal(fitsRunWindow(60000, dubai('02:48')), true, 'ends 02:49');
  assert.equal(fitsRunWindow(125000, dubai('04:58')), false, 'would cross 05:00');
  assert.equal(fitsRunWindow(1000, dubai('03:00')), false, 'starts inside the export gap');
  assert.equal(fitsRunWindow(1000, dubai('05:00')), false);
  // a budget long enough to jump the 02:50-03:10 gap is still refused
  assert.equal(fitsRunWindow(25 * 60000, dubai('02:46')), false);
});

test('the trim guard takes only tonight\'s row (after 23:00 Dubai), an empty plan and no batch in 10 minutes', () => {
  const now = dubai('02:30');
  const ok = { doneAt: '2026-10-05T23:40:00+04:00', planRows: 0, plannedLeft: 0, lastBatchAt: '2026-10-06T01:00:00+04:00' };
  assert.equal(trimRefusal(ok, now), null);
  assert.match(trimRefusal({ ...ok, doneAt: '2026-10-05T22:59:00+04:00' }, now), /since 23:00/);
  assert.match(trimRefusal({ ...ok, doneAt: '2026-09-30T23:40:00+04:00' }, now), /since 23:00/);
  assert.match(trimRefusal({ ...ok, doneAt: null }, now), /since 23:00/);
  assert.match(trimRefusal({ ...ok, planRows: 3 }, now), /kb_trim_plan/);
  assert.match(trimRefusal({ ...ok, plannedLeft: 1 }, now), /planned rows/);
  assert.match(trimRefusal({ ...ok, lastBatchAt: '2026-10-06T02:25:00+04:00' }, now), /10 minutes/);
  // at 23:30 the night began at 23:00 the same evening
  assert.equal(trimRefusal({ ...ok, doneAt: '2026-10-05T23:10:00+04:00', lastBatchAt: null }, new Date('2026-10-05T23:30:00+04:00')), null);
});

test('rollback refuses without kb_chunks_old, and refuses to run twice', () => {
  assert.match(rollbackRefusal({ oldExists: false, newExists: false }), /kb_chunks_old does not exist/);
  assert.match(rollbackRefusal({ oldExists: true, newExists: true }), /already rolled back/);
  assert.equal(rollbackRefusal({ oldExists: true, newExists: false }), null);
});
