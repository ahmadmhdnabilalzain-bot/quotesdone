// Splice helper for the production-direct protocol.
//
// Reads a routine's LIVE body out of the database, replaces one or more exact anchors, asserts each
// anchor matched exactly once, and returns the new body.  A splice that matched zero or twice is a
// stop, not a warning: the whole point of generating from the live body is that the file that lands
// is the file that was measured.
import { sql } from '../lib/db.mjs';

export async function liveBody(name, args) {
  const rows = await sql(`select pg_get_functiondef(p.oid) d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '${name}'
     ${args ? `and pg_get_function_identity_arguments(p.oid) = '${args}'` : ''}`);
  if (rows.length !== 1) throw new Error(`${name}: expected exactly one definition, got ${rows.length}`);
  return rows[0].d;
}

export function splice(body, edits) {
  let out = body;
  for (const [anchor, replacement] of edits) {
    const n = out.split(anchor).length - 1;
    if (n !== 1) throw new Error(`anchor matched ${n} times, expected 1:\n---\n${anchor}\n---`);
    out = out.split(anchor).join(replacement);
  }
  return out;
}
