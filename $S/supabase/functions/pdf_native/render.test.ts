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
