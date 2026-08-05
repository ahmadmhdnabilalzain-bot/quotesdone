// apply_taxonomy_fix.mjs — close the three taxonomy gaps verify_taxonomy has been PINNING.
//
// These are PRODUCTION REFERENCE DATA, mirrored byte-identically into staging (lead_trade_map is
// 24 rows with the same md5 in both projects), so a staging-only patch is provably invisible: the
// gate would go green while every real customer still hit the gap. Both projects, or neither.
//
// Applied DIRECTLY, never as a migration — verify_phase1.mjs asserts the 712-migration ledger
// parity between the two projects and a migration file breaks it.
//
// THE THREE GAPS, and why the brief was wrong about two of them:
//
//   (a) `wallpaper` is the one taxonomy_trade code with no lead_trade_map row at all.
//
//   (b) `elevators` and `signage` were recorded as "mapped but deliberately unmapped — NO CATALOGUE
//       CATEGORY". Measured 5 Aug 2026, that is false: `lifts-and-escalator-suppliers` and
//       `signage-and-printing-suppliers` both EXIST as catalog_supplier_categories. Nothing was
//       undecidable; the rows simply pointed nowhere. Same for wallpaper, whose home is
//       `paints-and-finishing-materials-suppliers`.
//
//   (c) 4 kb_operational_route.expected_catalog_slug values are the category name slugified WITHOUT
//       its parenthetical, so each is one unambiguous suffix away from a real category. Confirmed
//       by matching each against `slug LIKE <dangling>||'%'` — every one resolves to exactly one row.
//
// Staging is written through qd_guard's mgmtWrite, which refuses production by construction. The
// production statements are PRINTED for a human (or the same operator) to apply through the
// management API — the same split scripts/verify_prod_readiness.mjs uses.
//
//     node scripts/staging/apply_taxonomy_fix.mjs
import { mgmtRead, mgmtWrite, PROD_REF } from './qd_guard.mjs';
import { REF } from './demo_factory.mjs';

// trade code -> the catalogue category it belongs in. Every slug verified to exist in production.
const TRADES = [
  ['wallpaper', 'paints-and-finishing-materials-suppliers'],
  ['elevators', 'lifts-and-escalator-suppliers'],
  ['signage', 'signage-and-printing-suppliers'],
];

const STATEMENTS = [
  // (a)+(b) — upsert so it is idempotent whether the row is absent or present-with-null.
  ...TRADES.map(([code, slug]) => `
    insert into public.lead_trade_map (trade_key, catalog_slug)
    values ('${code}', '${slug}')
       on conflict (trade_key) do update set catalog_slug = excluded.catalog_slug`),
  // (c) — append the missing parenthetical suffix, matched by prefix against the real category.
  `update public.kb_operational_route r
      set expected_catalog_slug = (select c.slug from public.catalog_supplier_categories c
                                    where c.slug like r.expected_catalog_slug || '%' limit 1)
    where r.expected_catalog_slug is not null
      and not exists (select 1 from public.catalog_supplier_categories c
                       where c.slug = r.expected_catalog_slug)
      and exists (select 1 from public.catalog_supplier_categories c
                   where c.slug like r.expected_catalog_slug || '%')`,
];

const audit = (ref) => mgmtRead(ref, `
  select (select count(*) from public.taxonomy_trade t
           where not exists (select 1 from public.lead_trade_map m
                              where m.trade_key = t.code and m.catalog_slug is not null))::int as unreachable_trades,
         (select count(*) from public.kb_operational_route r
           where r.expected_catalog_slug is not null
             and not exists (select 1 from public.catalog_supplier_categories c
                              where c.slug = r.expected_catalog_slug))::int as dangling_routes,
         (select count(*) from public.lead_trade_map m
           where m.catalog_slug is not null
             and not exists (select 1 from public.catalog_supplier_categories c
                              where c.slug = m.catalog_slug))::int as broken_map_slugs`);

const before = (await audit(REF))[0];
console.log(`staging BEFORE : unreachable trades ${before.unreachable_trades}, dangling routes ${before.dangling_routes}, broken map slugs ${before.broken_map_slugs}`);

for (const sql of STATEMENTS) await mgmtWrite(REF, sql, 'taxonomy fix');

const after = (await audit(REF))[0];
console.log(`staging AFTER  : unreachable trades ${after.unreachable_trades}, dangling routes ${after.dangling_routes}, broken map slugs ${after.broken_map_slugs}`);

const prod = (await audit(PROD_REF))[0];
console.log(`\nproduction     : unreachable trades ${prod.unreachable_trades}, dangling routes ${prod.dangling_routes}, broken map slugs ${prod.broken_map_slugs}`);
if (prod.unreachable_trades || prod.dangling_routes) {
  console.log('\nApply the SAME statements to production — this is reference data and a staging-only');
  console.log('fix is invisible to every real customer:\n');
  for (const sql of STATEMENTS) console.log(sql.trim().replace(/\n\s+/g, '\n  ') + ';\n');
}
