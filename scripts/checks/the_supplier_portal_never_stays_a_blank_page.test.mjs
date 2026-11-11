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

function run(mounted) {
  const text = { textContent: 'Opening the supplier portal…' }, button = { hidden: true, onclick: null };
  const box = { querySelector: (sel) => (sel === 'button' ? button : text) };
  let timer = null, reloaded = 0;
  const ctx = {
    setTimeout: (f, ms) => { timer = { f, ms }; },
    location: { reload: () => { reloaded++; } },
    document: { documentElement: { getAttribute: (k) => (k === 'data-qd-portal' && mounted ? 'mounted' : null) }, getElementById: (id) => (id === 'qd-portal-boot' ? box : null) },
  };
  vm.runInNewContext(LATE, ctx);
  return { timer, text, button, fire: () => timer.f(), reloads: () => reloaded };
}

test('a portal that never mounts says so after 12 s and offers a reload that works', () => {
  const r = run(false);
  assert.equal(r.timer.ms, 12000);
  r.fire();
  assert.match(r.text.textContent, /taking longer than usual.*reload the page/i);
  assert.equal(r.button.hidden, false);
  r.button.onclick(); assert.equal(r.reloads(), 1);
});

test('a portal that mounted is left alone', () => {
  const r = run(true); r.fire();
  assert.equal(r.text.textContent, 'Opening the supplier portal…'); assert.equal(r.button.hidden, true);
});

test('/portal renders it with the page, it hides on mount, and SupplierPortal marks the mount', () => {
  assert.match(R('src/app/[locale]/portal/page.tsx'), /<PortalBootFallback \/><SupplierPortal \/>/);
  assert.match(SRC, /html\[data-qd-portal="mounted"\] #qd-portal-boot\{display:none\}/);
  assert.match(R('src/components/portal/SupplierPortal.tsx'), /document\.documentElement\.setAttribute\('data-qd-portal', 'mounted'\)/);
  assert.doesNotMatch(SRC, /[؀-ۿ]/, 'English only to a supplier (ruling 1008)');
});
