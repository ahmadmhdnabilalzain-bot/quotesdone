// WHICH ROW LOCKS A HEALTHY-DAY REPLAY WOULD TAKE ON LIVE TABLES (it_engineer, 19 Oct 2026).
// A replay runs a routine inside one transaction that is rolled back at the end, so every row lock taken on the way
// is held for the whole replay. A live caller that selects "for update skip locked" then silently skips those rows.
// That happened on 19 Oct: five sales_engineer duties went unrun while CI replays held their seat_duty rows.
// lockingCalls() walks a routine's body and every public routine it calls, transitively, through the schema mirror,
// and returns each path that reaches a FOR UPDATE / FOR SHARE clause. Calls named in `stubbed` are not followed,
// because the replay replaces them with a constant. A row lock in the replayed body itself is removed by
// alarm_replay.mjs (stripRowLocks), because that body reads its as-of views, never a live row it must keep.
export const ROW_LOCK = /\bfor\s+(?:no\s+key\s+)?(?:update|share|key\s+share)\b/i;

/** name -> [body, ...] for every public routine in the mirror text. */
export function routineBodies(mirror) {
  const out = new Map();
  const re = /CREATE OR REPLACE FUNCTION public\.(\w+)\(/g;
  const starts = [...mirror.matchAll(re)];
  starts.forEach((m, i) => {
    const end = i + 1 < starts.length ? starts[i + 1].index : mirror.length;
    const list = out.get(m[1]) ?? []; list.push(mirror.slice(m.index, end)); out.set(m[1], list);
  });
  return out;
}

const strip = (s) => s.replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''");
const callsIn = (body) => [...new Set([...strip(body).matchAll(/\bpublic\.(\w+)\s*\(/g)].map((m) => m[1]))];

/** Paths ("a -> b -> c") from `name`'s callees to a body that takes a row lock. The root body itself is not judged. */
export function lockingCalls(name, rootBody, bodies, stubbed = []) {
  const skip = new Set(stubbed.map((s) => s.replace(/^public\./, '')));
  const found = []; const seen = new Set([name]);
  const walk = (fn, path) => {
    if (seen.has(fn) || skip.has(fn) || !bodies.has(fn)) return;
    seen.add(fn);
    for (const b of bodies.get(fn)) {
      if (ROW_LOCK.test(strip(b))) found.push([...path, fn].join(' -> '));
      for (const c of callsIn(b)) walk(c, [...path, fn]);
    }
  };
  for (const c of callsIn(rootBody)) walk(c, [name]);
  return found;
}
