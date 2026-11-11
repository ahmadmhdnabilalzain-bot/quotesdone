// THE SUPPLIER PORTAL NEVER STAYS A BLANK PAGE (11 Nov 2026, customer_support). Supplier registration certification, second free
// round on production, J5 desktop run 1, 03:07-03:11 UTC: a portal chunk answered 502 and was refused ("MIME type 'text/plain'"),
// the portal never mounted, and the page stayed an empty dark screen for 240 s with nothing said. src/components/portal/supplier/
// PortalBootFallback.tsx is rendered by the server with /portal: "Opening the supplier portal…", hidden once SupplierPortal mounts,
// and after 12 s without a mount it says the portal is slow and shows a Reload button.
// The fallback's script is RUN here against a fake document, so this fails if it stops saying so, stops offering the reload, or
// speaks over a portal that did mount; and if /portal stops rendering it or SupplierPortal stops marking the mount.
//   node --test scripts/checks/the_supplier_portal_never_stays_a_blank_page.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const SRC = R('src/components/portal/supplier/PortalBootFallback.tsx');
const LATE = /const LATE = `([\s\S]*?)`;/.exec(SRC)[1];

function run(mounted, { resources = [] } = {}) {
  const text = { textContent: 'Opening the supplier portal…' }, button = { hidden: true, onclick: null };
  const box = { querySelector: (sel) => (sel === 'button' ? button : text) };
  const timers = []; let reloaded = 0, onError = null;
  const ctx = {
    setTimeout: (f, ms) => { timers.push({ f, ms }); },
    location: { reload: () => { reloaded++; } },
    window: { addEventListener: (type, f, capture) => { if (type === 'error' && capture === true) onError = f; } },
    performance: { getEntriesByType: (k) => (k === 'resource' ? resources : []) },
    document: { documentElement: { getAttribute: (k) => (k === 'data-qd-portal' && mounted.now ? 'mounted' : null) }, getElementById: (id) => (id === 'qd-portal-boot' ? box : null) },
  };
  vm.runInNewContext(LATE, ctx);
  return { timers, text, button, fire: (ms) => timers.filter((t) => t.ms === ms).forEach((t) => t.f()), reloads: () => reloaded,
    scriptFails: (src) => onError && onError({ target: { tagName: 'SCRIPT', src } }) };
}
const offered = (r) => /taking longer than usual.*reload the page/i.test(r.text.textContent) && r.button.hidden === false;

test('a portal that never mounts says so after 12 s and offers a reload that works', () => {
  const r = run({ now: false });
  assert.deepEqual(r.timers.map((t) => t.ms), [12000]);
  r.fire(12000);
  assert.ok(offered(r));
  r.button.onclick(); assert.equal(r.reloads(), 1);
});

test('a portal that mounted is left alone', () => {
  const r = run({ now: true }); r.fire(12000);
  assert.equal(r.text.textContent, 'Opening the supplier portal…'); assert.equal(r.button.hidden, true);
});

// free round 6, run 1 J2 mobile: a chunk answered 502 text/plain and was refused; the line stood ~9 s.
test('a page chunk that fails offers the reload 3 s later, not at 12 s, unless the retry mounted the portal', () => {
  const r = run({ now: false });
  r.scriptFails('https://quotesdone.ae/_next/static/immutable/chunks/339rcm1dz4b7r.js');
  r.scriptFails('https://quotesdone.ae/_next/static/immutable/chunks/another.js');
  assert.deepEqual(r.timers.map((t) => t.ms), [12000, 3000], 'one 3 s check, armed once');
  r.fire(3000); assert.ok(offered(r));
  const m = { now: false }; const ok = run(m);
  ok.scriptFails('https://quotesdone.ae/_next/static/immutable/chunks/339rcm1dz4b7r.js'); m.now = true; ok.fire(3000);
  assert.equal(ok.button.hidden, true, 'Turbopack\'s retry mounted the portal: nothing is said');
});

test('a chunk that failed before the script ran is found in the Resource Timing list; other failures arm nothing', () => {
  const r = run({ now: false }, { resources: [{ name: 'https://quotesdone.ae/_next/static/immutable/chunks/339rcm1dz4b7r.js', responseStatus: 502 }] });
  assert.deepEqual(r.timers.map((t) => t.ms), [12000, 3000]);
  const q = run({ now: false }, { resources: [{ name: 'https://quotesdone.ae/_next/static/immutable/chunks/a.js', responseStatus: 200 }, { name: 'https://www.googletagmanager.com/gtm.js', responseStatus: 503 }] });
  q.scriptFails('https://www.googletagmanager.com/gtm.js');
  assert.deepEqual(q.timers.map((t) => t.ms), [12000], 'only the page\'s own chunks count');
});

test('/portal renders it with the page, it hides on mount, and SupplierPortal marks the mount', () => {
  assert.match(R('src/app/[locale]/portal/page.tsx'), /<PortalBootFallback \/><SupplierPortal \/>/);
  assert.match(SRC, /html\[data-qd-portal="mounted"\] #qd-portal-boot\{display:none\}/);
  assert.match(R('src/components/portal/SupplierPortal.tsx'), /document\.documentElement\.setAttribute\('data-qd-portal', 'mounted'\)/);
  assert.doesNotMatch(SRC, /[؀-ۿ]/, 'English only to a supplier (ruling 1008)');
});
