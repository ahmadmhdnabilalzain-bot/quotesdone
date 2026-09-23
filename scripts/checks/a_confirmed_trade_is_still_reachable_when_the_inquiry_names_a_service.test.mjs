// A CONFIRMED TRADE IS STILL REACHABLE WHEN THE INQUIRY NAMES A SERVICE
// (23 Sep 2026, sales_engineer, SP-F-01 follow-up; rewritten 23 Sep after the re-review).
//
// WHAT THIS CATCHES. fn_match_capability's p_services gate is now passed by every matcher that has a
// brief: when the inquiry names a service, the supplier's confirmed service list is consulted. The
// gate is the founder's rule. But read over the supplier's WHOLE list it turned silence into a denial:
// a supplier that declares a trade and has named no service IN that trade was dropped from every
// service-naming inquiry in it, so the trade reached NOBODY while every card still showed it — an
// invisible loss of a whole trade. Measured on production 23 Sep 2026 against the live function, the
// day the gate went in: doors 4 reachable at trade level -> 0, painting 1 -> 0.
//
// THE PROPERTY, and it is the one the founder asked for in plain words: for every trade some confirmed
// supplier declares, naming that trade's services in an inquiry must not reach FEWER suppliers than
// naming only the trade. Not "fewer by a defensible amount" — not fewer at all. The service gate is
// there to prefer a supplier that named the service, never to empty the trade. This is measured by
// calling the live fn_match_capability twice per trade: once trade-level, once with every active
// service of that trade as p_services (the union of every one-service inquiry that trade can carry),
// and comparing the supplier sets. scripts/sql/the_service_gate_never_empties_a_trade.sql is the fix;
// before it, this check FAILS on doors and painting.
//
// The second test is a data property and stands on its own: supplier_capabilities.services legitimately
// holds BOTH stated keys and the supplier's own words (supplier_services.ts splitServices) — a word the
// rewriter could not name is kept exactly as typed and reaches the sales engineer as a proposal. But a
// word an ACTIVE service alias does name is not an own word; it is a service that was never rewritten,
// it contributes nothing to matching, and it sits in the "to map" queue forever. The alias test here is
// the SAME one fn_norm_trades applies — fn_ar_norm, word-START anchored, Arabic proclitics and ال
// allowed — so it agrees with the TS reader the runtime uses. A bare word NO alias names (production
// carries "Doors", an aluminium-interview checklist option) is correctly left alone here: mapping it to
// one of doors.wooden_doors / fire_doors / shutters / ironmongery / automatic_doors would be a
// nearest-neighbour guess, and exact match or none cuts both ways.
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

test('production: naming a trade\'s services never reaches fewer suppliers than naming the trade', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  // p_limit is deliberately far above any real candidate set: a truncated list would make a trade look
  // equal when it is not. p_need stays the default 'executes', the value every production matcher uses.
  const rows = await sql(`
    with declared as (
      select distinct t as trade
        from public.supplier_capabilities sc, unnest(coalesce(sc.trades, '{}'::text[])) t
       where sc.confirmed_at is not null
    ),
    keys as (
      select d.trade,
             array(select s.trade_code || '.' || s.code
                     from public.taxonomy_trade_service s
                    where s.active and s.trade_code = d.trade order by 1) as service_keys
        from declared d
    )
    select k.trade, cardinality(k.service_keys) as services_in_taxonomy,
           (select count(*)::int from public.fn_match_capability(array[k.trade], p_limit := 500)) as at_trade_level,
           (select count(*)::int from public.fn_match_capability(array[k.trade], p_limit := 500,
                                                                p_services := k.service_keys)) as naming_services
      from keys k
     order by k.trade`);
  for (const r of rows) {
    console.log(`  ${r.trade.padEnd(18)} taxonomy services ${String(r.services_in_taxonomy).padStart(3)}` +
                `   reachable: trade level ${r.at_trade_level}, naming services ${r.naming_services}`);
  }
  assert.ok(rows.length > 0, 'no confirmed supplier declares any trade, so this check measured nothing');
  const lost = rows.filter((r) => r.naming_services < r.at_trade_level)
    .map((r) => `${r.trade}: ${r.at_trade_level} reachable at trade level, ${r.naming_services} when the inquiry names a service`);
  assert.deepEqual(lost, [], 'the service gate removed suppliers a trade-level inquiry reaches, so these trades lose requests silently');
});

// THE MULTI-TRADE CASE, WHICH IS THE ONLY CASE PRODUCTION HAS (re-review finding A, 23 Sep 2026). The
// test above measures one trade at a time, and a gate that reads the named trades as one UNION passes
// it while still emptying a trade: a supplier silent on doors but spoken-on for aluminium looks
// spoken-on to a union, so {doors.fire_doors, aluminium.tensile_structures} reached nobody in doors.
// Every real inquiry is multi-trade — sales_engineer derives ONE key set from one brief across all of
// the inquiry's trades, and the three backfilled rows carry keys across three, two and two trades.
//
// The property is per supplier, not per count, because a lower count can be the gate working: a
// supplier that has named services in EVERY named trade it declares and holds none of the named ones
// SHOULD be dropped. So this asserts only the suppliers the relaxation is about — those a trade-level
// inquiry reaches AND which have named nothing in at least one of the named trades they declare.
//
// The services asked for are deliberately ones NO confirmed supplier holds. Asking for services
// somebody holds would let a union-reading gate pass on that hit and hide the defect.
test('production: a two-trade inquiry still reaches a supplier silent in one of those trades', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`
    with declared as (
      select distinct t as tr
        from public.supplier_capabilities sc, unnest(coalesce(sc.trades, '{}'::text[])) t
       where sc.confirmed_at is not null
    ),
    unheld as (      -- a service of that trade that no confirmed supplier has named
      select s.trade_code as tr, s.trade_code || '.' || s.code as key
        from public.taxonomy_trade_service s
       where s.active
         and not exists (
           select 1 from public.supplier_capabilities sc
            where sc.confirmed_at is not null
              and (s.trade_code || '.' || s.code) = any(
                    public.fn_services_effective(sc.services, sc.trades, sc.services_removed)))
    ),
    ask as (
      select a.tr as a, b.tr as b,
             array(select u.key from unheld u where u.tr in (a.tr, b.tr) order by 1) as keys
        from declared a join declared b on b.tr > a.tr
    ),
    pair as (select * from ask where cardinality(keys) > 0),
    base as (
      select p.a, p.b, m.supplier_id
        from pair p, public.fn_match_capability(array[p.a, p.b], p_limit := 500) m
    ),
    got as (
      select p.a, p.b, m.supplier_id
        from pair p, public.fn_match_capability(array[p.a, p.b], p_limit := 500, p_services := p.keys) m
    ),
    silent as (      -- of those, the ones that named nothing in one of the two trades they declare
      select b.a, b.b, b.supplier_id
        from base b
        join public.supplier_capabilities sc on sc.supplier_id = b.supplier_id
       where exists (
         select 1 from (values (b.a), (b.b)) v(tr)
          where v.tr = any(coalesce(sc.trades, '{}'::text[]))
            and not exists (
              select 1 from unnest(public.fn_services_effective(sc.services, sc.trades, sc.services_removed)) k
               where split_part(k, '.', 1) = v.tr))
    )
    select p.a, p.b, cardinality(p.keys) as services_asked,
           (select count(*)::int from base b where b.a = p.a and b.b = p.b) as at_trade_level,
           (select count(*)::int from got  g where g.a = p.a and g.b = p.b) as naming_services,
           (select count(*)::int from silent s where s.a = p.a and s.b = p.b) as silent_in_one,
           coalesce((select array_agg(s.supplier_id order by s.supplier_id) from silent s
                      where s.a = p.a and s.b = p.b
                        and not exists (select 1 from got g
                                         where g.a = s.a and g.b = s.b and g.supplier_id = s.supplier_id)), '{}') as lost
      from pair p
     order by p.a, p.b`);
  for (const r of rows) {
    console.log(`  {${r.a}, ${r.b}} asking ${r.services_asked} unheld service(s): trade level ${r.at_trade_level}, ` +
                `naming services ${r.naming_services}, of which silent in one trade ${r.silent_in_one}` +
                (r.lost.length ? `  LOST ${r.lost.join(',')}` : ''));
  }
  assert.ok(rows.length > 0, 'no two declared trades to pair, so this check measured nothing');
  const lost = rows.filter((r) => r.lost.length)
    .map((r) => `{${r.a}, ${r.b}}: supplier(s) ${r.lost.join(', ')} are reached at trade level and named nothing in one of these trades, yet the service gate dropped them`);
  assert.deepEqual(lost, [], 'the gate read the named trades as one union, so silence in one trade was covered by having spoken in another');
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
