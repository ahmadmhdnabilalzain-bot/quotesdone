import { assertEquals } from 'jsr:@std/assert';
import { parseReviewOutput } from './seat_deliberation.ts';

Deno.test('a review reply is one JSON object, fenced or not', () => {
  assertEquals(parseReviewOutput('{"verdict":"approve","steelman_against":"x"}')?.verdict, 'approve');
  assertEquals(parseReviewOutput('```json\n{"verdict":"reject"}\n```')?.verdict, 'reject');
});

Deno.test('anything else is not a review: prose, an array, nothing', () => {
  assertEquals(parseReviewOutput('I approve this plan.'), null);
  assertEquals(parseReviewOutput('[{"verdict":"approve"}]'), null);
  assertEquals(parseReviewOutput(null), null);
});
