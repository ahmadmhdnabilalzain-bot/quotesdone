// THE INTAKE PATH IN ARABIC, AND THE KNOWLEDGE THAT REACHES IT.
//
// Two things this pins, both of which were true and invisible until 6 Aug 2026:
//
// 1. An Arabic request could not be classified AT ALL. inquiry_intake's detectCat matches a
//    hardcoded English keyword map, so Arabic matched nothing, category stayed null, and that
//    customer got no checklist, no category knowledge and no specialist - while 4,212 bilingual
//    aliases sat in kb_operational_alias with zero code references anywhere.
//
// 2. The category knowledge could not be reached. The FIELD EXPERTISE lookup built its key as
//    'cat:' + a LEGACY slug ('cat:glass'), while agent_knowledge is keyed by CATALOGUE slug
//    ('cat:aluminium-and-glass-suppliers'). The overlap is exactly zero, so 53 of 56 categories
//    silently got no expertise - and a missing prompt section reads exactly like a category that
//    has no knowledge yet.
//
// Neither failed loudly. Both are asserted here on the ROW and on the FUNCTION's own answer, never
// on ok:true.
//
//   node scripts/staging/verify_intake_routing.mjs
// REHOMED 15 AUG 2026. This resolved 'pglpqrhvozwepymcuunn' — a project deleted that morning — so
// it had stopped pinning the two live defects it was written for and was failing on a management
// API 400 instead. The target now comes from demo_factory, which is the one place that decides it,
// and the fixture writes go through the QD_FIXTURES door in qd_guard.mjs.
import { withRun, makeCustomer, REF } from '../lib/demo_factory.mjs';
import { mgmtRead } from '../lib/qd_guard.mjs';
const checks = [];
const ok = (name, pass, detail) => {
  checks.push({ name, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(58)} ${detail}`);
};

const AR_ALUMINIUM = 'نحتاج توريد وتركيب نوافذ ألمنيوم لفيلا في دبي، حوالي 25 نافذة';

await withRun(async (run) => {
  // ---- the router itself, in both languages -----------------------------------------------------
  const ar = (await mgmtRead(REF, `select public.fn_kb_route_decide(${JSON.stringify(AR_ALUMINIUM).replace(/"/g, "'")})::text d`))[0];
  const arD = JSON.parse(ar.d);
  ok('the router resolves Arabic free text to a catalogue category',
    arD.catalog_num === 19 && Number(arD.confidence) >= 0.9,
    `catalog_num=${arD.catalog_num} "${arD.candidates?.[0]?.live_name}" confidence=${arD.confidence} via ${arD.candidates?.[0]?.matched_aliases?.[0]?.lang} alias`);

  const amb = JSON.parse((await mgmtRead(REF,
    `select public.fn_kb_route_decide('نحتاج صيانة تكييف مركزي للمبنى')::text d`))[0].d);
  ok('two tied routes produce a written question, not a guess',
    amb.action === 'ask_clarifying_question' && !!amb.clarification && !amb.catalog_num,
    `action=${amb.action} catalog_num=${amb.catalog_num} q="${String(amb.clarification || '').slice(0, 62)}…"`);

  // ---- the reverse map has to be deterministic --------------------------------------------------
  const rev = (await mgmtRead(REF, `
    select public.fn_intake_slug_for_catalog('aluminium-and-glass-suppliers') a,
           public.fn_intake_slug_for_catalog('flooring-suppliers') f,
           public.fn_intake_slug_for_catalog('mep-suppliers-electromechanical-suppliers') m`))[0];
  ok('a catalogue category maps back to ONE intake slug, base trade first',
    rev.a === 'aluminium' && rev.f === 'flooring' && rev.m === 'mep',
    `aluminium-and-glass→${rev.a}, flooring-suppliers→${rev.f} (over carpets/tiling/marble-granite/epoxy-flooring), mep→${rev.m}`);

  // ---- the knowledge is reachable from the vocabulary intake actually assigns --------------------
  const reach = (await mgmtRead(REF, `
    with cs as (select distinct category slug from public.category_specs)
    select count(*)::int total,
           count(*) filter (where (select count(*) from public.fn_category_knowledge(cs.slug))>0)::int reaching,
           (select count(*) from public.fn_category_knowledge('glass'))::int glass
      from cs`))[0];
  ok('the intake vocabulary reaches the catalogue knowledge base',
    reach.reaching >= 51 && reach.glass > 0,
    `${reach.reaching}/${reach.total} intake slugs resolve; the spec's worked example 'glass' returns ${reach.glass} module(s)`);

  // ---- end to end through the DEPLOYED function --------------------------------------------------
  const cust = await makeCustomer(run);
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/inquiry_intake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + cust.jwt },
    body: JSON.stringify({ text: AR_ALUMINIUM }),
  });
  const j = await r.json().catch(() => ({}));
  ok('the deployed intake accepts an Arabic request', r.status === 200 && !!j.intake_id,
    `HTTP ${r.status} intake_id=${j.intake_id ? 'yes' : 'no'} category=${j.category ?? 'null'}`);

  // THE ASSERTION THAT MATTERS IS ON THE ROW, not the response: the category is what dispatch and
  // the checklist read, and before this change an Arabic request left it null forever.
  const row = (await mgmtRead(REF,
    `select category from public.inquiry_intake
      where id=${JSON.stringify(String(j.intake_id)).replace(/"/g, "'")}`))[0] || {};
  ok('an Arabic request is CLASSIFIED, not filed as general',
    !!row.category && row.category !== 'general',
    `inquiry_intake.category=${row.category ?? 'null'} (English-only detectCat left this null before 6 Aug 2026)`);

  // THE ORDERED INTERVIEW. category_specs.fields is a flat list with a required flag and no
  // sequence; the corpus carries 16,588 questions with an explicit ask-order and a supplier-facing
  // key, and had exactly one reader in the whole repo — its own importer.
  const q = await mgmtRead(REF, `
    select field_key, ask_order, mandatory, left(question, 40) q
      from public.fn_category_questions('glass') order by ask_order`);
  ok('the category has an ORDERED qualification sequence, not a flat list',
    q.length >= 10 && Number(q[0].ask_order) < Number(q[q.length - 1].ask_order),
    `${q.length} question(s), ask_order ${q[0]?.ask_order}→${q[q.length - 1]?.ask_order}, first=[${q[0]?.field_key}]`);

  // The spec's own worked example (Agent 19, Aluminium & Glass) lists what to collect. Assert the
  // sequence actually covers it rather than trusting that a large row count means good coverage.
  const keys = new Set(q.map((r) => String(r.field_key)));
  const want = ['quantity-unit', 'area-dimensions', 'scope-mode', 'installation-access', 'required-date', 'project-emirate'];
  const have = want.filter((w) => keys.has(w));
  ok("the sequence covers the spec's Agent 19 collect-list",
    have.length >= 5, `${have.length}/${want.length} present: ${have.join(', ')}`);

  const qAr = await mgmtRead(REF, `select question from public.fn_category_questions('glass','ar') limit 3`);
  ok('the same sequence is served in Arabic',
    qAr.length > 0 && /[؀-ۿ]/.test(String(qAr[0].question)),
    `first Arabic question: "${String(qAr[0]?.question || '').slice(0, 46)}…"`);

  const kn = (await mgmtRead(REF,
    `select count(*)::int n from public.fn_category_knowledge(${JSON.stringify(String(row.category || 'general')).replace(/"/g, "'")})`))[0];
  ok('that classification reaches real category knowledge',
    Number(kn.n) > 0,
    `fn_category_knowledge('${row.category}') → ${kn.n} module(s) available to the specialist`);
});

const pass = checks.filter((c) => c.pass).length;
console.log(`\nINTAKE ROUTING ${pass}/${checks.length} on ${REF}`);
process.exitCode = pass === checks.length ? 0 : 1;
