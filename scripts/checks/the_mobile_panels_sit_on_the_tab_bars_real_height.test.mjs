// THE MOBILE PANELS SIT ON THE TAB BAR'S REAL HEIGHT (customer_support, E2E stage 1 D7 follow-up, 30 Sep 2026).
// #1155 set the panel's bottom to a hard-coded 56px; production's bar is 69px at 375px, so the panel still
// covered its top 13px. The bar now publishes its measured height (--qd-tabbar-h, safe-area padding included)
// and both panels above it use that. Offline, over the source.
//   node --test scripts/checks/the_mobile_panels_sit_on_the_tab_bars_real_height.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const s = readFileSync('src/components/me/PortalShell.tsx', 'utf8');
test('the tab bar publishes its measured height and nothing assumes a fixed one', () => {
  assert.match(s, /<nav ref=\{tabBar\} aria-label=\{t\('nav_main_bar'\)\}/, 'the tab bar no longer carries the ref that measures it');
  assert.match(s, /setProperty\('--qd-tabbar-h', el\.offsetHeight \+ 'px'\)/);
  assert.match(s, /\.observe\(el, \{ box: 'border-box' \}\)/, 'the bar is observed without its safe-area padding');
  // Tailwind 4 writes a CSS-variable value as bottom-(--x,0px); v3 needed bottom-[var(--x,0px)]. Same rule.
  assert.ok((s.match(/bottom-(?:\[var\(--qd-tabbar-h,0px\)\]|\(--qd-tabbar-h,0px\))/g) || []).length >= 2, 'a panel above the bar no longer uses its real height');
  assert.doesNotMatch(s, /bottom-\[calc\(\d+px\+env\(safe-area-inset-bottom\)\)\]/, 'a hard-coded bar height is back');
});
