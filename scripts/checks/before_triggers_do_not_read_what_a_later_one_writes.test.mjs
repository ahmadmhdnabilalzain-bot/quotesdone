// A BEFORE TRIGGER MUST NOT DEPEND ON A COLUMN A LATER-SORTING BEFORE TRIGGER FILLS IN.
//
// BEFORE triggers on the same table fire in NAME order. So if trigger A tests `NEW.x is null` and
// trigger B — sorting after A — assigns `NEW.x`, then A always sees NULL and its branch is dead.
// Nothing errors. Nothing is logged. The feature simply never happens.
//
// Two instances were found on 13 Aug 2026, one in each direction:
//
//   agent_actions     fn_agent_actions_fill_alternatives returned early on `NEW.decision_log_id is
//                     null`, and decision_log_id is assigned by zzz_action_gate — named `zzz_` on
//                     purpose so it runs last. The filler had never fired on an insert:
//                     alternatives null on 1,254 of 1,362 recommendations in 30 days.
//
//   agent_knowledge   a00_agent_knowledge_metadata stamped source_ref =
//                     'unattributed: no provenance was recorded...' before
//                     trg_knowledge_provenance_stamp could derive a real citation from the row's
//                     own topic. 1,084 of 2,049 rows unattributed, and the dropbox_asset: branch
//                     had produced exactly ZERO rows ever. The provenance function's own comment
//                     had predicted it: "A source_ref that says 'unknown' is worse than one that is
//                     absent, because the check counts it as present."
//
// Both are fixed by ordering, and this check is the generalisation: it asks the whole public schema
// the same question and fails on any new pair. It is green today with zero hits, so a failure here
// is a genuine new instance rather than a backlog.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// tgtype bit 1 = ROW, bit 2 = BEFORE. Both required: statement-level triggers have no NEW, and
// AFTER triggers cannot assign to it.
const SQL = `
with bt as (
  select c.relname as tbl, t.tgname, p.prosrc
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  where n.nspname = 'public' and not t.tgisinternal
    and (t.tgtype & 2) = 2 and (t.tgtype & 1) = 1
),
reads as (
  select tbl, tgname, lower(m[1]) col
  from bt, lateral regexp_matches(prosrc, 'NEW\\.([a-z_]+)\\s+is\\s+null', 'g') m
),
writes as (
  select tbl, tgname, lower(m[1]) col
  from bt, lateral regexp_matches(prosrc, 'NEW\\.([a-z_]+)\\s*:=', 'g') m
)
select r.tbl, r.tgname as reader, r.col, w.tgname as later_writer
from reads r
join writes w on w.tbl = r.tbl and w.col = r.col and w.tgname > r.tgname
order by 1, 2, 3`;

// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
for (const [label, project] of [['production', 'htdblwldjkcgjvmqkbeh']]) {
  test(`no BEFORE trigger reads a column a later one writes on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token, so pg_trigger cannot be read'); return; }
    const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: SQL }),
    });
    assert.ok(r.ok, `query failed on ${project}: ${r.status}`);
    const rows = await r.json();

    // A zero here has to mean "asked and found none", never "asked nothing" — the population is
    // asserted so an empty or broken query cannot read as a pass.
    const [pop] = await (await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: "select count(*)::int n from pg_trigger t join pg_class c on c.oid=t.tgrelid "
        + "join pg_namespace s on s.oid=c.relnamespace where s.nspname='public' and not t.tgisinternal "
        + "and (t.tgtype & 2)=2 and (t.tgtype & 1)=1" }),
    })).json();
    assert.ok(pop.n > 0, `no row-level BEFORE triggers were found at all on ${label} — the query is `
      + 'wrong, not the schema, and a zero result here would be meaningless');

    const bad = rows.map((x) => `${x.tbl}: ${x.reader} reads NEW.${x.col}, which ${x.later_writer} assigns later`);
    assert.deepEqual(bad, [],
      `on ${label}, a BEFORE trigger depends on a column that a LATER-SORTING BEFORE trigger fills in. `
      + 'BEFORE triggers fire in NAME order, so the reader always sees NULL and its branch is dead — '
      + 'silently, with nothing logged. Rename one of them so the writer runs first, or move the '
      + `logic. Offenders: ${bad.join(' | ')}`);
    console.log(`${label}: ${pop.n} row-level BEFORE trigger(s) examined, 0 order-dependent pairs`);
  });
}
