// THE SEAT QUALIFICATION EXAM: is each seat qualified against its own job description? Seat: it_engineer, founder
// instruction 888, 28 Sep 2026.
//
// WHY. The model-graded exam was retired (routine work is code) and the daily recall exam
// (fn_it_engineer_knowledge_recall_exam) scores recall@5 on the packs' own eval questions: it says whether an entry is
// FOUND, never whether the seat then holds the FACT the job needs. The founder's method (888): standard = the job
// description; checklist; audit; build the gaps; ONLY THEN the exam. The audit lives beside the job descriptions
// (scratchpad/standards/seat_qualification.md); the questions live in knowledge/exams/<seat>.json, one per checklist item
// or more, each with the entry ids that answer it AND the facts the answer must contain.
//
// HOW AN ITEM PASSES (no model, no word list deciding anything the seat does): the English question is embedded by the
// same free gte-small path think() uses and put to the routine the seat calls at decision time,
// public.fn_reason_retrieve(seat, vector, 6). PASS = one of the first 5 rows it returns IS an expected entry (the
// English row '<id>') AND that row's excerpt -- the 1,200 characters the seat actually sees -- contains every expected
// fact (case-insensitive). Found-but-truncated fails: a fact past character 1,200 never reaches the seat.
// Arabic is not graded here: the expected facts are English strings, and Arabic retrieval on gte-small is measured at
// ~0 by knowledge_pack_eval.mjs (FLOOR.ar = 0). An Arabic exam waits on the multilingual embedder.
//
// TWO MODES, the machinery of knowledge_pack_eval.mjs:
//   live   fn_reason_retrieve read-only against what is loaded; excerpts are the routine's own.
//   staged one ABORTED transaction per chunk upserts the seat pack rows that could reach each question's top 6 (exact
//          cosine), calls the same routine, raises the top-5 ids back; nothing commits. The excerpt of a staged row is
//          left(body_en, 1200) of the repository entry, i.e. exactly what the loader would write.
//
//   node scripts/eval/seat_qualification_exam.mjs [--mode live|staged] [--seat ceo] [--out results.json]
//   node scripts/eval/seat_qualification_exam.mjs --load [--seat ceo]   (writes public.seat_exam_item; see below)
//
// Exit 1 when an exam file is malformed (an expected id missing, or a fact that is not in the first 1,200 characters
// of an expected entry: such an item could never pass, which would make the pass rate measure the author, not the
// seat). A low pass rate is a finding reported per seat, not an exit code: there is no floor yet (first baseline).
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const TOP = 5;
export const K_RETRIEVE = 6;          // what think() passes
export const EXCERPT = 1200;          // fn_reason_retrieve: left(body, 1200)
const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const has = (text, fact) => String(text ?? '').toLowerCase().includes(String(fact).toLowerCase());

/** THE GRADER. top: the first rows the routine returned, [{id, excerpt}] in rank order. */
export function grade(item, top) {
  const expected = new Set(item.expected_entry_ids);
  const hits = top.slice(0, TOP).filter((r) => expected.has(r.id));        // '<id>@ar' is not an English hit
  const full = hits.find((r) => item.expected_facts.every((f) => has(r.excerpt, f)));
  return {
    pass: !!full,
    found: hits.length > 0,
    missing: full || !hits.length ? [] : item.expected_facts.filter((f) => !has(hits[0].excerpt, f)),
  };
}

/** Every reason an exam item could never pass, named. entries: Map id -> pack entry. */
export function validateExam(exam, entries) {
  const err = [];
  if (!Array.isArray(exam.items) || !exam.items.length) return ['no items'];
  const ids = new Set();
  for (const it of exam.items) {
    const at = it.id ?? '(no id)';
    if (ids.has(at)) err.push(`${at}: duplicate id`);
    ids.add(at);
    if (!it.q_en?.trim()) err.push(`${at}: q_en missing`);
    if (!Array.isArray(it.expected_entry_ids) || !it.expected_entry_ids.length) { err.push(`${at}: no expected entries`); continue; }
    if (!Array.isArray(it.expected_facts) || !it.expected_facts.length || it.expected_facts.some((f) => !String(f).trim())) err.push(`${at}: no expected facts`);
    for (const id of it.expected_entry_ids) {
      const e = entries.get(id);
      if (!e) { err.push(`${at}: expects ${id}, not in the seat pack`); continue; }
      for (const f of it.expected_facts ?? []) if (!has(e.body_en.slice(0, EXCERPT), f)) err.push(`${at}: "${f}" is not in the first ${EXCERPT} characters of ${id}`);
    }
  }
  return err;
}

export function readExams(root = join(REPO, 'knowledge', 'exams')) {
  return readdirSync(root).filter((f) => /^[a-z_]+\.json$/.test(f)).sort()
    .map((f) => ({ file: `knowledge/exams/${f}`, ...JSON.parse(readFileSync(join(root, f), 'utf8')) }));
}

async function main() {
  const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const { readPacks, rowsOf, upsertSql, makeEmbedder, cosine, vecLit, SEAT_TABLE } = await import('../kb/verified_packs.mjs');
  const { sql, PROJECT_REF } = await import('../lib/db.mjs');
  const mode = at('--mode') ?? 'live';
  const packs = readPacks(join(REPO, 'knowledge'));
  const exams = readExams().filter((x) => !at('--seat') || x.seat === at('--seat'));

  const bad = [];
  for (const x of exams) {
    const p = packs.find((q) => q.kind === 'seat' && q.code === x.seat);
    if (!p || p.errors.length) { bad.push(`${x.file}: seat pack ${x.seat} missing or refused (${p?.errors.slice(0, 3)})`); continue; }
    x.pack = p;
    x.entries = new Map(p.pack.entries.map((e) => [e.id, e]));
    for (const e of validateExam(x, x.entries)) bad.push(`${x.file}: ${e}`);
  }
  if (bad.length) { console.error(bad.join('\n')); process.exit(1); }

  const embedder = await makeEmbedder(sql, PROJECT_REF);

  // --load (29 Sep 2026, ceo, instruction 1009): store each item WITH its question's vector in public.seat_exam_item,
  // so the seats' monthly self-review (fn_seat_self_review) re-grades it in SQL against live retrieval, no embedder
  // needed at run time. The seat's rows are replaced by the file's: an item removed from the file leaves the exam.
  if (process.argv.includes('--load')) {
    const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
    const arr = (a) => `array[${a.map(lit).join(',')}]::text[]`;
    for (const x of exams) {
      const vecs = await embedder.many(x.items.map((i) => i.q_en));
      const rows = x.items.map((it, i) => `(${lit(x.seat)}, ${lit(it.id)}, ${lit(it.checklist ?? 'unlisted')}, ${lit(it.q_en)}, ${arr(it.expected_entry_ids)}, ${arr(it.expected_facts)}, ${vecLit(vecs[i])}, ${lit(x.file)})`);
      await sql(`begin;
        delete from public.seat_exam_item where seat = ${lit(x.seat)} and item_id <> all(${arr(x.items.map((i) => i.id))});
        insert into public.seat_exam_item (seat, item_id, checklist, q_en, expected_entry_ids, expected_facts, q_vec, source_file)
        values ${rows.join(',\n')}
        on conflict (seat, item_id) do update set checklist = excluded.checklist, q_en = excluded.q_en, expected_entry_ids = excluded.expected_entry_ids,
          expected_facts = excluded.expected_facts, q_vec = excluded.q_vec, source_file = excluded.source_file, loaded_at = now();
        commit;`, { retry: false });
      console.log(`  loaded ${x.seat}: ${x.items.length} items`);
    }
    return;
  }
  const topExpr = (seat, vec) => `(select coalesce(jsonb_agg(x->>'id' order by n), '[]'::jsonb) from jsonb_array_elements(public.fn_reason_retrieve('${seat}', ${vecLit(vec)}, ${K_RETRIEVE})) with ordinality t(x, n) where n <= ${TOP})`;
  console.log(`mode: ${mode}`);
  const report = { mode, at: new Date().toISOString(), top: TOP, seats: [] };

  for (const x of exams) {
    const vecs = await embedder.many(x.items.map((i) => i.q_en));
    x.items.forEach((it, i) => { it.vec = vecs[i]; });
    const excerptOf = (id) => x.entries.get(id)?.body_en.slice(0, EXCERPT) ?? '';   // staged rows: what the loader writes
    if (mode === 'live') {
      for (let c = 0; c < x.items.length; c += 10) {
        const part = x.items.slice(c, c + 10);
        // The routine is STABLE and this is one SELECT; the API read_only role cannot EXECUTE it (42501, 23 Sep 2026).
        const [r] = await sql(`select jsonb_build_array(${part.map((it) => `(select coalesce(jsonb_agg(jsonb_build_object('id', x->>'id', 'excerpt', x->>'excerpt') order by n), '[]'::jsonb) from jsonb_array_elements(public.fn_reason_retrieve('${x.seat}', ${vecLit(it.vec)}, ${K_RETRIEVE})) with ordinality t(x, n) where n <= ${TOP})`).join(',')}) got`);
        part.forEach((it, j) => { it.top = r.got[j]; });
      }
    } else {
      const rows = rowsOf(x.pack).filter((r) => r.table === SEAT_TABLE[x.seat]);
      const rv = await embedder.many(rows.map((r) => r.text));
      rows.forEach((r, i) => { r.vec = rv[i]; });
      // 8 questions a chunk: the answer comes back through an error message the management API cuts at ~2,000 characters.
      for (let c = 0; c < x.items.length; c += 8) {
        const part = x.items.slice(c, c + 8);
        const stage = new Map();
        for (const it of part) rows.map((r) => [r, cosine(it.vec, r.vec)]).sort((a, b) => b[1] - a[1]).slice(0, K_RETRIEVE).forEach(([r]) => stage.set(r.record_id, r));
        const block = `do $qdexam$ declare o jsonb := '[]'::jsonb; begin\n${part.map((it) => `o := o || jsonb_build_array(${topExpr(x.seat, it.vec)});`).join('\n')}\nraise exception 'CHK<<%>>', o::text; end $qdexam$;`;
        try { await sql(upsertSql(SEAT_TABLE[x.seat], [...stage.values()]) + block, { retry: false }); throw new Error('the probe committed instead of rolling back'); }
        catch (e) {
          const m = String(e.message).match(/CHK<<(.*?)>>/s);
          if (!m) throw new Error(`${x.seat}: the probe failed before it could report: ${String(e.message).slice(0, 400)}`);
          // The management API may return the message JSON-escaped (\" for "): unescape once before parsing.
          const txt = m[1].includes('\\"') ? m[1].replace(/\\"/g, '"') : m[1];
          JSON.parse(txt).forEach((ids, j) => { part[j].top = ids.map((id) => ({ id, excerpt: excerptOf(id) })); });
        }
      }
    }
    const graded = x.items.map((it) => ({ id: it.id, checklist: it.checklist, q: it.q_en, ...grade(it, it.top), top: it.top.map((r) => r.id) }));
    const pass = graded.filter((g) => g.pass).length;
    const found = graded.filter((g) => g.found).length;
    report.seats.push({ seat: x.seat, items: graded.length, pass, found, rate: +(pass / graded.length).toFixed(3), failing: graded.filter((g) => !g.pass) });
    console.log(`  ${x.seat.padEnd(18)} pass ${pass}/${graded.length} = ${(100 * pass / graded.length).toFixed(1)}%   (entry found ${found}, facts missing ${found - pass})`);
  }
  for (const s of report.seats) for (const f of s.failing) console.log(`FAIL ${f.id} [${f.checklist}] ${f.found ? 'facts missing: ' + f.missing.join(' | ') : 'not in top 5'} -- ${f.q}`);
  if (at('--out')) writeFileSync(at('--out'), JSON.stringify(report, null, 1));
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) await main();
