// DOES A SEAT REMEMBER A CASE BY MEANING AND USE IT? The learning-loop recall proof. Seat: it_engineer
// (shared platform). 28 Sep 2026, founder_instruction 887.
//
// The founder, 23 Sep 2026: a seat that meets a case like one it handled before must remember it, by meaning.
// This proves the whole loop end to end on PRODUCTION, inside ONE transaction that always raises, so nothing
// commits and nothing can leave the database (the subjects are ZZ DEMO IT findings: no customer, no supplier,
// no address; the probe also asserts it queued no notification and no HTTP call):
//
//   A. it_engineer handles case A (an IT finding, opened then closed with its fix). The z90_case_memory
//      trigger writes the case and its lesson ("Fixed by: ..."); A is embedded with the SAME free gte-small
//      model the heartbeat uses, and written through the same writer (fn_case_embed_write).
//   B. a similar case B arrives, worded differently. The decision path does what case_recall.ts does:
//      fn_case_recall (own seat, this kind, B excluded) -> must return A above the 0.84 floor; the judgement
//      is opened WITH that recall (fn_judgement_record), and the deterministic decision "apply the fix that
//      closed the precedent" is closed naming A (fn_judgement_decided p_followed). When B closes, its real
//      outcome lands on the judgement through the z91 outcome trigger.
//   C. NEGATIVE CONTROL: an unrelated case C must NOT recall A. And ISOLATION: another seat recalling B's
//      vector without asking for other seats must not see A.
//
// Before the pending SQL is applied, the pending files this depends on are replayed inside the same aborted
// transaction first (as knowledge_pack_eval.mjs staged mode does). Afterwards, a read-only query asserts that
// zero ZZ DEMO rows of this proof exist.
//
// WHAT THE FIRST RUN FOUND (28 Sep 2026), printed as c_recalled_similarities and NOT gated here: the unrelated
// case C (a supplier's expired licence) does not recall A (0.820 < 0.84), but it DOES recall 20 real IT findings
// at 0.840-0.877. The 0.84 floor was measured on free-text situations; every IT finding is written in one
// "title | where: .. | blast: .." shape, and the shared template lifts unrelated findings over it. The floor
// needs re-measuring per case kind (or the template left out of the embedded text); that is its own change.
//
//   node scripts/eval/learning_loop_recall_proof.mjs          exit 0 = proved, 1 = an assertion failed
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeEmbedder, vecLit } from '../kb/verified_packs.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const { sql, PROJECT_REF } = await import('../lib/db.mjs');
const FLOOR = 0.84;             // fn_case_recall's measured floor (every_seat_remembers_its_cases_and_recalls_them_by_meaning.sql)
const TAG = 'zz_demo_887';      // every subject key starts with this; the leftover count reads it

// The situation text exactly as fn_case_from_it_finding writes it: title | where: .. | blast: ..
const sit = (f) => `${f.title} | where: ${f.where} | blast: ${f.blast}`;
const A = { key: `${TAG}:a`, title: 'ZZ DEMO the nightly database backup did not complete and no export file was written',
  where: 'ZZ DEMO backup duty', blast: 'internal', fix: 'ZZ DEMO raised the backup statement timeout to 20 minutes and re-ran the export' };
const B = { key: `${TAG}:b`, title: "ZZ DEMO last night's database backup never finished, so there is no dump file",
  where: 'ZZ DEMO backup duty', blast: 'internal', fix: 'ZZ DEMO applied the precedent fix: longer statement timeout, export re-run' };
const C = { key: `${TAG}:c`, title: 'ZZ DEMO a supplier uploaded a trade licence that expired last month',
  where: 'ZZ DEMO supplier onboarding', blast: 'supplier_facing' };

// PENDING SQL this proof depends on: replayed only while its note says it is not applied yet.
const PENDING = ['a_decision_names_the_recalled_case_it_followed'];
const replay = PENDING.filter((n) => existsSync(join(REPO, 'scripts/sql/pending', n + '.txt')))
  .map((n) => readFileSync(join(REPO, 'scripts/sql', n + '.sql'), 'utf8')).join('\n');

const embedder = await makeEmbedder(sql, PROJECT_REF);
// THE FIXTURE MARKER IS NOT EMBEDDED. 'ZZ DEMO' is shared text no real case carries, and shared text is shared
// meaning: measured 28 Sep 2026, A~C (unrelated) is 0.791 bare, 0.820 in the real "title | where | blast" shape
// and 0.847 with the marker in title and where, which alone crosses the 0.84 floor. The ROWS carry the marker (so
// they can never be mistaken for real ones); the vectors are of the same text without it, i.e. of a real case.
// The marked similarity is still measured and printed, so the effect stays visible.
const unmark = (s) => s.replace(/ZZ DEMO /g, '');
const [vA, vB, vC, mA, mC] = await embedder.many([...[sit(A), sit(B), sit(C)].map(unmark), sit(A), sit(C)]);
const dot = (x, y) => x.reduce((s, v, i) => s + v * y[i], 0);
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const finding = (f) => `insert into public.it_engineer_finding (issue_key, title, where_it_is, blast, affected, evidence, ruled_out, undetermined, raised_by)
  values (${q(f.key)}, ${q(f.title)}, ${q(f.where)}, ${q(f.blast)}, 0, '{}'::jsonb, '{}', '{}', 'it_engineer');`;

const probe = `
do $p$
declare
  t0 timestamptz := now();  -- the transaction's start: every row written below is created at or after it
  n_net0 bigint := (select count(*) from net.http_request_queue);
  a_id bigint; a_lessons text[]; rb jsonb; rc jsonb; ri jsonb; hit jsonb; trace jsonb; j bigint; jr record; bo jsonb;
  r jsonb := '{}';
begin
  -- A: handled and closed with its fix
  ${finding(A)}
  update public.it_engineer_finding set closed_at = now(), close_note = ${q(A.fix)} where issue_key = ${q(A.key)};
  select id, lessons into a_id, a_lessons from public.seat_case_memory where source_table = 'it_engineer_finding' and source_id = ${q(A.key)};
  if a_id is null then raise exception 'CHK<<%>>', '{"error":"case A was not captured by the trigger"}'; end if;
  perform public.fn_case_embed_write(a_id, ${vecLit(vA)}::vector(384), (select md5(situation) from public.seat_case_memory where id = a_id));
  r := r || jsonb_build_object('a_case_id', a_id, 'a_lessons', a_lessons,
    'a_embedded', (select embedding is not null from public.seat_case_memory where id = a_id));

  -- B: a similar case arrives; the decision path recalls, records, decides naming what it followed
  ${finding(B)}
  rb := public.fn_case_recall('it_engineer', ${vecLit(vB)}::vector(384), null, 5, 'it_finding', false, null, 'it_engineer_finding', ${q(B.key)});
  select c into hit from jsonb_array_elements(rb->'cases') c where (c->>'case_id')::bigint = a_id;
  trace := jsonb_build_object('available', true, 'reason', null, 'finalised_precedent', coalesce((rb->>'finalised_precedent')::boolean, false),
    'cases', coalesce((select jsonb_agg(jsonb_build_object('case_id', c->'case_id', 'similarity', c->'similarity', 'finalised', c->'finalised'))
                         from jsonb_array_elements(rb->'cases') c), '[]'::jsonb));
  j := public.fn_judgement_record('it_engineer', 'triage', jsonb_build_object('issue_key', ${q(B.key)}), ${q(sit(B))}, trace);
  if hit is not null then
    perform public.fn_judgement_decided(j, 'answered', 'follow finalised precedent #' || a_id || ': ' || coalesce(hit->>'outcome', ''), null, 'deterministic', array[a_id]);
  else
    perform public.fn_judgement_decided(j, 'answered', 'no precedent recalled', null, 'deterministic', '{}'::bigint[]);
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = ${q(B.fix)} where issue_key = ${q(B.key)};
  select * into jr from public.seat_judgement where id = j;
  r := r || jsonb_build_object(
    'b_recalled', (select jsonb_agg(jsonb_build_object('case_id', c->'case_id', 'similarity', c->'similarity')) from jsonb_array_elements(rb->'cases') c),
    'b_similarity_to_a', hit->'similarity', 'b_recalled_a', hit is not null, 'b_a_lesson_carried', hit->'lessons',
    'judgement', jsonb_build_object('id', jr.id, 'status', jr.status, 'decision', jr.decision, 'followed_case_ids', jr.followed_case_ids,
       'recall_case_ids', (select jsonb_agg(c->'case_id') from jsonb_array_elements(jr.recall->'cases') c),
       'outcome', jr.outcome, 'outcome_correct', jr.outcome_correct, 'finalised', jr.finalised));

  -- C: negative control, and seat isolation
  -- k = 20, the routine's maximum: A must be absent because it is below the floor, not because 5 others outranked it
  rc := public.fn_case_recall('it_engineer', ${vecLit(vC)}::vector(384), null, 20, 'it_finding', false, null, 'it_engineer_finding', ${q(C.key)});
  ri := public.fn_case_recall('sales_engineer', ${vecLit(vB)}::vector(384), null, 5, null, false, null, null, null);
  r := r || jsonb_build_object(
    'c_recalled_a', exists (select 1 from jsonb_array_elements(rc->'cases') c where (c->>'case_id')::bigint = a_id),
    'c_similarity_to_a', (select round((1 - (embedding <=> ${vecLit(vC)}::vector(384)))::numeric, 3) from public.seat_case_memory where id = a_id),
    'c_recalled_count', jsonb_array_length(rc->'cases'),
    'c_recalled_similarities', (select jsonb_agg(c->'similarity') from jsonb_array_elements(rc->'cases') c),
    'isolation_other_seat_saw_a', exists (select 1 from jsonb_array_elements(ri->'cases') c where (c->>'case_id')::bigint = a_id));

  -- nothing reached, or was queued to reach, anyone
  r := r || jsonb_build_object(
    'notifications_queued', (select count(*) from public.notifications where created_at >= t0),
    'http_calls_queued', (select count(*) from net.http_request_queue) - n_net0,
    'zz_rows_inside_tx', (select count(*) from public.seat_case_memory where source_id like '${TAG}:%'));
  raise exception 'CHK<<%>>', r;
end $p$;`;

let r;
try { await replaySql(replay + '\n' + probe, { retry: false }); console.error('the probe COMMITTED: it must always raise'); process.exit(2); }
catch (e) {
  const m = String(e.message).match(/CHK<<(.*)>>/s);
  if (!m) throw e;
  r = JSON.parse(m[1].replace(/\\"/g, '"'));
}
if (r.error) { console.error(r.error); process.exit(1); }

// Afterwards, outside the rolled-back transaction: zero rows of this proof exist anywhere it wrote.
const [left] = await sql(`select
  (select count(*) from public.it_engineer_finding where issue_key like '${TAG}:%')::int findings,
  (select count(*) from public.seat_case_memory where source_id like '${TAG}:%')::int cases,
  (select count(*) from public.seat_judgement where subject_id like '${TAG}:%')::int judgements,
  (select count(*) from public.seat_case_memory_miss where source_id like '${TAG}:%')::int misses`, { readOnly: true });
const rowsLeft = left.findings + left.cases + left.judgements + left.misses;

console.log(JSON.stringify({ replayed_pending: PENDING.filter((n) => existsSync(join(REPO, 'scripts/sql/pending', n + '.txt'))), ...r,
  c_similarity_to_a_with_marker: Number(dot(mA, mC).toFixed(3)), rows_left_after: left }, null, 2));
const checks = [
  ['A captured with its lesson', Array.isArray(r.a_lessons) && r.a_lessons.some((l) => l.startsWith('Fixed by:')) && r.a_embedded],
  [`B recalls A above the ${FLOOR} floor`, r.b_recalled_a && Number(r.b_similarity_to_a) >= FLOOR],
  ['the recall carries A\'s lesson to B', Array.isArray(r.b_a_lesson_carried) && r.b_a_lesson_carried.length > 0],
  ['the judgement records the recall and names A as followed', r.judgement.recall_case_ids?.includes(r.a_case_id) && r.judgement.followed_case_ids?.includes(r.a_case_id) && r.judgement.status === 'answered'],
  ['B\'s outcome fed back onto the judgement', !!r.judgement.outcome && r.judgement.finalised === true],
  ['negative control: C does not recall A', r.c_recalled_a === false && Number(r.c_similarity_to_a) < FLOOR],
  ['isolation: another seat does not see A', r.isolation_other_seat_saw_a === false],
  ['nothing queued to reach anyone', r.notifications_queued === 0 && r.http_calls_queued === 0],
  ['zero ZZ DEMO rows left', rowsLeft === 0],
];
for (const [name, ok] of checks) console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
process.exit(checks.every(([, ok]) => ok) ? 0 : 1);
