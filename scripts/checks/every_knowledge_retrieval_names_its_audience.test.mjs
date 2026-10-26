// Every call to the knowledge retrieval routines names its audience.
//
// fn_reason_retrieve and fn_reason_retrieve_ml reserve a seat's own rows (internal facts) only for an audience named
// 'internal' or 'founder'. A call that leaves p_audience out is safe only while the guarded signature is the sole one
// live: an older overload without the parameter, or a default changed later, would hand internal rows to a public
// reader. 19 Oct 2026: _shared/given_trade_knowledge.ts, read by site_assistant (the public widget), left it out, as
// did four eval/kb scripts. This scans every edge function and every script (tests excepted: they mock the rpc) and
// fails on any call whose argument list does not carry p_audience.
//
// A call may carry it through a name defined in the same file (`...area`, `${aud}`) only when that definition names
// p_audience and has no empty-string branch, so a conditional that drops it still fails.
//
// Not covered: scripts/sql. Those files are applied history; the live callers in SQL are pinned by
// a_seats_own_pack_fills_half_of_every_retrieval.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SKIP_DIRS = new Set(['node_modules', 'checks', 'sql', 'full_schema']);

function walk(dir, out = []) {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) { if (!SKIP_DIRS.has(n)) walk(p, out); }
    else if (/\.(ts|mjs|js)$/.test(n) && !/\.test\.[mt]?[jt]s$/.test(n)) out.push(p);
  }
  return out;
}

// Text from the '(' at `open` to its matching ')'.
function span(src, open) {
  let d = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '(') d++;
    else if (src[i] === ')' && --d === 0) return src.slice(open, i + 1);
  }
  return src.slice(open);
}

const isComment = (src, at) => /^\s*(\/\/|\*|--)/.test(src.slice(src.lastIndexOf('\n', at) + 1, at));

function carries(src, args) {
  if (/\bp_audience\b/.test(args)) return true;
  for (const [, name] of args.matchAll(/(?:\.\.\.|\$\{)\s*([A-Za-z_$][\w$]*)/g)) {
    const def = src.match(new RegExp(`(?:const|let)\\s+${name.replace(/\$/g, '\\$')}\\s*=([^\\n]*)`));
    if (def && /\bp_audience\b/.test(def[1]) && !/:\s*(''|""|``)/.test(def[1])) return true;
  }
  return false;
}

// Every call site in one source text: a SQL call `fn_reason_retrieve[_ml](`, a literal rpc('fn_reason_retrieve…', …),
// or a dynamic rpc(x.retrieve, …) (think.ts picks the routine per space).
export function missing(src) {
  const bad = [];
  const re = /\bfn_reason_retrieve(?:_ml)?\(|\brpc\(\s*(?:['"`]fn_reason_retrieve(?:_ml)?['"`]|[\w.]+\.retrieve\b)/g;
  for (const m of src.matchAll(re)) {
    if (isComment(src, m.index)) continue;
    const open = src.indexOf('(', m.index);
    if (!carries(src, span(src, open))) bad.push(src.slice(0, m.index).split('\n').length);
  }
  return bad;
}

test('the scanner fails the shapes that leave the audience out', () => {
  assert.deepEqual(missing(`deps.rpc('fn_reason_retrieve_ml', { p_seat: 'x', p_k: k });`), [1]);
  assert.deepEqual(missing("sql(`select public.fn_reason_retrieve('a', v, 6)`)"), [1]);
  assert.deepEqual(missing("const aud = f ? `, p_audience => 'x'` : '';\nq(`fn_reason_retrieve(s, v, 6${aud})`)"), [2]);
  assert.deepEqual(missing("const area = { p_k: 1 };\ndeps.rpc(rt.retrieve, { ...area })"), [2]);
  assert.deepEqual(missing(`deps.rpc('fn_reason_retrieve_ml', { p_seat: 'x', p_audience: 'visitor' });`), []);
  assert.deepEqual(missing("const area = { p_audience: ctx.audience ?? null };\ndeps.rpc(rt.retrieve, { p_k: 6, ...area })"), []);
  assert.deepEqual(missing('// fn_reason_retrieve_ml(seat, v) is described here'), []);
});

test('every edge function and script names p_audience when it calls the retrieval routines', () => {
  const files = [...walk(join(root, 'supabase', 'functions')), ...walk(join(root, 'scripts'))];
  assert.ok(files.length > 100, `scanned only ${files.length} files`);
  const found = files.flatMap((f) => missing(readFileSync(f, 'utf8')).map((l) => `${relative(root, f)}:${l}`));
  assert.deepEqual(found, [], 'calls without p_audience:\n' + found.join('\n'));
});
