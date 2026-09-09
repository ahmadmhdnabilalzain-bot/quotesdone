// MEASURE — what proportion of a realistic portal question set the Sales Engineer can answer from
// RETRIEVAL ALONE, after fn_sales_assist was widened from one corpus to seven.
//
// This is a measurement, not a check. It prints the real answer rate, the corpus each answer came
// from and the similarity it cleared, so the number in the report is one that was observed rather
// than one that was hoped for. It also runs the negative control: genuine nonsense must still fall
// through, or the floor is broken and the answer rate means nothing.
//
//   node scripts/measure_sales_engineer_estate_retrieval.mjs
import { readFileSync } from 'node:fs';

const REF = 'htdblwldjkcgjvmqkbeh';
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function sql(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const t = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 6) {
    await new Promise((s) => setTimeout(s, 2000 * (attempt + 1)));
    return sql(query, attempt + 1);
  }
  if (!r.ok) return { error: t };
  return { rows: JSON.parse(t) };
}
const one = async (q) => (await sql(q)).rows?.[0];

const S = Object.fromEntries((await sql(
  `select key, value from app_secrets where key in ('cred_fn_sales_engineer','anon_key')`)).rows.map((r) => [r.key, r.value]));
const FN = `https://${REF}.supabase.co/functions/v1/sales_engineer`;

async function ask(message, extra = {}) {
  const t0 = Date.now();
  const r = await fetch(FN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + S.anon_key },
    body: JSON.stringify({ action: 'assist', message, __secret: S.cred_fn_sales_engineer, ...extra }),
  });
  const j = await r.json().catch(() => null);
  return { ms: Date.now() - t0, status: r.status, j };
}

// ── THE QUESTION SET ──────────────────────────────────────────────────────────────────────────
// Written as a customer or a supplier would actually type them in a portal, not as keyword queries.
// Five families, because a single family would measure one corner of the corpus and call it
// coverage: technical scope, licence/registration, documents, how a quote is compared, and
// coverage/commercial terms.
const QUESTIONS = [
  // technical scope
  'what technical information do you need from me to price an HVAC chiller replacement',
  'how do I specify a fire alarm system so suppliers can quote it properly',
  'what details matter when specifying structural steel fabrication',
  'what should a joinery and carpentry scope of work include',
  'what do I need to tell you about an electrical LV panel to get a quote',
  // licence and registration
  'what trade licence does a supplier need to register on this platform',
  'does a supplier need to be VAT registered to work with you',
  'how does a supplier get verified before receiving RFQs',
  // documents
  'what documents does a supplier need for verification',
  'can I upload a drawing instead of writing the specification out',
  'what happens to my trade licence document after I upload it',
  // how quoting and comparison works
  'how are quotes from different suppliers compared',
  'what does the reveal fee cost and when do I pay it',
  'how many suppliers will quote on my request',
  'why can I not see the supplier name before I pay',
  // coverage and commercial terms
  'what does an emirate coverage limit mean for a supplier',
  'does a Dubai supplier cover Abu Dhabi as well',
  'what is your refund policy if the supplier does not respond',
];

// NEGATIVE CONTROLS. Pure gibberish with no lexeme anywhere in 2.7m rows. If either of these is
// answered, the floor is not doing its job and every PASS above is worthless.
const NONSENSE = [
  'zorblax quantum flibbertigibbet moonbeam turnip parade',
  'wugglethorpe brindlequax vempaloo snorfitude',
];

console.log('-- POSITIVE CONTROL: the corpora hold what the widening claims --');
const ctl = await one(`select
  (select count(*) from sales_knowledge) sales_knowledge,
  (select count(*) from ops_knowledge) ops_knowledge,
  (select count(*) from kb_chunks) kb_chunks,
  (select count(*) from kb_chunks where embedding_gte is not null) kb_chunks_embedded,
  (select count(*) from agent_knowledge) agent_knowledge,
  (select count(*) from agent_knowledge where agent_key like 'cat:%') agent_knowledge_cat,
  (select count(*) from support_knowledge) support_knowledge,
  (select count(*) from category_specs) category_specs,
  (select count(*) from category_quote_specs) category_quote_specs`);
console.table([ctl]);
const idx = await one(`select count(*) n from pg_indexes
  where schemaname='public' and indexname='agent_knowledge_search_idx'`);
console.log('agent_knowledge lexical index present:', Number(idx.n) === 1);

console.log('\n-- 18 REALISTIC PORTAL QUESTIONS --');
const rows = [];
for (const q of QUESTIONS) {
  const { j, ms } = await ask(q);
  const recs = j?.answered ? (await one(
    `select string_agg(distinct split_part(c, ':', 1), ',') corp from sales_decision_log,
       lateral unnest(cited) c where action='assist' order by 1 limit 1`)) : null;
  rows.push({
    question: q.slice(0, 58),
    answered: j?.answered === true,
    n_cited: (j?.cited || []).length,
    corpora: (j?.cited || []).map((c) => String(c).split(':')[0]).filter((v, i, a) => a.indexOf(v) === i).join('+'),
    refusal: j?.refusal || '',
    task: j?.task_id ?? '',
    ms,
  });
  void recs;
}
console.table(rows);

const answered = rows.filter((r) => r.answered).length;
console.log(`\nANSWER RATE FROM RETRIEVAL ALONE: ${answered}/${rows.length} = ${(100 * answered / rows.length).toFixed(1)}%`);

console.log('\n-- PER-CORPUS CITATION COUNTS (this run) --');
const bycorp = await one(`select jsonb_object_agg(corp, n) o from (
  select split_part(c,':',1) corp, count(*) n from sales_decision_log,
    lateral unnest(cited) c
   where action='assist' and created_at > now() - interval '20 minutes'
   group by 1) x`);
console.log(bycorp?.o || '(none)');

console.log('\n-- SIMILARITY / RANK DISTRIBUTION OF CITED ROWS (this run) --');
console.table((await sql(`select c->>'corpus' corpus, c->>'route' route, count(*) n,
    round(min((c->>'similarity')::numeric),4) min_sim, round(max((c->>'similarity')::numeric),4) max_sim,
    round(min((c->>'lexical_rank')::numeric),4) min_rank, round(max((c->>'lexical_rank')::numeric),4) max_rank
  from sales_decision_log, lateral jsonb_array_elements(candidates) c
 where action='assist' and created_at > now() - interval '20 minutes' and (c->>'cited')::boolean
 group by 1,2 order by 3 desc`)).rows);

console.log('\n-- NEGATIVE CONTROL: nonsense must still fall through --');
let floorOk = true;
for (const n of NONSENSE) {
  const { j } = await ask(n);
  const ok = j?.answered === false && (j?.cited || []).length === 0;
  floorOk = floorOk && ok;
  console.log(`${ok ? 'PASS' : 'FAIL'}  "${n.slice(0, 40)}..."  answered=${j?.answered} refusal=${j?.refusal} task=${j?.task_id}`);
  console.log(`      reply: ${String(j?.reply || '').slice(0, 200)}`);
}

console.log('\n-- THE FALLBACK IS AN ACTION: tasks and gap records it opened --');
console.table((await sql(`select g.id, left(g.question, 46) question, g.asks, g.refusal, g.nearest_corpus,
    g.best_similarity, g.task_id, t.status task_status, t.assigned_agent, t.priority
  from sales_knowledge_gap g left join org_tasks t on t.id = g.task_id
  order by g.id desc limit 12`)).rows);

console.log('\n-- THE MODEL HOLD, restated so the answer rate is not read as capability --');
console.table((await sql(`select count(*) routes, min(open_until) held_until from llm_route_health
  where open_until > now()`)).rows);

console.log(`\nFLOOR INTACT: ${floorOk}`);
process.exit(floorOk ? 0 : 1);
