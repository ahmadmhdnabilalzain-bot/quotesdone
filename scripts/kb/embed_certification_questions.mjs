// Precompute the semantic examiner's vectors ONCE, with the free in-region gte-small.
//
// The founder asked whether the employees are answering by keyword search. They were:
// fn_certification_exam_sit scores options with ts_rank_cd. fn_certification_exam_sit_semantic scores
// them by cosine instead, and cosine needs vectors for 2,080 question stems and their 8,320 options —
// 10,400 texts. Embedding those inside the sitter would mean 10,400 HTTPS round trips per sitting, so
// they are computed once here and stored in public.certification_exam_question_vector.
//
// The same pass fills public.agent_knowledge.embedding_gte for active employees: the employee's own
// notes are one of the four evidence sources the lexical sitter reaches for, and they had no vector,
// so a cosine examiner would have been blind to exactly the knowledge that is most personal to the
// employee being examined.
//
// NO PAID PROVIDER, EVER. Every vector comes from kb_embed's batch mode — the same free in-region
// gte-small, the same 1,200-character truncation and the same 384 dimensions that embedded
// ops_knowledge and kb_chunks. A vector from any other model is not comparable with those and would
// silently produce meaningless cosines.
//
//   node scripts/kb/embed_certification_questions.mjs              # resume until done
//   node scripts/kb/embed_certification_questions.mjs --limit 2000 # embed at most N texts, then stop
//   node scripts/kb/embed_certification_questions.mjs --status     # counts only, no work
//
// Resumable: it only ever asks for the rows that have no vector yet, so an interrupted run costs
// nothing and a re-run is a no-op once the table is full.
import { sql } from '../phase_c/lib/db.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const BATCH = 16;      // measured 7 Sep 2026 on this project's edge worker: 16 -> 200, 32 -> 546.
const PARALLEL = 4;    // four warm workers; higher gave no throughput and more 546s.
const args = process.argv.slice(2);
const cap = args.includes('--limit') ? Number(args[args.indexOf('--limit') + 1]) : Infinity;

const secret = (await sql(`select value from public.app_secrets where key = 'cred_cron_knowledge'`))[0]?.value;
if (!secret) { console.error('no cred_cron_knowledge in app_secrets'); process.exit(2); }

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

async function embedBatch(texts) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const r = await fetch(`https://${REF}.supabase.co/functions/v1/kb_embed`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, texts }) });
    if (r.ok) {
      const j = await r.json();
      if (Array.isArray(j.embeddings) && j.embeddings.length === texts.length
          && j.embeddings.every((e) => Array.isArray(e) && e.length === 384)) return j.embeddings;
      // A short return means the worker hit its wall-clock budget mid-batch; retry the whole batch.
    }
    await new Promise((res) => setTimeout(res, 400 * (attempt + 1)));
  }
  // Measured 7 Sep 2026: 16 short exam options fit the worker, 16 agent_knowledge notes (median ~1,370
  // characters each) do not — the gte-small session's allocation grows with the text it is given, so
  // the ceiling is in characters, not rows, and a fixed row cap cannot express it. Halving on failure
  // finds the row count this particular batch fits in, instead of failing the whole backfill.
  if (texts.length > 1) {
    const half = Math.ceil(texts.length / 2);
    return [...await embedBatch(texts.slice(0, half)), ...await embedBatch(texts.slice(half))];
  }
  throw new Error('kb_embed batch mode failed four times on a single text');
}

async function status() {
  const [s] = await sql(`select
      (select count(*) from public.certification_exam_question) * 5 as want,
      (select count(*) from public.certification_exam_question_vector) as have,
      (select count(*) from public.agent_knowledge ak join public.org_agents a on a.agent_key=ak.agent_key and a.active) as ak_want,
      (select count(*) from public.agent_knowledge ak join public.org_agents a on a.agent_key=ak.agent_key and a.active where ak.embedding_gte is not null) as ak_have`);
  return s;
}

// ---- pass 1: question stems and options -------------------------------------------------------
// One row of certification_exam_question yields five texts: the stem, and each of the four options.
//
// EACH OPTION IS EMBEDDED ALONE, NOT WITH ITS STEM. The first build prefixed the stem to every option
// on the reasoning that an option like "AED 375,000" carries no meaning by itself. Measured on
// production 7 Sep 2026 over bookkeeper/ACCA, that reasoning was wrong and expensive: the stem is far
// longer than the option, so all four option vectors collapsed onto the stem's direction — best-evidence
// cosines sat in a 0.86-0.93 band and the median relative margin between the winner and the runner-up
// was 0.0028, i.e. the four options were indistinguishable. Top-1 agreement with the key was 30% on 40
// questions. Re-embedded option-alone, the same 40 questions gave a median margin of 0.0101 (3.6x) and
// 45% top-1 agreement. Option-alone is also the exact semantic counterpart of what the lexical sitter
// does: fn_exam_or_tsquery builds each option's tsquery from the option's own words with the stem's
// words removed as a stop list.
async function passQuestions(budget) {
  let done = 0;
  for (;;) {
    if (done >= budget) return done;
    const rows = await sql(`select q.id, q.question, q.option_a, q.option_b, q.option_c, q.option_d
                              from public.certification_exam_question q
                             where not exists (select 1 from public.certification_exam_question_vector v
                                                where v.question_id = q.id and v.kind = 'D')
                             order by q.id limit 60`);
    if (!rows.length) return done;
    const jobs = [];
    for (const r of rows) {
      jobs.push({ id: r.id, kind: 'stem', text: String(r.question || '') });
      for (const [k, col] of [['A','option_a'],['B','option_b'],['C','option_c'],['D','option_d']]) {
        jobs.push({ id: r.id, kind: k, text: String(r.question || '') + '\n' + String(r[col] || '') });
      }
    }
    const batches = [];
    for (let i = 0; i < jobs.length; i += BATCH) batches.push(jobs.slice(i, i + BATCH));
    for (let i = 0; i < batches.length; i += PARALLEL) {
      const slice = batches.slice(i, i + PARALLEL);
      const vecs = await Promise.all(slice.map((b) => embedBatch(b.map((j) => j.text))));
      const values = [];
      slice.forEach((b, bi) => b.forEach((j, ji) =>
        values.push(`(${j.id}, ${q(j.kind)}, '[${vecs[bi][ji].join(',')}]'::vector(384))`)));
      await sql(`insert into public.certification_exam_question_vector (question_id, kind, embedding)
                 values ${values.join(',')}
                 on conflict (question_id, kind) do update set embedding = excluded.embedding, embedded_at = now()`);
      done += values.length;
      process.stdout.write(`\r  questions: ${done} vectors written this run`);
    }
  }
}

// ---- pass 2: the employees' own notes ----------------------------------------------------------
async function passAgentKnowledge(budget) {
  let done = 0;
  for (;;) {
    if (done >= budget) return done;
    const rows = await sql(`select ak.id, ak.topic, ak.content from public.agent_knowledge ak
                              join public.org_agents a on a.agent_key = ak.agent_key and a.active
                             where ak.embedding_gte is null order by ak.id limit 64`);
    if (!rows.length) return done;
    const batches = [];
    for (let i = 0; i < rows.length; i += BATCH) batches.push(rows.slice(i, i + BATCH));
    for (let i = 0; i < batches.length; i += PARALLEL) {
      const slice = batches.slice(i, i + PARALLEL);
      const vecs = await Promise.all(slice.map((b) =>
        embedBatch(b.map((r) => String(r.topic || '') + '\n' + String(r.content || '')))));
      for (let bi = 0; bi < slice.length; bi++) {
        for (let ri = 0; ri < slice[bi].length; ri++) {
          await sql(`update public.agent_knowledge set embedding_gte = '[${vecs[bi][ri].join(',')}]'::vector(384)
                      where id = ${slice[bi][ri].id}`);
          done++;
        }
      }
      process.stdout.write(`\r  agent_knowledge: ${done} vectors written this run`);
    }
  }
}

const before = await status();
console.log(`before: question vectors ${before.have}/${before.want}; agent_knowledge ${before.ak_have}/${before.ak_want}`);
if (args.includes('--status')) process.exit(0);

const nq = await passQuestions(cap);
console.log(`\n  questions pass wrote ${nq}`);
const na = await passAgentKnowledge(Math.max(0, cap - nq));
console.log(`\n  agent_knowledge pass wrote ${na}`);

const after = await status();
console.log(`after:  question vectors ${after.have}/${after.want}; agent_knowledge ${after.ak_have}/${after.ak_want}`);
const complete = Number(after.have) >= Number(after.want) && Number(after.ak_have) >= Number(after.ak_want);
console.log(complete ? 'COMPLETE' : 'INCOMPLETE — re-run to resume');
process.exit(complete ? 0 : 1);
