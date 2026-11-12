// node --test src/components/ui/button.test.mjs
// Browser perfection walk, 12 Nov 2026 (customer_support), H2; founder ruling 1645 ("there is no loading animation when you are
// submitting something"). Measured on production: 0 running animations during every submit. A busy Button now shows a turning
// ring, is disabled and says so (aria-busy). The .tsx is compiled here with the project's own TypeScript and rendered with React.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const req = createRequire(ROOT + 'package.json');
// TypeScript 7 has no JavaScript API, so the .tsx is compiled with the SWC that Next.js itself builds the site with.
const swc = req('next/dist/build/swc/index.js');
const url = (spec) => import.meta.resolve(spec);   // ESM resolution, as the bundler resolves it
async function loadButton() {
  const src = readFileSync(new URL('./button.tsx', import.meta.url), 'utf8');
  await swc.loadBindings?.();
  let js = (await swc.transform(src, { jsc: { parser: { syntax: 'typescript', tsx: true }, transform: { react: { runtime: 'automatic' } }, target: 'es2022' }, module: { type: 'es6' } })).code;
  js = js.replace(/from (["'])([^"']+)\1/g, (_m, _q, spec) => `from "${spec === '@/lib/utils' ? pathToFileURL(ROOT + 'src/lib/utils.ts').href : url(spec)}"`);
  return import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

test('a busy button shows a turning ring before its label, is disabled and is announced busy', async () => {
  const { Button } = await loadButton();
  const React = req('react'); const { renderToStaticMarkup } = req('react-dom/server');
  const busy = renderToStaticMarkup(React.createElement(Button, { busy: true, onClick: () => {} }, 'Submitting…'));
  assert.match(busy, /<button[^>]*disabled=""/, busy);
  assert.match(busy, /aria-busy="true"/);
  assert.match(busy, /<span data-busy="" aria-hidden="true" class="qd-spin"><\/span>Submitting…<\/button>/, 'the estate\'s one ring (.qd-spin) comes before the label');
  const idle = renderToStaticMarkup(React.createElement(Button, {}, 'Submit for approval'));
  assert.doesNotMatch(idle, /qd-spin|aria-busy|disabled=""/);
  const off = renderToStaticMarkup(React.createElement(Button, { disabled: true }, 'Submit'));
  assert.match(off, /disabled=""/); assert.doesNotMatch(off, /qd-spin/);
});
