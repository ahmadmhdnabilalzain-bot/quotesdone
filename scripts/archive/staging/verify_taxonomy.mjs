// verify_taxonomy.mjs — the operational router, and the crosswalk that has to hold for it to matter.
//
// Until session 9 staging held NONE of fn_kb_route_decide's inputs: kb_operational_alias was 0 rows
// against production's 4,212 and kb_operational_route_map 0 against 426, so the router returned
// top_score 0 for every string ever typed at it. That is the worst shape a data gap can take - a
// confident "I could not understand you" rather than an error.
//
// Loading them was blocked by a real bug in sync_staging_reference.mjs's copyTable: it paginated
// with `order by 1`, and kb_operational_alias's first column (catalog_num) is massively non-unique
// against a primary key of (catalog_num, language, alias). LIMIT/OFFSET over a partial order has no
// stable row order, so batches both duplicated and dropped rows; the duplicate violated the primary
// key, the INSERT threw, and the old `if (stageRows) skip` guard then made the half-loaded table
// skip forever. Both are fixed; this asserts the result.
//
// Everything here is SQL. No model calls, nothing created, nothing to tear down.
//
//     node scripts/archive/staging/verify_taxonomy.mjs
import { mgmtRead, PROD_REF } from '../../lib/qd_guard.mjs';
import { REF } from '../../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(46)} ${detail}`);
};
const one = async (ref, sql) => (await mgmtRead(ref, sql))[0];

// ---- 1. the router's inputs are present, and complete ------------------------------------------
for (const t of ['kb_operational_route', 'kb_operational_alias', 'kb_operational_route_map']) {
  const p = Number((await one(PROD_REF, `select count(*)::int n from public.${t}`)).n);
  const s = Number((await one(REF, `select count(*)::int n from public.${t}`)).n);
  step(`${t} matches production`, s === p && p > 0, `staging ${s}, production ${p}`);
}

// A duplicate-or-drop pagination bug does not always change the COUNT - it can drop one row and
// duplicate another. Compare the actual key set, not its size.
const digest = async (ref) => (await one(ref,
  `select md5(string_agg(catalog_num || '|' || language || '|' || alias, E'\\n'
       order by catalog_num, language, alias)) h
     from public.kb_operational_alias`)).h;
const [ph, sh] = [await digest(PROD_REF), await digest(REF)];
step('kb_operational_alias is row-for-row identical', !!ph && ph === sh,
  ph === sh ? `md5 ${String(ph).slice(0, 12)}… over all 4,212 keys`
            : `production ${String(ph).slice(0, 12)}… vs staging ${String(sh).slice(0, 12)}…`);

// ---- 2. the router actually routes --------------------------------------------------------------
const decide = async (txt) => (await one(REF,
  `select public.fn_kb_route_decide('${txt.replace(/'/g, "''")}') d`)).d;

const fire = await decide('supply and install fire alarm system with smoke detectors');
step('English free text routes to a catalogue entry',
  Number(fire.top_score) > 0 && fire.catalog_num === 13 && Number(fire.confidence) === 1,
  `catalog_num=${fire.catalog_num} "${fire.candidates?.[0]?.live_name}" ` +
  `score=${fire.top_score} confidence=${fire.confidence} action=${fire.action}`);

// The Arabic branch is not a translation of the English one - kb_operational_alias carries its own
// `ar` aliases, and customers.locale exists for exactly this. Worth its own assertion.
const ar = await decide('نحتاج توريد وتركيب نوافذ ألمنيوم لفيلا');
step('Arabic free text routes to a catalogue entry',
  Number(ar.top_score) > 0 && ar.catalog_num === 19
    && (ar.candidates?.[0]?.matched_aliases?.[0]?.lang === 'ar'),
  `catalog_num=${ar.catalog_num} "${ar.candidates?.[0]?.live_name}" ` +
  `matched ar alias "${ar.candidates?.[0]?.matched_aliases?.[0]?.alias}" score=${ar.top_score}`);

// The paired negative. The assertion is on the REASON, not on a row count: "no route" and "no
// suppliers" look identical downstream if you only count.
const none = await decide('zzz nonsense string that matches nothing at all zzz');
step('unroutable text asks rather than guessing',
  Number(none.top_score) === 0 && none.catalog_num === null
    && none.action === 'ask_clarifying_question' && !!none.clarification,
  `top_score=${none.top_score} action=${none.action} reason="${none.reason}"`);

// Ambiguity must also ask, not pick. "aluminium windows" matches the single word "Windows" in two
// different categories at weight 2 apiece.
const amb = await decide('We need aluminium windows supplied and installed for a villa');
step('ambiguous text asks which category, and names both',
  amb.multi_category === true && amb.catalog_num === null
    && (amb.candidates || []).length >= 2 && !!amb.clarification,
  `${(amb.candidates || []).length} candidates at score ${amb.top_score}, ` +
  `action=${amb.action}`);

// ---- 3. the crosswalk: a catalogue route has to reach a matchable trade -------------------------
// fn_match_capability gates on taxonomy_trade.code (25 codes). fn_kb_route_decide returns a
// catalog_num (86 categories). lead_trade_map is the bridge, and if it does not hold, routing
// succeeds and dispatch then finds nobody - for a vocabulary reason that looks like a coverage gap.
const x = await one(REF, `select
  (select count(*) from public.lead_trade_map m
    where m.catalog_slug is not null
      and not exists (select 1 from public.catalog_supplier_categories c where c.slug = m.catalog_slug)) dangling,
  (select coalesce(string_agg(t.code, ','), '') from public.taxonomy_trade t
    where not exists (select 1 from public.lead_trade_map m where m.trade_key = t.code)) unmapped,
  (select coalesce(string_agg(m.trade_key, ','), '') from public.lead_trade_map m
    where m.catalog_slug is null) no_category,
  (select coalesce(string_agg(r.expected_catalog_slug, ','order by r.catalog_num), '')
     from public.kb_operational_route r
    where r.expected_catalog_slug is not null
      and not exists (select 1 from public.catalog_supplier_categories c where c.slug = r.expected_catalog_slug)) route_dangling`);

step('every lead_trade_map slug resolves to a real category',
  Number(x.dangling) === 0, `${x.dangling} dangling catalog_slug value(s)`);

// CLOSED 5 Aug 2026. These three gaps were PINNED here for two sessions as "real and unfixed", and
// the pin was doing real harm: it asserted the gap set had not CHANGED, so the gate stayed green
// while 3 of 25 trades could not be reached from any catalogue route and 4 routes pointed at
// categories that do not exist. A gate that certifies a defect as stable is not a gate.
//
// Two of the three were also mis-described. `elevators` and `signage` were recorded as deliberately
// unmapped because there was "NO CATALOGUE CATEGORY" — but `lifts-and-escalator-suppliers` and
// `signage-and-printing-suppliers` both exist, and so does `paints-and-finishing-materials-suppliers`
// for `wallpaper`. Nothing was undecidable; the rows simply pointed nowhere.
//
// The 4 dangling routes were each the category name slugified WITHOUT its parenthetical, so each
// resolved to exactly one real category by prefix match.
//
// Fixed in BOTH projects by scripts/archive/staging/apply_taxonomy_fix.mjs — this is reference data, and a
// staging-only fix would have turned this gate green while every real customer still hit the gap.
step('every taxonomy_trade code reaches a catalogue category',
  x.unmapped === '' && x.no_category === '',
  x.unmapped === '' && x.no_category === ''
    ? 'all 25 trades resolve through lead_trade_map to a real catalogue category'
    : `absent from lead_trade_map: [${x.unmapped}]; mapped but catalog_slug null: [${x.no_category}]`);

step('no route points at a category that does not exist',
  x.route_dangling === '',
  x.route_dangling === ''
    ? 'every kb_operational_route.expected_catalog_slug resolves'
    : `${x.route_dangling.split(',').filter(Boolean).length} dangling: ${x.route_dangling}`);

const pass = checks.filter((c) => c.ok).length;
console.log(`\nTAXONOMY ${pass}/${checks.length} on ${REF} (zero spend)`);
process.exitCode = pass === checks.length ? 0 : 1;
