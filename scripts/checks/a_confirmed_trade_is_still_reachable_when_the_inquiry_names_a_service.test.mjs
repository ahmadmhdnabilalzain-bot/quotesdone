// A CONFIRMED TRADE IS STILL REACHABLE WHEN THE INQUIRY NAMES A SERVICE
// (23 Sep 2026, sales_engineer, SP-F-01 follow-up).
//
// WHAT THIS CATCHES, AND WHY IT IS NOT THE GATE'S FAULT. fn_match_capability's p_services gate is now
// passed by every matcher that has a brief: when the inquiry names a service, a supplier is a
// candidate only if its CONFIRMED list covers one of them. The gate is the founder's rule. But the
// gate turns a stale capability row into an INVISIBLE loss of a whole trade: the supplier still shows
// the trade on its card, the portal still says it is matchable, and every service-naming inquiry in
// that trade reaches nobody. Measured 23 Sep 2026, the day before the gate deployed: production's one
// confirmed row declared {gypsum, painting} and carried five gypsum.* keys plus the raw Arabic word
// «الدهانات», so painting was about to go from 1 reachable supplier to 0
// (scripts/sql/a_confirmed_service_is_a_taxonomy_key_not_a_word.sql).
//
// TWO PROPERTIES, both read from production, neither of them a style rule:
//
//   1. NO ASYMMETRIC TRADE. A confirmed supplier that has named services for SOME of its trades and
//      none for another trade it also declares. That is provably a defect in the row — the company
//      said it does that trade and named nothing it does in it — and it cannot fire on a supplier who
//      has simply not filled the Services tab yet (that supplier has no keys at all, is uniformly
//      trade-level, and is counted below rather than failed).
//
//   2. NO WORD THAT IS REALLY A KEY. supplier_capabilities.services legitimately holds BOTH stated
//      keys and the supplier's own words (supplier_services.ts splitServices) — a word the rewriter
//      could not name is kept exactly as typed and reaches the sales engineer. But a word an ACTIVE
//      service alias does name is not an own word; it is a service that was never rewritten, it
//      contributes nothing to matching, and it sits in the "to map" queue forever. The alias test
//      here is the SAME one fn_norm_trades applies — fn_ar_norm, word-START anchored, Arabic
//      proclitics and ال allowed — so it agrees with the TS reader the runtime uses.
//
//   node --test scripts/checks/a_confirmed_trade_is_still_reachable_when_the_inquiry_names_a_service.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('production: no confirmed supplier declares a trade it has named no service in', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`
    with cap as (
      select sc.supplier_id, l.company_name, sc.trades,
             public.fn_services_effective(sc.services, sc.trades, sc.services_removed) as eff
        from public.supplier_capabilities sc
        join public.leads l on l.id = sc.supplier_id
       where sc.confirmed_at is not null
    )
    select c.supplier_id, c.company_name, t as trade, cardinality(c.eff) as keys_in_total
      from cap c, unnest(coalesce(c.trades, '{}'::text[])) t
     where cardinality(c.eff) > 0
       and not exists (select 1 from unnest(c.eff) k where split_part(k, '.', 1) = t)
     order by 1, 3`);
  const bad = rows.map((r) => `${r.supplier_id} ${r.company_name}: trade ${r.trade} has 0 of its ${r.keys_in_total} service keys`);
  assert.deepEqual(bad, [], 'a service-naming inquiry in this trade reaches nobody, while the trade still shows as declared');

  // A zero above must be readable: say how many confirmed rows there are and how many have no keys at
  // all (uniformly trade-level, a different and expected state — not a silent failure of this check).
  const [n] = await sql(`select count(*)::int as confirmed,
                                count(*) filter (where cardinality(public.fn_services_effective(services, trades, services_removed)) = 0)::int as no_keys
                           from public.supplier_capabilities where confirmed_at is not null`);
  console.log(`${n.confirmed} confirmed capability row(s); ${n.no_keys} with no service key at all (trade-level only)`);
  assert.ok(n.confirmed > 0, 'no confirmed capability row exists, so this check measured nothing');
});

test('production: no confirmed capability stores a word an active service alias already names', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`
    with known as (select trade_code || '.' || code as key from public.taxonomy_trade_service where active),
    extras as (
      select sc.supplier_id, w as word
        from public.supplier_capabilities sc, unnest(coalesce(sc.services, '{}'::text[])) w
       where sc.confirmed_at is not null and w not in (select key from known)
    )
    select distinct e.supplier_id, e.word, s.trade_code || '.' || s.code as named
      from extras e
      join public.taxonomy_trade_service s on s.active
      cross join lateral unnest(s.aliases) a
     where length(public.fn_ar_norm(a)) >= 3
       and public.fn_ar_norm(e.word) ~* ('\\m' || case
             when public.fn_ar_norm(a) ~ '^[ء-ي]'
               then '(?:[وفبلك]?ال|[وف]?لل|[وفبلك])?'
                    || replace(replace(regexp_replace(public.fn_ar_norm(a), '([.*+?^$\{\}()|\\[\\]\\\\])', '\\\\\\1', 'g'), ' ', ' (?:ال)?'), ' (?:ال)?و', ' و(?:ال)?')
             else regexp_replace(public.fn_ar_norm(a), '([.*+?^$\{\}()|\\[\\]\\\\])', '\\\\\\1', 'g')
           end)
     order by 1, 2`);
  const bad = rows.map((r) => `${r.supplier_id}: "${r.word}" is ${r.named}, stored as free text`);
  assert.deepEqual(bad, [], 'these words name a real service, so they should be keys — as free text they match nothing');
});
