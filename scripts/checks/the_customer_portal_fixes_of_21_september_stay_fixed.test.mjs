// THE CUSTOMER-PORTAL FIXES OF 21 SEP 2026 STAY FIXED (PRs #761, #771) — the root causes a source
// reading can see. Copy and layout items need a browser and belong to the nightly journey; the index
// of what is and is not guarded is docs/it/RECURRENCE_GUARDS_21_SEP_2026.md.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const SRC = new URL('../../src/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const walk = (d) => readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? walk(p) : (n.endsWith('.tsx') ? [p] : []);
});
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));

// Declared inside another component before 21 Sep and not part of that defect. A new entry here needs
// a reason; removing one when it is hoisted is the point.
const KNOWN = new Set([
  'components/me/PortalShell.tsx:NavButton',        // buttons, no typed state; hoist when next touched
  'components/visual/AnonymityFlow.tsx:Packet',     // decorative SVG, no input
  'components/visual/AnonymityFlow.tsx:Label',      // decorative SVG, no input
]);

test('item 3: no component is declared inside another component\'s render (it re-mounts every keystroke)', () => {
  // `Row` inside AccountSettings was a new component type per render, so React re-mounted the
  // <Input> under the customer's cursor and dropped keystrokes in Account Name.
  const found = [];
  for (const p of walk(SRC)) {
    const rel = p.slice(SRC.length).replace(/\\/g, '/');
    for (const m of code(readFileSync(p, 'utf8')).matchAll(/^[ \t]{2,}(?:const ([A-Z]\w*)\s*=\s*\(\{|function ([A-Z]\w*)\s*\(\{)/gm)) {
      found.push(`${rel}:${m[1] || m[2]}`);
    }
  }
  assert.deepEqual(found.filter((f) => !KNOWN.has(f)), [], 'hoist these to module scope');
});

test('item 10: the secondary button takes both colours from the theme palette', () => {
  const b = readFileSync(join(SRC, 'components', 'ui', 'button.tsx'), 'utf8');
  const sec = (b.match(/secondary:\s*'([^']*)'/) || [])[1] || '';
  assert.match(sec, /\bbg-secondary\b/);
  assert.match(sec, /\btext-secondary-foreground\b/);
  assert.doesNotMatch(sec, /bg-surf\b/, 'a marketing navy behind a theme-aware text colour was unreadable in one theme');
});

test('item 14: a wrong URL gets a bilingual page inside the site chrome, not the bare Next.js 404', () => {
  const p = join(SRC, 'app', '[locale]', 'not-found.tsx');
  assert.ok(existsSync(p), 'src/app/[locale]/not-found.tsx is gone');
  const s = readFileSync(p, 'utf8');
  assert.match(s, /ar:\s*\{[^}]*[؀-ۿ]/, 'the Arabic copy is missing');
  assert.match(s, /dir=\{/, 'the page no longer sets its direction');
});

test('#761 a customer who revealed a supplier sees "Reveal" lit, from the reveal itself', async () => {
  // rfqStageIdx reaches its last stage only when a supplier is HIRED, so a customer who had just paid
  // to reveal was shown the reveal step greyed out.
  // 5 Oct 2026: the rail is now the request tracker (requestTracker.ts); executed, not grepped.
  const { trackerOf } = await import('../../src/components/me/requestTracker.ts');
  const tr = trackerOf({ status: 'quoted' }, [{ revealed: true }, {}], 'en');
  assert.equal(tr.stages.find((x) => x.key === 'revealed').done, true, 'the reveal no longer lights its own stage');
  assert.equal(tr.stages.find((x) => x.key === 'done').done, false, 'a reveal is being claimed as a hire');
});
