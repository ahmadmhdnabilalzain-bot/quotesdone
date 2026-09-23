// THE CORPUS THE MULTILINGUAL MODEL'S VOCABULARY IS TRIMMED TO. Seat: it_engineer. 24 Sep 2026.
// Writes one line per knowledge row (every source knowledge_vector_ml embeds, plus the verified packs) to the
// file named by --out, READ-ONLY against production. scripts/kb/trim_ml_model.py reads it; see that file.
//   node scripts/kb/trim_ml_model_corpus.mjs --out=corpus.txt
import { sql } from '../lib/db.mjs';
import { createWriteStream, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const out = createWriteStream(process.argv.find((a) => a.startsWith('--out='))?.slice(6) ?? 'corpus.txt');
const small = `select left(coalesce(title,'')||' '||coalesce(body,''),1500) t from (
  select null::text title, m.situation body from public.seat_case_memory m
  union all select c.title, c.body from public.ceo_knowledge c
  union all select s.title, s.body from public.support_knowledge s
  union all select a.title, a.content from public.accountant_knowledge a
  union all select i.title, i.content from public.it_engineer_knowledge i
  union all select k.title, k.content from public.marketing_knowledge k
  union all select s.title, s.content from public.sales_knowledge s
  union all select f.question, f.answer from public.company_faq f
  union all select g.topic, g.content from public.agent_knowledge g
  union all select o.title, o.content from public.ops_knowledge o
  union all select r.question, r.finding from public.reasoning_knowledge_candidate r) x`;
let n = 0;
for (const r of await sql(small, { readOnly: true })) { out.write(r.t.replace(/\s+/g, ' ') + '\n'); n++; }
console.log('small', n);
let last = '00000000-0000-0000-0000-000000000000';
for (;;) {
  const rows = await sql(`select id::text id, left(coalesce(title,'')||' '||coalesce(content,''),1300) t from public.kb_chunks where id::text > '${last}' order by id::text limit 8000`, { readOnly: true });
  if (!rows.length) break;
  for (const r of rows) out.write(r.t.replace(/\s+/g, ' ') + '\n');
  n += rows.length; last = rows.at(-1).id; process.stdout.write(n + ' ');
}
for (const d of ['packs', 'seats']) { const p = fileURLToPath(new URL('../../knowledge/' + d, import.meta.url)); try { for (const f of readdirSync(p)) if (f.endsWith('.json')) { const j = JSON.parse(readFileSync(p + '/' + f, 'utf8')); for (const e of j.entries ?? []) out.write([e.topic, e.body_en, e.body_ar, ...(e.eval ?? []).flatMap?.((q) => [q.q_en, q.q_ar, q.question_en, q.question_ar]) ?? []].filter(Boolean).join(' ').replace(/\s+/g, ' ') + '\n'); } } catch (e) { console.log(d, e.message); } }
out.end(); console.log('\ntotal', n);
