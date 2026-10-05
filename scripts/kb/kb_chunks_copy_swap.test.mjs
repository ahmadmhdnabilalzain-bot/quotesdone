// The copy-and-swap's pure parts: the run window and the index rewrite (scripts/kb/kb_chunks_copy_swap.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import { inRunWindow, indexForCopy } from './kb_chunks_copy_swap.mjs';

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
