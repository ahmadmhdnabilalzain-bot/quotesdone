// THE PORTAL'S BELL AND ACCOUNT MENU FLOAT OVER THE PAGE AND STAY ON THE SCREEN (12 Nov 2026, customer_support; founder ruling
// 1645, browser perfection walk of supplier registration, finding H5). Measured on production at 390x844: opening either pushed the
// company name down 150 / 154 px, and the bell's panel ended at x = 441. `.qd-panel` sets position: relative (globals.css), which beat
// `absolute` on the same element. Local render after the fix (scratchpad fixes/ux-shell/render): the name moves 0 px, the bell panel
// spans x 48-368 at 390 px and 18-338 at 360 px. Reads source; fails if a panel is .qd-panel and absolute on one element again,
// if a <details> becomes the panels' anchor again, or if the menus' row stops being it.
//   node --test scripts/checks/the_portal_menus_float_over_the_page.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const MENUS = R('src/components/portal/supplier/core/HeaderMenus.tsx');
const DASH = R('src/components/portal/supplier/core/Dashboard.tsx');
const CSS = R('src/app/globals.css');

test('the sealed panel still sets position: relative, which is why a panel cannot be .qd-panel and absolute at once', () => {
  assert.match(CSS, /\.qd-panel \{\s*position: relative;/);
});

test('no element is both .qd-panel and absolute; each panel is an absolute wrapper around a .qd-panel', () => {
  for (const m of MENUS.matchAll(/className=(?:"([^"]*)"|\{[^}]*?'([^']*)'[^}]*\})/g)) {
    const cls = m[1] || m[2] || '';
    assert.ok(!(/\bqd-panel\b/.test(cls) && /\babsolute\b/.test(cls)), `a panel is .qd-panel and absolute on one element: ${cls}`);
  }
  assert.match(MENUS, /const PANEL = 'absolute inset-e-0 top-full[^']*';/);
  assert.equal((MENUS.match(/<div className=\{cn\(PANEL, '[^']*'\)\}><(div|ul) className="qd-panel/g) || []).length, 2, 'both the bell and the Account menu wrap their .qd-panel');
});

test('the panels are placed against the row of both menus, not against their own <details>', () => {
  assert.doesNotMatch(MENUS, /<details ref=\{ref\} className="relative"/, 'a <details> is the anchor again: the bell panel starts off the left of a phone');
  assert.match(DASH, /<div className="relative ms-auto flex items-center gap-2"><NotificationBell /);
});

test('the bell panel is never wider than the screen less its gutters, and both still close on Escape and a tap outside', () => {
  assert.match(MENUS, /w-\[min\(320px,calc\(100vw-32px\)\)\]/);
  assert.match(MENUS, /e\.key === 'Escape' && shut\(\)/);
  assert.match(MENUS, /addEventListener\('pointerdown', onDown\)/);
});
