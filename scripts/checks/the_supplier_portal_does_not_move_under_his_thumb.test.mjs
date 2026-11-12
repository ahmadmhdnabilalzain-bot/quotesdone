// THE SUPPLIER PORTAL DOES NOT MOVE UNDER HIS THUMB (12 Nov 2026, customer_support; founder ruling 1645, browser perfection walk of
// supplier registration, finding M15). Production: CLS 0.18-0.36 as /portal opened on a phone, 0.18-0.35 after a reload. Local render
// before the fix reproduced it (0.18 at 390 and 360, 0.35 at 1440, the shifted node the whole <body>, y 152 -> 0): the boot line's
// `margin: 18vh` collapsed through <body>. After: CLS 0 opening /portal and the workspace at all three sizes, and on reload.
// Reads source; fails if the boot line gets a top margin again, if the workspace's first paint is a centred line again, or if the
// tab-switch bars push the panel down again.
//   node --test scripts/checks/the_supplier_portal_does_not_move_under_his_thumb.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const BOOT = R('src/components/portal/supplier/PortalBootFallback.tsx');
const DASH = R('src/components/portal/supplier/core/Dashboard.tsx');
const STYLE = /const STYLE = '([^']*)';/.exec(BOOT)[1];

test('the boot line spaces itself with padding, never a margin that collapses through <body>, and holds the screen', () => {
  const rule = /#qd-portal-boot\{([^}]*)\}/.exec(STYLE.replace(/html\[data-qd-portal="mounted"\] #qd-portal-boot\{display:none\}/, ''))[1];
  assert.doesNotMatch(rule, /margin:\s*[^;]*\d+vh|margin-top/, 'a top margin on the boot line moves the whole page when it hides');
  assert.match(rule, /min-height:100vh/);
  assert.match(STYLE, /html\{scrollbar-gutter:stable\}/);
});

test('the workspace first paints its own outline, and the tab-switch bars float over the outgoing panel', () => {
  assert.match(DASH, /return <WorkspaceOutline lang=\{lang\} \/>;/);
  assert.doesNotMatch(DASH, /return <div className=\{S\.center\} aria-busy="true">\{t\(lang, 'loading_dash'\)\}<\/div>/);
  assert.match(DASH, /\{switchBars && <Card aria-busy className="qd-panel absolute inset-x-0 top-0 z-10/);
});
