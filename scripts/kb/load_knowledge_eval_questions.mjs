// Loads every verified pack's eval questions into public.seat_knowledge_eval_question, embedded by the same free
// gte-small path think() uses, for the daily no-model knowledge exam (fn_it_engineer_knowledge_recall_exam,
// scripts/sql/every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql). Seat: it_engineer, 24 Sep 2026.
// Same questions, seats and languages as scripts/eval/knowledge_pack_eval.mjs. Re-run after a pack changes.
//
//   node scripts/kb/load_knowledge_eval_questions.mjs [--dry]
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPacks, makeEmbedder, seatsOf, vecLit, lit } from './verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const packs = readPacks(join(REPO, 'knowledge'));
const bad = packs.filter((p) => p.errors.length);
if (bad.length) { console.error('refused packs: ' + bad.map((p) => p.rel).join(', ')); process.exit(2); }
const qs = packs.flatMap((p) => (p.pack.eval ?? []).flatMap((q) => ['en', 'ar'].flatMap((lang) =>
  seatsOf(p).map((seat) => ({ pack: p.key, seat, lang, text: lang === 'en' ? q.q_en : q.q_ar, expected: q.expected_entry_ids })))))
  .filter((q) => q.text && q.expected?.length);
console.log(`${packs.length} packs, ${qs.length} (seat, question, language) rows`);
if (process.argv.includes('--dry')) process.exit(0);

const { sql, PROJECT_REF } = await import('../lib/db.mjs');
const embedder = await makeEmbedder(sql, PROJECT_REF);
const texts = [...new Set(qs.map((q) => q.text))];
const vecs = new Map(texts.map((t, i) => [t, i]));
const got = await embedder.many(texts);
for (let i = 0; i < qs.length; i += 100) {
  const part = qs.slice(i, i + 100);
  await sql(`insert into public.seat_knowledge_eval_question (seat, pack, lang, question, expected, embedding) values\n` +
    part.map((q) => `(${lit(q.seat)}, ${lit(q.pack)}, ${lit(q.lang)}, ${lit(q.text)}, ${lit(q.expected)}, ${vecLit(got[vecs.get(q.text)])})`).join(',\n') +
    `\non conflict (seat, pack, lang, question) do update set expected = excluded.expected, embedding = excluded.embedding, loaded_at = now();`);
}
console.log('loaded');
