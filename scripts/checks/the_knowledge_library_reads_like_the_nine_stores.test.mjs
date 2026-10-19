// THE KNOWLEDGE LIBRARY READS LIKE THE NINE STORES (5 Oct 2026, it_engineer; ledger 1085 stage 2, phase 1).
//
// WHAT FAILS IF THE CAUSE RETURNS (static, over the SQL file):
//   * a library reader reads one of the nine stores again (it must read knowledge_library, plus company_faq,
//     reasoning_knowledge_candidate and knowledge_vector_ml, which are not among the nine);
//   * fn_reason_retrieve / fn_reason_retrieve_ml lose the one-line dispatch, or the dispatch reads anything but the
//     flag, or passes fewer arguments than the signature has;
//   * a store loses its mirror trigger (a writer would stop reaching the library), or knowledge_vector_ml loses its two;
//   * a library row takes an ALIAS's vector (probed 5 Oct 2026: a kb row the ml queue had not reached took its agent
//     copy's ml vector and outranked a ceo exam row, ceo/en ml 0.750 -> 0.667), or the primary stops being chosen by
//     store priority (then the fill order decides, and the probe's layout no longer describes the library);
//   * an eligible text merges with an ineligible copy (a superseded ops row would be served on an alias's strength);
//   * a writer's own transaction can fail on the library: a lock per row (out of shared memory at 5,000 rows, probed),
//     a NULL text reaching the library's NOT NULL, a NULL source_kind silently dropping a row, or an UPDATE trigger
//     firing on columns the library does not map;
//   * the fused reader's per-store ml candidates go back to a JOIN against knowledge_vector_ml (probed: planned as
//     2,303 sequential scans, 4.5 s a call, against 0.1 s with one primary-key probe a row);
//   * a fill page may exceed 5,000 origins, or runs without the purge's advisory lock;
//   * a new routine lacks its revoke or its pinned search_path; a new table lacks RLS, its policy or its registry row.
//
//   node --test scripts/checks/the_knowledge_library_reads_like_the_nine_stores.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/one_knowledge_library_is_built_beside_the_nine_stores_and_read_behind_a_flag.sql';
const code = readFileSync(join(REPO, FILE), 'utf8').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const STORES = ['kb_chunks', 'ops_knowledge', 'agent_knowledge', 'sales_knowledge', 'accountant_knowledge',
  'it_engineer_knowledge', 'marketing_knowledge', 'ceo_knowledge', 'support_knowledge'];

function body(name) {
  const a = code.toLowerCase().indexOf(`create or replace function public.${name}(`);   // the two read-back bodies are upper case
  assert.ok(a >= 0, `${name} is defined in ${FILE}`);
  const ends = ['$fn$;', '$function$;'].map((e) => code.indexOf(e, a)).filter((x) => x >= 0);
  return code.slice(a, Math.min(...ends));
}

test('the library readers read the library, never one of the nine stores', () => {
  for (const f of ['fn_reason_retrieve_library', 'fn_reason_retrieve_ml_library']) {
    const b = body(f);
    for (const s of STORES) assert.ok(!new RegExp(`public\\.${s}\\b`).test(b), `${f} reads public.${s}`);
    assert.match(b, /public\.knowledge_library\b/);
    assert.match(b, /l\.seats && v_seats/, `${f} filters by seat`);
  }
});

// The dispatch is NOT in this file (release operator, 19 Oct 2026). Its old six/eight-argument reader bodies predated
// #1567's audience guard; applying them recreated the unguarded overloads, so the file now drops them and phase 2 adds
// the dispatch to the guarded readers. This test holds that line until then.
test('this file never defines a legacy reader, and drops the pre-audience overloads', () => {
  for (const f of ['fn_reason_retrieve', 'fn_reason_retrieve_ml']) {
    assert.ok(code.toLowerCase().indexOf(`create or replace function public.${f}(`) < 0, `${FILE} defines ${f} again`);
  }
  assert.match(code, /DROP FUNCTION IF EXISTS public\.fn_reason_retrieve\(text, vector, integer, text, text, text\);/);
  assert.match(code, /DROP FUNCTION IF EXISTS public\.fn_reason_retrieve_ml\(text, vector, vector, integer, integer, text, text, text\);/);
  assert.match(body('fn_knowledge_library_read'), /key = 'knowledge_library_read'\) = 'library'/);
});

test('every store and knowledge_vector_ml mirror into the library', () => {
  for (const s of STORES) {
    assert.match(code, new RegExp(`create trigger zz_knowledge_library_mirror after insert or[^;]*on public\\.${s}\\s+for each row execute function public\\.fn_knowledge_library_mirror\\(\\)`), `${s} has no mirror trigger`);
  }
  assert.match(code, /create trigger zz_knowledge_library_mirror_ml after insert or update of src, row_id, embedding on public\.knowledge_vector_ml/);
  assert.match(code, /create trigger zz_knowledge_library_mirror_ml_delete after delete on public\.knowledge_vector_ml/);
});

test('a library row carries only its primary origin\'s vectors, and the primary is chosen by store priority', () => {
  const b = body('fn_knowledge_library_recompute');
  assert.match(b, /order by case origin_store when 'kb_chunks' then 1 when 'ops_knowledge' then 2 when 'agent_knowledge' then 3 else 4 end,\s+origin_id/);
  assert.match(b, /where v\.src = p\.origin_store and v\.row_id = p\.origin_id;/, 'the ml vector is not the primary\'s');
  assert.match(b, /embedding_gte = p\.embedding_gte/, 'the gte vector is not the primary\'s');
  assert.ok(!/coalesce\(v_gte|coalesce\(v_ml/.test(b), 'an alias vector is taken');
});

test('an eligible text never merges with an ineligible copy', () => {
  assert.match(body('fn_knowledge_library_sync'), /l\.content_md5 = v_md5 and l\.runtime_eligible = s\.runtime_eligible/);
  assert.match(body('fn_knowledge_library_fill_page'), /l\.content_md5 = p\.md5\s+and l\.runtime_eligible = p\.runtime_eligible/);
});

test('a writer never fails on the library: one shared lock, no NOT NULL trap, triggers only on mapped columns', () => {
  const s = body('fn_knowledge_library_sync');
  assert.match(s, /pg_advisory_xact_lock_shared\(hashtext\('public\.knowledge_library'\)\)/);
  assert.ok(!/pg_advisory_xact_lock\(hashtext\('knowledge_library:/.test(code), 'a lock per row ran out of shared memory at 5,000 rows');
  assert.match(body('fn_knowledge_library_fill_page'), /perform pg_advisory_xact_lock\(hashtext\('public\.knowledge_library'\)\);/);
  assert.match(body('fn_knowledge_library_source_sql'), /where s\.content is not null'/);
  assert.match(body('fn_knowledge_library_source_sql'), /c\.source_kind is not distinct from ''qd_kb_pack''/, 'a NULL source_kind drops the row');
  for (const s2 of STORES) assert.match(code, new RegExp(`after insert or delete or update of [^;]*on public\\.${s2}\\s+for each row`), `${s2}: UPDATE fires on every column`);
  assert.match(code, /create trigger zz_knowledge_library_mirror_citation after insert or delete or update of cited on public\.sales_decision_log/);
});

test('the fused reader probes knowledge_vector_ml by primary key per candidate, never by a join', () => {
  const b = body('fn_reason_retrieve_ml_library');
  assert.match(b, /\(select v\.embedding <=> m from public\.knowledge_vector_ml v\s+where v\.src = 'knowledge_library' and v\.row_id = e\.id::text\) d/);
  assert.ok(!/from elig e join public\.knowledge_vector_ml/.test(b), 'the per-store ml candidates join knowledge_vector_ml again');
});

test('a fill page is at most 5,000 origins and never runs beside a purge or trim batch', () => {
  const b = body('fn_knowledge_library_fill_page');
  assert.match(b, /least\(coalesce\(p_n, 2000\), 5000\)/);
  assert.match(b, /pg_try_advisory_xact_lock\(hashtext\('public\.fn_kb_purge_batch'\)\)/);
});

test('new routines are revoked and pinned; new tables have RLS, a policy, a revoke and a registry row', () => {
  const created = [...code.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1])
    .filter((n) => !['fn_reason_retrieve', 'fn_reason_retrieve_ml'].includes(n));
  for (const n of created) {
    assert.match(code, new RegExp(`revoke execute on function public\\.${n}\\([^)]*\\) from public, anon, authenticated;`), `${n} is not revoked`);
    assert.match(body(n), /set search_path to 'public'/, `${n} has no pinned search_path`);
  }
  for (const t of ['knowledge_library', 'knowledge_library_origin']) {
    assert.match(code, new RegExp(`alter table public\\.${t} enable row level security;`));
    assert.match(code, new RegExp(`create policy ${t}_service_role_only on public\\.${t}`));
    assert.match(code, new RegExp(`revoke all on public\\.${t} from anon, authenticated;`));
    assert.match(code, new RegExp(`\\('${t}', true, 'knowledge',`), `${t} has no export registry row`);
  }
});
