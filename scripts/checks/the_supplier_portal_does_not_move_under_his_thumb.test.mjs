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

// THE LIST LANDS WITHOUT MOVING THE PAGE (12 Nov 2026, sales_engineer; stub walk of the workspace at 390x844 while a profile is read).
// Before: one shift of 0.144 the moment the list arrived (the "services unconfirmed" hold line stood above the "reading" card and
// vanished), and 0.0945 when step A's summary was inserted above the check lists. After: 0.0197 each (the card's own line) and 0.0405
// for a J9-length summary of 12 phrases.
test('while his documents are read the hold line is not shown above the reading card, and step A\'s block holds its place', async () => {
  assert.match(DASH, /const servicesLeft = !!receivedCard && \(receivedCard\.kind === 'services' \|\| \(receivedCard\.kind === 'reading' && ov\.supplier\.licence_gate_reason === 'services_unconfirmed'\)\);/);
  const TAB = R('src/components/portal/supplier/ServicesTab.tsx');
  // one shape before and after the summary lands (review of #1975, note 4): the same boxes, so the holder is exactly the block's height
  // (235 px at 390, 166 px at 1440 in the stub walk, for a one-line and a J9-length summary alike), and a step-A shift of 0
  assert.match(TAB, /data-testid=\{pr \? 'reading-progress' : 'reading-progress-held'\}/);
  assert.match(TAB, /<div className="line-clamp-4 min-h-\[4lh\] text-\[15px\] leading-relaxed text-foreground sm:line-clamp-3 sm:min-h-\[3lh\]">/);
  // his phrases in two rows of FIXED height (review of #1976, item 2), the holder's chips in the same rows: a long list cannot make the
  // block taller, and what does not fit is counted in "+N more" (servicesRead.packPhrases), never hidden behind a sideways scroll
  assert.match(TAB, /const PHRASE_ROWS = 'mt-2 flex h-\[66px\] flex-wrap content-start gap-1\.5 overflow-hidden';/);
  assert.match(TAB, /const PHRASE_CHIP = 'max-w-full truncate rounded-full [^']*leading-5[^']*';/, 'one 30 px chip height, and an ellipsis on a phrase wider than the row');
  assert.match(TAB, /: <ul className=\{PHRASE_ROWS\}>\{\[0, 1, 2\]\.map/, 'the holder uses the same rows');
  assert.match(TAB, /\{more > 0 \? <li className=\{PHRASE_MORE\}>\{'\+' \+ more \+ ' more'\}<\/li> : null\}/);
  assert.doesNotMatch(TAB, /overflow-x-auto \[scrollbar-width:none\] \[&::-webkit-scrollbar\]:hidden">\s*\{pr/, 'no hidden sideways row of phrases');
  // a screen reader is read EVERY phrase: the two visible rows are hidden from it and a full list stands beside them (second review of
  // #1976: at 390 the visible rows exposed 3 of 8 phrases, and 2 of 20 on a long profile)
  assert.match(TAB, /<ul className="sr-only" data-testid="reading-phrases-all">\{words\.map\(\(w\) => <li key=\{w\} dir="auto">\{w\}<\/li>\)\}<\/ul>/);
  assert.match(TAB, /<ul ref=\{ref\} aria-hidden="true" className=\{PHRASE_ROWS\} data-testid="reading-phrases">/);
  // and the widths are measured again once the web font is in, so a chip never wraps into the hidden third row
  assert.match(TAB, /document\.fonts\?\.ready\.then\(\(\) => \{ if \(live\) setFontsIn\(true\); \}\)/);
  const { packPhrases, PHRASE_GAP } = await import(new URL('../../src/components/portal/supplier/servicesRead.ts', import.meta.url).href);
  assert.equal(PHRASE_GAP, 6, 'gap-1.5');
  // J9 at 390 (a 304 px row): every phrase that fits, in his order first-fit, with room for "+N more" on row 2
  assert.deepEqual(packPhrases([150, 160, 140, 150], 304, 80), [0, 2, 1], 'the short third phrase fills row 1 rather than being lost; the fourth is counted');
  assert.deepEqual(packPhrases([100, 100, 90], 304, 80), [0, 1, 2], 'all fit: no "+N more" room taken');
  assert.deepEqual(packPhrases([400, 50], 304, 80), [0, 1], 'a phrase wider than the row takes it alone (ellipsis on screen)');
  assert.deepEqual(packPhrases([300, 300, 300], 304, 80), [0], 'row 2 is given up to the "+N more" chip when the next phrase and the chip do not both fit');
  for (const [ws, row, more] of [[[120, 90, 200, 60, 70, 150, 40], 304, 76], [[300, 10, 10, 10, 280], 304, 70]]) {
    const idx = packPhrases(ws, row, more); const left = ws.length - idx.length;
    const rows = [0, 0]; let r = 0;
    for (const i of idx) { const w = Math.min(ws[i], row); const need = (rows[r] ? PHRASE_GAP : 0) + w; if (rows[r] + need > row) r++; assert.ok(r < 2, 'never a third row'); rows[r] += (rows[r] ? PHRASE_GAP : 0) + w; }
    if (left) assert.ok(rows[1] + (rows[1] ? PHRASE_GAP : 0) + more <= row, 'the "+N more" chip fits on row 2');
  }

  assert.match(TAB, /<p className=\{cn\(sub, 'invisible mt-2 flex items-start gap-2'\)\}><span className="h-4 w-4 shrink-0" \/><span>\{PROPOSED_COPY\.progress_help\}<\/span><\/p>/, 'the holder keeps the help line\'s height');
  assert.doesNotMatch(TAB, /min-h-56/);
});
