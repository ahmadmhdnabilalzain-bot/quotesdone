// PROBE: replay the multilingual-space SQL file and exercise its routines inside ONE aborted transaction.
// Seat: it_engineer. 23 Sep 2026. Nothing commits: the probe raises CHK<<...>> with its counts, which rolls
// back the DDL and every row it wrote. It reads real rows (it claims five case-memory rows and writes fake
// vectors for them, then the rollback removes both); it sends nothing and touches no person.
//
//   node scripts/kb/probe_multilingual_space.mjs
//
// Expect: claimed 5, vectors 5 (the five cases; counted before one ceo_knowledge row is added), the ceo seat's fused search
// answering with its own ceo_knowledge row first, case_recall_ok true with case_space 'ml', a stale write
// refused, the trigger dropping a touched row's vectors (vectors_after_trigger 0), and a cap of 0 answered
// 'daily cap reached'. 23 Sep 2026 run: exactly that.
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sql } from '../lib/db.mjs';
const file = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'sql', 'an_arabic_question_finds_the_same_knowledge_as_an_english_one.sql'), 'utf8');
const probe = `
set local statement_timeout = '60s';
do $p$ declare ceo_id text; ceo_hash text; c jsonb; r jsonb; n int; w boolean; v text; sp text; cr jsonb; rr jsonb; cap jsonb; stale int; before_cases int; after_cases int;
begin
  select count(*) into before_cases from public.seat_case_memory;
  sp := public.fn_ml_read_space();
  c := public.fn_ml_embed_claim(5);
  -- a fake unit vector per claimed row; the probe only proves the plumbing, the ranking is measured offline
  v := '[' || array_to_string(array_fill(0.0510310363::float8, array[384]), ',') || ']';
  for r in select * from jsonb_array_elements(c->'rows') loop
    w := public.fn_ml_embed_write(r->>'src', r->>'row_id', r->>'hash', v::vector(384), null);
    if not w then raise exception 'CHK<<write refused %>>', r->>'row_id'; end if;
  end loop;
  select count(*) into n from public.knowledge_vector_ml;
  cr := public.fn_case_recall_ml('it_engineer', v::vector(384), null, 3);
  -- a ceo_knowledge row in both spaces, then the ceo seat's fused search must return it first, as its own
  select s.row_id, md5(coalesce(s.title,'') || E'
' || coalesce(s.body,'')) into ceo_id, ceo_hash from public.v_knowledge_ml_source s where s.src = 'ceo_knowledge' limit 1;
  w := public.fn_ml_embed_write('ceo_knowledge', ceo_id, ceo_hash, v::vector(384), v::vector(384));
  rr := public.fn_reason_retrieve_ml('ceo', v::vector(384), v::vector(384), 6);
  -- a stale write is refused
  w := public.fn_ml_embed_write((c->'rows'->0->>'src'), (c->'rows'->0->>'row_id'), 'not-the-hash', v::vector(384), null);
  -- the trigger: touching the case's situation drops its vectors (same text written back, so nothing changes)
  update public.seat_case_memory set situation = situation where id::text = (c->'rows'->0->>'row_id');
  select count(*) into stale from public.knowledge_vector_ml where row_id = (c->'rows'->0->>'row_id');
  update public.app_secrets set value = '0' where key = 'ml_embed_daily_cap';
  cap := public.fn_ml_embed_claim(5);
  select count(*) into after_cases from public.seat_case_memory;
  raise exception 'CHK<<%>>', jsonb_build_object('space', sp, 'claimed', jsonb_array_length(c->'rows'), 'srcs', (select jsonb_agg(distinct x->>'src') from jsonb_array_elements(c->'rows') x),
    'vectors', n, 'case_recall_ok', cr->'ok', 'case_hits', jsonb_array_length(cr->'cases'), 'case_space', cr->'space',
    'retrieve_rows', jsonb_array_length(rr), 'retrieve_first', rr->0->>'source', 'retrieve_first_own', rr->0->>'own', 'stale_write_refused', not w, 'vectors_after_trigger', stale,
    'cap0', cap->>'reason', 'cases_before', before_cases, 'cases_after', after_cases)::text;
end $p$;`;
try { await sql('begin;\n' + file + '\n' + probe, { retry: false }); console.log('PROBE FAILED: it committed'); process.exitCode = 1; }
catch (e) {
  const m = String(e.message).match(/CHK<<(.*?)>>/s);
  if (!m) { console.log('PROBE FAILED: ' + String(e.message).slice(0, 1500)); process.exitCode = 1; }
  else {
    const r = JSON.parse(m[1].replace(/\\"/g, '"'));
    const want = { claimed: 5, vectors: 5, case_recall_ok: true, case_space: 'ml', retrieve_first: 'ceo_knowledge', retrieve_first_own: 'true',
      stale_write_refused: true, vectors_after_trigger: 0, cap0: 'daily cap reached' };
    const bad = Object.entries(want).filter(([k, v]) => r[k] !== v).map(([k, v]) => `${k}=${JSON.stringify(r[k])} (want ${JSON.stringify(v)})`);
    if (r.cases_before !== r.cases_after) bad.push('case memory row count changed');
    console.log(JSON.stringify(r));
    console.log(bad.length ? 'PROBE FAILED: ' + bad.join('; ') : 'PROBE OK');
    process.exitCode = bad.length ? 1 : 0;
  }
}
