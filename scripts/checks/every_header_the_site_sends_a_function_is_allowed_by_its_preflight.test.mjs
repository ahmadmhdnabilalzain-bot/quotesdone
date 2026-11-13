// A BROWSER SENDS THE POST ONLY IF THE PREFLIGHT ALLOWS EVERY HEADER ON IT.
// Assigned: it_engineer.
//
// 13 Nov 2026, the founder's own iPhone on quotesdone.ae: "Download my data" answered "Something went wrong. Please try
// again." The page (src/components/portal/PrivacyControls.tsx) called the edge function my_data_pdf with the headers
// apikey, Authorization and Content-Type; the function's preflight answer listed 'authorization, content-type'. Every
// browser then refuses to send the POST: the edge log showed two OPTIONS 200 and no POST. It had never worked in a real
// browser, and it had passed two signed-in walks, the author's own browser proof and three reviews: each browser run
// drove Playwright with request interception on, and an intercepted request is not held to the preflight's header list;
// each review checked that the preflight answered 200, not what it allowed.
//
// This reads both sides, for every edge function the website calls through fnUrl('<name>') with explicit headers: every
// header name the page sends must be in that function's Access-Control-Allow-Headers (or the function allows '*').
// A function whose allow-list this cannot find in its own folder is listed, not passed silently.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const walk = (dir, out = []) => { for (const n of readdirSync(dir)) { const p = join(dir, n); if (statSync(p).isDirectory()) walk(p, out); else out.push(p); } return out; };
// CORS-safelisted request headers need no listing (Fetch standard); content-type with application/json does.
const SAFELISTED = new Set(['accept', 'accept-language', 'content-language']);

/** [{ fn, file, headers: string[] }] for every fetch(fnUrl('name'), { headers: {...} }) in the website's source. */
export function callsWithHeaders(root = join(REPO, 'src')) {
  const calls = [];
  for (const file of walk(root)) {
    if (!/\.(ts|tsx|mjs|js)$/.test(file) || /\.test\./.test(file)) continue;
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/fnUrl\(\s*['"]([a-z0-9_]+)['"]\s*\)/g)) {
      const after = src.slice(m.index + m[0].length, m.index + m[0].length + 700);
      const h = /headers\s*:\s*\{([^}]*)\}/.exec(after);
      if (!h) continue;
      const names = [...h[1].matchAll(/(?:['"]([A-Za-z-]+)['"]|\b([A-Za-z]+))\s*:/g)].map((k) => (k[1] || k[2]).toLowerCase());
      calls.push({ fn: m[1], file: file.slice(REPO.length + 1), headers: [...new Set(names)] });
    }
  }
  return calls;
}
/** The function's own Access-Control-Allow-Headers, from the literal(s) in its folder; null when none is written there. */
export function allowedHeaders(fn, root = join(REPO, 'supabase', 'functions')) {
  const dir = join(root, fn);
  if (!existsSync(dir)) return null;
  const all = new Set(); let found = false;
  for (const file of walk(dir)) {
    if (!/\.ts$/.test(file) || /\.test\./.test(file)) continue;
    for (const m of readFileSync(file, 'utf8').matchAll(/Access-Control-Allow-Headers['"]?\s*:\s*['"`]([^'"`]*)['"`]/g)) {
      found = true; for (const x of m[1].split(',')) all.add(x.trim().toLowerCase());
    }
  }
  return found ? all : null;
}
/** Every header a call sends that its function's preflight does not allow. */
export function refusedHeaders(calls, allowOf) {
  const out = [];
  for (const c of calls) {
    const allow = allowOf(c.fn);
    if (!allow || allow.has('*')) continue;
    const missing = c.headers.filter((h) => !SAFELISTED.has(h) && !allow.has(h));
    if (missing.length) out.push({ ...c, missing, allow: [...allow].sort() });
  }
  return out;
}

test('every header the site sends an edge function is in that function\'s preflight answer', () => {
  const calls = callsWithHeaders();
  assert.ok(calls.length >= 5, `only ${calls.length} calls with explicit headers were found: the scan no longer reads the source`);
  assert.ok(calls.some((c) => c.fn === 'my_data_pdf'), 'the my_data_pdf call was not found: the scan no longer reads PrivacyControls.tsx');
  const bad = refusedHeaders(calls, (fn) => allowedHeaders(fn));
  assert.deepEqual(bad.map((b) => `${b.fn}: the page sends ${b.missing.join(', ')} (${b.file}); the preflight allows ${b.allow.join(', ')}`), []);
});

test('a function whose allow-list is not written in its own folder is named, not passed silently', () => {
  const unknown = [...new Set(callsWithHeaders().filter((c) => allowedHeaders(c.fn) === null).map((c) => c.fn))].sort();
  // Today every function the site calls with explicit headers writes its allow-list in its own folder. A function that moves to a
  // shared helper must be added to this check's reader rather than drop out of it.
  assert.deepEqual(unknown, []);
});

test('the rule fails on the defect of 13 Nov 2026 and passes once the header is allowed', () => {
  const call = [{ fn: 'my_data_pdf', file: 'src/components/portal/PrivacyControls.tsx', headers: ['apikey', 'authorization', 'content-type'] }];
  const before = refusedHeaders(call, () => new Set(['authorization', 'content-type']));
  assert.equal(before.length, 1); assert.deepEqual(before[0].missing, ['apikey']);
  assert.deepEqual(refusedHeaders(call, () => new Set(['authorization', 'content-type', 'apikey', 'x-client-info'])), []);
  assert.deepEqual(refusedHeaders(call, () => new Set(['*'])), []);
  assert.deepEqual(refusedHeaders([{ fn: 'x', file: 'f', headers: ['accept'] }], () => new Set(['authorization'])), [], 'a safelisted header needs no listing');
});
