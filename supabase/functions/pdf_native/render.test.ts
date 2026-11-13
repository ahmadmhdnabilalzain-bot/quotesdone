// render.test.ts - a word wider than its column is broken, never drawn past the edge.
// Run: deno test supabase/functions/pdf_native/render.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { wrapWords } from './render.ts';

const len = (s: string) => s.length;   // one unit per character: the logic, not the font

Deno.test('the signed-terms SHA-256 (64 chars) fits a 20-char cell, every character kept in order', () => {
  const hash = '94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420aa11bb22';
  const out = wrapWords(hash, len, 20);
  assert(out.every((l) => l.length <= 20), JSON.stringify(out));
  assertEquals(out.join(''), hash);
});

Deno.test('ordinary text still wraps on spaces', () => {
  assertEquals(wrapWords('alpha beta gamma delta', len, 11), ['alpha beta', 'gamma delta']);
  assertEquals(wrapWords('', len, 10), ['']);
});

// 13 Nov 2026 (customer_support): an image block was never drawn. safeDeep copied the block key by key, the picture's
// Uint8Array became a plain object, pdf-lib refused it, and the page showed nothing where the picture belonged.
Deno.test('an image block is embedded and drawn on the page', async () => {
  const { renderPdf } = await import('./render.ts');
  // a 1x1 PNG
  const png = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='), (c) => c.charCodeAt(0));
  const r = await renderPdf({ title: 'ZZ DEMO picture', blocks: [{ t: 'p', text: 'ZZ DEMO' }, { t: 'image', bytes: png, kind: 'png', w: 100 }], options: { letterhead: false } }, { fetchBytes: () => Promise.resolve(null) });
  assert(r.ok);
  const raw = new TextDecoder('latin1').decode(r.bytes);
  assert(/\/Subtype\s*\/Image/.test(raw), 'the PDF holds no image object');
});
