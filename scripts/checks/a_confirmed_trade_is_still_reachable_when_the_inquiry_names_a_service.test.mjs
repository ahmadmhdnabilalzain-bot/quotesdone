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

// MEASURED NOTHING IS NOT A DEFECT (re-review finding D, 23 Sep 2026). Every confirmed capability in
// production is a ZZ DEMO rehearsal row, and the set was watched going 4 -> 7 -> 1 in 75 minutes and
// watched emptying. A bare assert then turns "the fixture retired" into a red check, and a guard that
// goes red because a fixture retired is a guard that gets ignored. So an empty measurement takes the
// same road the missing credential above takes: a NOT_VERIFIED_ line and a skip, which is
// distinguishable at a glance from a failure. The PREDICATE is not left unmeasured when the data
// cannot supply a case — it is driven from a read-only VALUES list of synthetic candidate rows, which
// writes nothing and seeds no fixture. See the header of
// scripts/sql/the_service_gate_never_empties_a_trade.sql for that measurement.
const nothing = (t, marker, why) => { console.log(marker); return t.skip(why); };

test('production: naming a trade\'s services never reaches fewer suppliers than naming the trade', { skip: SKIP }, async (t) => {
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
  if (!rows.length) return nothing(t, 'NOT_VERIFIED_NO_CONFIRMED_CAPABILITY_ROW',
    'production holds no confirmed capability row, so there is no trade to measure');
  const lost = rows.filter((r) => r.naming_services < r.at_trade_level)
    .map((r) => `${r.trade}: ${r.at_trade_level} reachable at trade level, ${r.naming_services} when the inquiry names a service`);
  assert.deepEqual(lost, [], 'the service gate removed suppliers a trade-level inquiry reaches, so these trades lose requests silently');
});

// THE MULTI-TRADE CASE, WHICH IS THE ONLY CASE PRODUCTION HAS (re-review findings A and C, 23 Sep
// 2026). The test above measures one trade at a time, and two different wrong readings of the gate pass
// it while still emptying a trade:
//
//   A. THE NAMED TRADES READ AS ONE UNION. A supplier silent on doors but spoken-on for aluminium looks
//      spoken-on to a union, so a {doors.*, aluminium.*} inquiry reached nobody in doors.
//   C. ONLY THE TRADES THE SUPPLIER DECLARES CONSULTED. When the services named fall in trades the
//      supplier does NOT declare, it was never asked anything — and a reading that looks only for a
//      declared-and-silent trade finds none and excludes it. That is a supplier which has never opened
//      the Services tab, dropped on an inquiry it matches by trade.
//
// Every real inquiry is multi-trade, and C's shape is ordinary rather than a corner: detectTrades and
// serviceKeysOf read the same brief INDEPENDENTLY, so a brief that names two trades and yields keys in
// only one is the normal case. The backfilled rows carry keys across three, two and two trades.
//
// SO THE ASK IS RUN TWO WAYS per ordered pair of declared trades {a, b}: the unheld services of BOTH
// (which is where A shows), and the unheld services of b ONLY (which is where C shows — a supplier
// declaring a alone is then asked about nothing it does). Asking only for services NO confirmed supplier
// holds is deliberate: asking for one somebody holds lets a wrong reading pass on that hit and hide the
// defect. An earlier version of this test asked both trades only, so C's shape could never appear.
//
// THE PROPERTY IS PER SUPPLIER, not per count, because a lower count can be the gate working correctly:
// a supplier that has named services in EVERY named trade it declares and holds none of the named ones
// SHOULD be dropped. So this asserts exactly the suppliers the relaxation is about — those a trade-level
// inquiry reaches and which are trade level for this work, either never asked or silent where asked.
test('production: a multi-trade inquiry still reaches a supplier that is trade level for it', { skip: SKIP }, async (t) => {
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
    -- ONE TRADE NO CONFIRMED SUPPLIER DECLARES. Finding C's shape needs the named trades to be DISJOINT
    -- from the candidate's own trades, and a pair drawn from the declared set cannot guarantee that:
    -- 23 Sep 2026 production held one confirmed matchable row declaring {gypsum, painting}, which
    -- declares BOTH trades of every such pair, so "never asked" was never reached and removing the
    -- fourth arm of the gate left this test green. Pairing a declared trade with an UNDECLARED one makes
    -- the disjointness hold by construction, whatever the fixture set is doing: the trade gate still
    -- admits the candidate through trade a, and nothing it declares is asked about. 40 such trades today.
    outside as (
      select t.code as tr from public.taxonomy_trade t
       where t.active
         and not exists (select 1 from public.supplier_capabilities sc, unnest(coalesce(sc.trades, '{}'::text[])) x
                          where sc.confirmed_at is not null and x = t.code)
       order by t.code limit 1
    ),
    ask as (
      -- finding C's shape, guaranteed: every service named belongs to a trade NO candidate declares.
      select a.tr as a, o.tr as b, 'services of ' || o.tr || ' only, a trade nobody declares' as mode,
             array(select s.trade_code || '.' || s.code from public.taxonomy_trade_service s
                    where s.active and s.trade_code = o.tr order by 1) as keys
        from declared a, outside o
      union all
      -- finding C's shape as far as the declared set can carry it: the services named are all in b, so a
      -- supplier declaring only a is asked about nothing of its own. Ordered, because {a,b} and {b,a}
      -- ask different things here. Vacuous for "never asked" when one row declares both trades.
      select a.tr as a, b.tr as b, 'services of ' || b.tr || ' only' as mode,
             array(select u.key from unheld u where u.tr = b.tr order by 1) as keys
        from declared a join declared b on b.tr <> a.tr
      union all
      -- finding A's shape: services named in both, so a union reading sees "spoken" for both.
      select a.tr, b.tr, 'services of both trades',
             array(select u.key from unheld u where u.tr in (a.tr, b.tr) order by 1)
        from declared a join declared b on b.tr > a.tr
    ),
    pair as (
      select k.*, array(select distinct split_part(x, '.', 1) from unnest(k.keys) x) as named_trades
        from ask k where cardinality(k.keys) > 0
    ),
    base as (
      select p.a, p.b, p.mode, m.supplier_id
        from pair p, public.fn_match_capability(array[p.a, p.b], p_limit := 500) m
    ),
    got as (
      select p.a, p.b, p.mode, m.supplier_id
        from pair p, public.fn_match_capability(array[p.a, p.b], p_limit := 500, p_services := p.keys) m
    ),
    -- Of the suppliers a trade-level inquiry reaches, the ones that are TRADE LEVEL for this ask and so
    -- must survive it: never asked (it declares no trade the services name), or silent where asked.
    must as (
      select b.a, b.b, b.mode, b.supplier_id,
             case when not exists (select 1 from unnest(p.named_trades) x
                                    where x = any(coalesce(sc.trades, '{}'::text[])))
                  then 'never asked' else 'silent where asked' end as reason
        from base b
        join pair p on p.a = b.a and p.b = b.b and p.mode = b.mode
        join public.supplier_capabilities sc on sc.supplier_id = b.supplier_id
       where not exists (select 1 from unnest(p.named_trades) x
                          where x = any(coalesce(sc.trades, '{}'::text[])))
          or exists (
            select 1 from unnest(p.named_trades) x
             where x = any(coalesce(sc.trades, '{}'::text[]))
               and not exists (
                 select 1 from unnest(public.fn_services_effective(sc.services, sc.trades, sc.services_removed)) k
                  where split_part(k, '.', 1) = x))
    )
    select p.a, p.b, p.mode, cardinality(p.keys) as services_asked,
           (select count(*)::int from base  z where z.a = p.a and z.b = p.b and z.mode = p.mode) as at_trade_level,
           (select count(*)::int from got   z where z.a = p.a and z.b = p.b and z.mode = p.mode) as naming_services,
           (select count(*)::int from must  z where z.a = p.a and z.b = p.b and z.mode = p.mode) as must_survive,
           coalesce((select array_agg(m.supplier_id || ' (' || m.reason || ')' order by m.supplier_id)
                       from must m
                      where m.a = p.a and m.b = p.b and m.mode = p.mode
                        and not exists (select 1 from got g
                                         where g.a = m.a and g.b = m.b and g.mode = m.mode
                                           and g.supplier_id = m.supplier_id)), '{}') as lost
      from pair p
     order by p.a, p.b, p.mode`);
  for (const r of rows) {
    console.log(`  p_trades {${r.a}, ${r.b}} asking ${r.services_asked} unheld ${r.mode}: trade level ${r.at_trade_level}, ` +
                `naming services ${r.naming_services}, must survive ${r.must_survive}` +
                (r.lost.length ? `  LOST ${r.lost.join(', ')}` : ''));
  }
  if (!rows.length) return nothing(t, 'NOT_VERIFIED_NO_MULTI_TRADE_ASK_CAN_BE_FORMED',
    'no confirmed supplier declares a trade, or the taxonomy carries no active service to ask for, so no multi-trade ask can be formed');
  const lost = rows.filter((r) => r.lost.length)
    .map((r) => `p_trades {${r.a}, ${r.b}} asking ${r.mode}: ${r.lost.join(', ')} — reached at trade level and trade level for this ask, yet the service gate dropped them`);
  assert.deepEqual(lost, [], 'the gate dropped a supplier that is trade level for this inquiry: either it read the named trades as one union, or it consulted only the trades the supplier declares');
});

test('production: no confirmed capability stores a word an active service alias already names', { skip: SKIP }, async (t) => {
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
