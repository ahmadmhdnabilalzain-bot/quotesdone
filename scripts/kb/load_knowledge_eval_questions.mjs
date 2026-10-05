// Loads every verified pack's eval questions into public.seat_knowledge_eval_question, embedded by the same free
// gte-small path think() uses, for the daily no-model knowledge exam (fn_it_engineer_knowledge_recall_exam,
// scripts/sql/every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql). Seat: it_engineer, 24 Sep 2026.
// Same questions, seats and languages as scripts/eval/knowledge_pack_eval.mjs. Re-run after a pack changes.
//
//   node scripts/kb/load_knowledge_eval_questions.mjs [--dry]
//   node scripts/kb/load_knowledge_eval_questions.mjs --ml    only fill embedding_ml where it is missing
// Every load ends by filling embedding_ml (5 Oct 2026, the bilingual exam): each question's multilingual vector from
// embed_ml 'query', the production model, so the exam's vector is the one think() makes for the same words.
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPacks, makeEmbedder, seatsOf, vecLit, lit } from './verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const packs = readPacks(join(REPO, 'knowledge'));
const bad = packs.filter((p) => p.errors.length);
if (bad.length) { console.error('refused packs: ' + bad.map((p) => p.rel).join(', ')); process.exit(2); }
const qs = packs.flatMap((p) => (p.pack.eval ?? []).flatMap((q) => ['en', 'ar'].flatMap((lang) =>
  seatsOf(p).map((seat) => ({ pack: p.key, seat, lang, text: lang === 'en' ? q.q_en : q.q_ar, expected: q.expected_entry_ids })))))
  .filter((q) => q.text && q.expected?.length)
  // a pack can repeat a question or list a seat twice; the upsert refuses the same key twice in one batch
  .filter((q, i, all) => all.findIndex((o) => o.seat === q.seat && o.pack === q.pack && o.lang === q.lang && o.text === q.text) === i);
console.log(`${packs.length} packs, ${qs.length} (seat, question, language) rows`);
if (process.argv.includes('--dry')) process.exit(0);

const { sql, PROJECT_REF } = await import('../lib/db.mjs');

async function fillMl() {
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  if (!secret) throw new Error('no cred_fn_ai in app_secrets');
  const rows = await sql('select id, question from public.seat_knowledge_eval_question where embedding_ml is null order by id');
  const byText = new Map();
  for (const r of rows) byText.set(r.question, [...(byText.get(r.question) ?? []), Number(r.id)]);
  const texts = [...byText.keys()];
  const one = async (text) => {
    for (let a = 0; ; a++) {
      const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/embed_ml`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, fn: 'embed_verified_packs', action: 'query', text }),
      }).catch(() => null);
      const j = res?.ok ? await res.json() : null;
      if (typeof j?.embedding === 'string') return j.embedding;
      if (a >= 4) throw new Error(`embed_ml refused (HTTP ${res?.status ?? 0})`);
      await new Promise((r) => setTimeout(r, 1500 * 2 ** a));
    }
  };
  let i = 0, done = 0;
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (i < texts.length) {
      const t = texts[i++];
      const v = await one(t);
      await sql(`update public.seat_knowledge_eval_question set embedding_ml = ${lit(v)}::vector where id = any(array[${byText.get(t).join(',')}]::bigint[])`);
      if (++done % 100 === 0) console.log(`ml ${done}/${texts.length}`);
    }
  }));
  console.log(`ml vectors: ${done} texts, ${rows.length} questions`);
}
if (process.argv.includes('--ml')) { await fillMl(); process.exit(0); }

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
// a changed question keeps its old multilingual vector unless cleared; the upsert above kept it, so clear and refill
await sql(`update public.seat_knowledge_eval_question set embedding_ml = null where loaded_at > now() - interval '1 hour'`);
await fillMl();
