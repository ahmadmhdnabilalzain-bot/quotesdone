// A customer is never blocked from rating: stars alone pass, a comment is optional, a short comment
// is refused in words with a code the portal translates, and nothing here reaches a database.
import { assertEquals } from 'jsr:@std/assert@1';
import { COMMENT_MAX, parseRatingInput } from './rating_input.ts';

Deno.test('stars alone are a complete rating: no comment, empty comment and whitespace all pass with comment null', () => {
  for (const comment of [undefined, null, '', '   ', '\n\t']) {
    assertEquals(parseRatingInput({ rating: 4, comment }), { ok: true, rating: 4, comment: null });
  }
});

Deno.test('a comment of 10+ characters is kept, trimmed, and cut at the storage limit rather than refused', () => {
  assertEquals(parseRatingInput({ rating: 5, comment: '  Fast, tidy and on budget.  ' }),
    { ok: true, rating: 5, comment: 'Fast, tidy and on budget.' });
  const long = 'x'.repeat(COMMENT_MAX + 50);
  const r = parseRatingInput({ rating: 3, comment: long });
  assertEquals(r.ok && r.comment?.length, COMMENT_MAX);
});

Deno.test('a comment shorter than 10 characters is refused in words, with the code the portal translates', () => {
  const r = parseRatingInput({ rating: 5, comment: 'ok thanks' });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.code, 'review_comment_too_short');
    assertEquals(/at least 10 characters/.test(r.error), true);
  }
});

Deno.test('the rating must be an integer 1..5; anything else is rating_out_of_range, never a database error', () => {
  for (const rating of [0, 6, 2.5, -1, 'five', '', null, undefined, NaN]) {
    const r = parseRatingInput({ rating });
    assertEquals(r.ok, false, `rating ${String(rating)} should be refused`);
    if (!r.ok) assertEquals(r.code, 'rating_out_of_range');
  }
  assertEquals(parseRatingInput({ rating: '3' }), { ok: true, rating: 3, comment: null });
});

Deno.test('the rating is checked before the comment, so a bad star count is named first', () => {
  const r = parseRatingInput({ rating: 9, comment: 'x' });
  assertEquals(r.ok === false && r.code, 'rating_out_of_range');
});
