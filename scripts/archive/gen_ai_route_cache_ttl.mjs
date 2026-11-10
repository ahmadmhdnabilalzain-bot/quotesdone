// ROW #8 §7 — teach fn_ai_route to hand back the response-cache TTL, WITHOUT retyping its body.
//
// fn_ai_route is 7,889 characters with four separate return points. The defect is one missing key
// in one of them, and the repo's promotion rule is that a routine reaches production by reading a
// verified definition back out — never by retyping. So the live definition is read, exactly one
// line is added, and the result is written to scripts/sql/. If the anchor is not found EXACTLY
// once the script exits non-zero and writes nothing: a silent no-op here would produce a file that
// looks like a fix, applies cleanly, and changes nothing.
//
// The anchor is `'max_tokens', v_pol.max_tokens,` — the one line in the final return that already
// reads from the policy record, which is where the new column lives. Adding the TTL beside it keeps
// the two policy-sourced ceilings together.
//
// NOT `'cache', coalesce(v_reg.supports_cache, false)` two lines below, and the difference matters:
// that is the model REGISTRY's prompt-prefix cache flag — a provider feature about resending a long
// system prompt cheaply. The new key is the RESPONSE cache TTL, about replaying a whole answer.
// Two different mechanisms that both contain the word cache, and conflating them would switch
// response caching on for every model that supports prompt caching, which is all six.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/fn_ai_route_returns_cache_ttl.sql';

const rows = await mgmtRead(STAGE, `select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_ai_route' limit 1`);
const def = rows[0] && rows[0].def;
if (!def) { console.error('fn_ai_route not found on staging'); process.exit(1); }

if (/cache_ttl_min/.test(def)) {
  console.error('REFUSING: fn_ai_route already returns cache_ttl_min. Nothing to do.');
  process.exit(1);
}

const ANCHOR = /^(\s*)'max_tokens', v_pol\.max_tokens,\s*$/m;
const hits = def.match(new RegExp(ANCHOR.source, 'gm'));
if (!hits || hits.length !== 1) {
  console.error(`REFUSING: the max_tokens anchor was found ${hits ? hits.length : 0} time(s), expected exactly 1.`);
  console.error('fn_ai_route has changed shape since this generator was written. Re-read it before editing.');
  process.exit(1);
}

const patched = def.replace(ANCHOR, (_m, indent) =>
  `${indent}'max_tokens', v_pol.max_tokens,\n` +
  `${indent}'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0),`);
if (patched === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${patched};\n`);
console.log(`wrote ${OUT}`);
console.log(`  added: 'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0)`);
