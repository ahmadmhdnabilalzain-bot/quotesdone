// THE SUPPLIER PORTAL OFFERS ONLY ITS FINISHED THEME (12 Nov 2026, customer_support; founder ruling 1645, browser perfection walk of
// supplier registration, finding H6). The light theme was one tap away and remembered (qd-theme=light): tab labels 1.25:1 contrast,
// links 1.5:1, the sign-in e-mail box a dark block. Local render after the fix with qd-theme=light stored: data-theme dark, no toggle,
// tab labels 9.3:1. The theme code stays behind THEME_CHOICE for when the light palette is finished.
//   node --test scripts/checks/the_supplier_portal_offers_only_its_finished_theme.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SRC = readFileSync(new URL('../../src/components/portal/SupplierPortal.tsx', import.meta.url), 'utf8');

test('the toggle is not rendered and a stored light preference is not read while THEME_CHOICE is false', () => {
  assert.match(SRC, /^const THEME_CHOICE = false;$/m, 'the light theme is offered again: finish it (contrast) before turning this on');
  assert.match(SRC, /\{THEME_CHOICE && <Button variant="outline" size="sm" onClick=\{swapTheme\}/, 'the theme toggle renders unconditionally');
  assert.match(SRC, /if \(THEME_CHOICE && \(th === 'light' \|\| th === 'dark'\)\) setTheme\(th\)/, 'a stored qd-theme=light is honoured');
  assert.match(SRC, /const \[theme, setTheme\] = useState\('dark'\);/);
});
