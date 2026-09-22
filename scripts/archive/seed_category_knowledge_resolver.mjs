// fn_category_knowledge — the first reader the category knowledge base ever had.
//
// Measured 6 Aug 2026: 1,558 of 1,869 agent_knowledge rows are keyed 'cat:<catalogue-slug>', and
// 84 of those keys match a catalog_supplier_categories slug exactly — i.e. every one of the spec's
// 84 UAE categories carries its 8 knowledge modules. The live intake assigns one of 56 LEGACY
// category_specs slugs whose overlap with the catalogue is EXACTLY ZERO, so at inquiry time the
// specialist got its checklist and none of its Industry / Technical / UAE / Supplier knowledge.
// The spec's own worked example (Agent 19, Aluminium & Glass) was two disconnected halves.
//
// lead_trade_map is the bridge and this function is the first thing that walks it at read time.
// It accepts EITHER vocabulary, so a caller holding a legacy slug or a catalogue slug both work
// and no caller has to know which one it is holding.
//
// Measured before: 3 of 56 intake slugs could reach any module.
// Measured after:  51 of 56, exposing 767 modules.
// The 5 that cannot are correct: 'general' and 'general-services-other' are the catch-alls the
// intake falls back to when it could NOT classify (deliberately unmapped — see
// seed_category_bridge.mjs), and 'acrylic', 'signage' and 'elevators' resolve to the only two
// catalogue categories the corpus never covered: signage-and-printing-suppliers and
// lifts-and-escalator-suppliers. That is a CONTENT gap, not a wiring gap, and it should be closed
// by the knowledge generator that produced the other 84 rather than by hand.
//
// Created on BOTH projects: verify_phase1 asserts routine-count parity, so a function added to one
// project only turns that gate red.
//
//   node scripts/seed_category_knowledge_resolver.mjs <staging-ref>
//   node scripts/seed_category_knowledge_resolver.mjs --print-sql
import { mgmtRead, mgmtWrite, resolveStagingRef } from './staging/qd_guard.mjs';

export const SQL = `create or replace function public.fn_category_knowledge(p_category text)
returns table(catalog_slug text, topic text, content text, priority integer, layer text)
language sql stable security definer set search_path = public as $fn$
  with resolved as (
    select coalesce(
      (select c.slug from public.catalog_supplier_categories c where c.slug = p_category),
      (select m.catalog_slug from public.lead_trade_map m
         join public.catalog_supplier_categories c2 on c2.slug = m.catalog_slug
        where m.trade_key = p_category)
    ) as slug
  )
  select r.slug, k.topic, k.content, k.priority, k.layer
    from resolved r
    join public.agent_knowledge k on k.agent_key = 'cat:' || r.slug
   where r.slug is not null
   order by k.priority desc nulls last, k.topic;
$fn$;

grant execute on function public.fn_category_knowledge(text) to postgres, service_role;`;

if (process.argv.includes('--print-sql')) { console.log(SQL); process.exit(0); }

const REF = resolveStagingRef(process.argv[2]);
await mgmtWrite(REF, SQL, 'create fn_category_knowledge');

const m = (await mgmtRead(REF, `
  with cs as (select distinct category slug from public.category_specs)
  select count(*)::int intake_slugs,
         count(*) filter (where (select count(*) from public.fn_category_knowledge(cs.slug)) > 0)::int reaching,
         coalesce(sum((select count(*) from public.fn_category_knowledge(cs.slug))),0)::int modules
    from cs`))[0];

console.log(`fn_category_knowledge created on ${REF}`);
console.log(`intake slugs reaching knowledge: ${m.reaching}/${m.intake_slugs}, exposing ${m.modules} module(s)`);
if (m.modules === 0) {
  console.log(`NOTE: 0 modules here means agent_knowledge is empty on this project, not that the`);
  console.log(`      resolver is broken. The corpus lives in production only — see requirement 46,`);
  console.log(`      knowledge-import/import_corpus.py could historically only write to production.`);
}
