// A TRADE QUESTION READS ITS OWN TRADE PACK (ceo, 19 Oct 2026). Measured: 36 trade market packs and real_estate_services
// recalled 0.000-0.333 for sales_engineer and customer_support. Two causes, both pinned here:
//   1. RANKING: a trade's short market entry lost to generic kb_chunks and to its own base pack, even with the trade
//      resolved. Both retrieval routines now reserve k slots for the resolved trade's pack rows (every audience: trade
//      packs are public, #1567's guard still applies), and when the planner's kind is about the market or pricing the
//      trade's market and pricing rows lead. Meaning comes from the planner's kind and the rows' kind
//      tags, never from the question's words.
//   2. ML VECTORS: "AFTER DELETE OR UPDATE OF title, content" fires whenever the column is in the SET list, so every
//      verified-pack load (an upsert setting every column) deleted every pack row's ml vector, changed or not: 0 of
//      5,102 trade-pack rows had one. The triggers now clear a vector only when the text changed, or the row is deleted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const FILE = 'scripts/sql/a_trade_question_reads_its_own_trade_pack.sql';
const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const src = read(FILE);
const body = (name) => { const i = src.indexOf(`FUNCTION public.${name}(`); assert.ok(i > 0, name); return src.slice(i, src.indexOf('end $fn$;', i)); };
const MARKET = ['kind:uae_market_products', 'kind:uae_market_brands', 'kind:uae_market_sizes'];

test('both routines know the market-and-pricing kinds and decide "lead with the market" from the resolved kind', () => {
  for (const fn of ['fn_reason_retrieve', 'fn_reason_retrieve_ml']) {
    const b = body(fn);
    for (const k of MARKET) assert.ok(b.includes(`'${k}'`), `${fn}: ${k}`);
    // never NULL: a NULL "lead" sorts FIRST under DESC and put the market rows ahead of every question (measured)
    assert.match(b, /v_lead_market := coalesce\(v_trade is not null and \('kind:' \|\| v_kind\) = any\(v_market\), false\);/, fn);
    assert.ok(b.includes("(('kind:' || v_kind) = any(v_market) and s.tags && v_market)"), fn + ': a market kind admits the market family');
  }
});

test('fn_reason_retrieve reserves the resolved trade\'s best k rows first, market rows leading', () => {
  const b = body('fn_reason_retrieve');
  assert.match(b, /case when t\.tr <= k then 2/);
  assert.match(b, /row_number\(\) over \(order by \(v_lead_market and s\.tags && v_market\) desc, h2\.sim desc\) tr/);
  assert.match(b, /order by reserved desc, tr nulls last, sim desc limit k \* 2/);
  assert.match(b, /order by \(v_trade is not null and s\.tags && v_trade\) desc, s\.embedding_gte <=> p_embedding limit case when v_trade is null then k else 128 end/);
});

test('fn_reason_retrieve_ml makes every trade row a candidate and reserves k of them, market rows leading', () => {
  const b = body('fn_reason_retrieve_ml');
  const cand = b.slice(b.indexOf("-- every row of the resolved trade's own pack is a candidate"));
  assert.match(cand, /where v_trade is not null and s\.runtime_index_eligible and s\.tags && v_trade/);
  assert.ok(cand.slice(0, 1200).includes("(v_internal or not (s.tags && array['audience:internal', 'kind:company']"), "#1567's audience guard on the trade candidates");
  assert.match(b, /trade_rows as \([\s\S]*?row_number\(\) over \(order by \(v_lead_market and s\.tags && v_market\) desc, h\.score desc\) tr[\s\S]*?order by tr limit k/);
  assert.match(b, /select t\.\*, 2 reserved from trade_rows t/);
  assert.match(b, /order by reserved desc, tr nulls last, score desc/);
  assert.match(b, /order by sc\.score desc limit case when v_trade is null then k else 128 end/);
});

test('an ml vector is cleared only when the embedded text changed, or the row is deleted', () => {
  const tables = ['accountant_knowledge', 'agent_knowledge', 'ceo_knowledge', 'company_faq', 'it_engineer_knowledge', 'kb_chunks', 'kb_chunks_old',
    'marketing_knowledge', 'ops_knowledge', 'reasoning_knowledge_candidate', 'sales_knowledge', 'seat_case_memory', 'support_knowledge'];
  for (const t of tables) {
    const m = src.match(new RegExp(String.raw`create trigger z_ml_vectors_stale after update of ([a-z_, ]+) on public\.${t} for each row\s+when \(([^)]*)\)`));
    assert.ok(m, t + ': no text-changed update trigger');
    for (const c of m[1].split(', ')) assert.ok(m[2].includes(`old.${c} is distinct from new.${c}`), `${t}: ${c} not compared`);
    assert.ok(src.includes(`create trigger z_ml_vectors_stale_del after delete on public.${t} for each row`), t + ': delete trigger');
  }
  assert.ok(!/after delete or update of/i.test(src), 'the unconditional form is back');
});

test('the planner can name the market file\'s kinds', () => {
  const think = read('supabase/functions/_shared/think.ts');
  const kinds = think.slice(think.indexOf('export const ENTRY_KINDS'), think.indexOf('] as const;', think.indexOf('export const ENTRY_KINDS')));
  for (const k of MARKET) assert.ok(kinds.includes(`'${k.slice(5)}'`), k);
});

test('the file waits for merge with a note, or is in MANIFEST, never both', () => {
  const pending = existsSync(new URL('../../scripts/sql/pending/a_trade_question_reads_its_own_trade_pack.txt', import.meta.url));
  const listed = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).some((l) => l.endsWith(FILE));
  assert.ok(pending !== listed);
});
