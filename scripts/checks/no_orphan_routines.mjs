// "No function should exist that touches no table. Nothing should run unlinked from the knowledge
// and the company." — the founder's rule, made measurable.
//
//   node scripts/checks/no_orphan_routines.mjs [--ref=<project>]
//
// THE RULE AS LITERALLY WRITTEN DOES NOT ISOLATE DEAD CODE, and that is worth stating rather than
// quietly reinterpreting. Measured on production 11 Aug 2026, "public routines whose body names no
// table or view" returns 150 rows, of which:
//   * ~120 are pgvector's own operators (vector_add, halfvec_cmp, l2_distance…) installed into
//     public by the extension;
//   * the rest are pure scalar helpers that are CORRECT to touch no table — fn_norm_text (7
//     callers), fn_term_matches (7), fn_quote_spec_group (6), fn_authority_rank, mask_contact — and
//     trigger functions that operate on NEW/OLD.
// A pure function with callers is not dead code. It is a function.
//
// So this check measures what the rule is FOR: a routine that nothing anywhere calls. Every call
// site the estate has is searched — other routines, triggers, views, constraints, cron commands,
// the edge functions, and the Next.js app — and a routine reachable from none of them is an orphan.
//
// Exit non-zero when the orphan count exceeds the recorded baseline, so this is a ratchet: the
// number may fall without ceremony and cannot rise without someone editing the baseline and saying
// why in the commit.
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const REF = (process.argv.find(a => a.startsWith('--ref=')) || '--ref=htdblwldjkcgjvmqkbeh').slice(6);
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(SUPABASE_TOKEN_FILE)
      ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();
if (!token) { console.error('SUPABASE_ACCESS_TOKEN is not set and no local access token was found.'); process.exit(2); }

// 58 is what production MEASURED on 11 Aug 2026, not what it should be. 0 is the goal. It is set
// to the measurement rather than to the goal so the check is a ratchet from today: the number may
// fall without ceremony and cannot rise without someone editing this line and saying why.
//
// They are NOT deleted in the same change. Several are reachable over PostgREST as RPCs whose names
// the console can build at runtime (fn_refund_decide, fn_undo, fn_inv_receive), so "named nowhere in
// the repository" is evidence of an orphan and not proof of one. Dropping 58 routines on the
// strength of a text search is the kind of tidy-up that takes a working path with it.
const BASELINE = Number(process.env.ORPHAN_BASELINE ?? 58);

const q = async (sql, attempt = 0) => {
  try {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
    const b = await r.text();
    if (!r.ok) throw new Error(r.status + ': ' + b.slice(0, 300));
    return JSON.parse(b);
  } catch (e) {
    if (attempt < 3) { await new Promise(s => setTimeout(s, 2000 * 2 ** attempt)); return q(sql, attempt + 1); }
    throw e;
  }
};

// Candidates: public routines with no caller INSIDE the database. Extension-owned routines are
// excluded by pg_depend deptype='e' — they belong to pgvector, not to this company. Trigger
// functions are excluded by their attachment, not by their name prefix, because a trigger function
// with no trigger IS an orphan and a name convention would hide it.
const CANDIDATES = `
with f as (
  select p.oid, p.proname, pg_get_functiondef(p.oid) def from pg_proc p
   where p.pronamespace='public'::regnamespace and p.prokind in ('f','p')
     and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
)
select x.proname from f x
where not exists (select 1 from f o where o.oid<>x.oid and o.def ~ ('\\y'||x.proname||'\\s*\\('))
  and not exists (select 1 from pg_trigger tg where tg.tgfoid=x.oid)
  and not exists (select 1 from pg_views pv where pv.schemaname='public' and pv.definition ~ ('\\y'||x.proname||'\\s*\\('))
  and not exists (select 1 from cron.job j where j.command ~ ('\\y'||x.proname||'\\s*\\('))
  and not exists (select 1 from pg_constraint c where pg_get_constraintdef(c.oid) ~ ('\\y'||x.proname||'\\s*\\('))
order by 1`;

// Everything outside the database that can name a routine: edge functions, the app, the scripts
// that operate the estate. Read once into a single haystack — 200 candidates against a per-file
// walk is the shape that turns a check into a coffee break.
function haystack() {
  const roots = ['supabase/functions', 'src', 'scripts', 'supabase/migrations'];
  const want = /\.(ts|tsx|js|mjs|sql|json)$/i;
  let out = '';
  const walk = (d) => {
    let entries; try { entries = readdirSync(d); } catch { return; }
    for (const e of entries) {
      if (e === 'node_modules' || e === '.next' || e === 'dist') continue;
      const p = join(d, e);
      let st; try { st = statSync(p); } catch { continue; }
      if (st.isDirectory()) walk(p);
      else if (want.test(e) && st.size < 4_000_000) { try { out += readFileSync(p, 'utf8'); } catch { /* unreadable is not a call site */ } }
    }
  };
  for (const r of roots) walk(r);
  return out;
}

const rows = await q(CANDIDATES);
const hay = haystack();
const orphans = rows.map(r => r.proname).filter(n => !hay.includes(n));

console.log(`${REF}: ${rows.length} routine(s) have no caller inside the database.`);
console.log(`${orphans.length} of those are named nowhere in the repository either — nothing anywhere calls them.\n`);
for (const o of orphans) console.log('  ORPHAN  ' + o);

if (orphans.length > BASELINE) {
  console.error(`\nORPHAN COUNT ROSE: ${orphans.length} > baseline ${BASELINE}. Either wire the new routine to a caller or lower it deliberately.`);
  process.exit(1);
}
console.log(`\nOK — ${orphans.length} orphan(s) against a baseline of ${BASELINE}.`);
