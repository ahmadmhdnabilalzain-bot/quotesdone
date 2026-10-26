import { assertEquals } from 'jsr:@std/assert@1';
import { revealDescriptorSuffix, DESCRIPTOR_PREFIX, SUFFIX_MAX } from './statement_descriptor.ts';

Deno.test('the reveal suffix fits the 22-character card statement line after the account prefix', () => {
  for (const [job, want] of [['QD-12', 'REVEAL 12'], ['104', 'REVEAL 104'], ['1042', 'REVEAL1042'], ['QD-10423', 'RV 10423'],
                             ['1A2B3C4D', 'RV1A2B3C4D'], ["9'*<x>", 'REVEAL 9X'], ['', 'REVEAL']] as const) {
    const s = revealDescriptorSuffix(job);
    assertEquals(s, want);
    assertEquals((DESCRIPTOR_PREFIX + '* ' + s).length <= 22, true);
    assertEquals(/^[A-Z0-9 ]+$/.test(s) && s.length <= SUFFIX_MAX, true);
  }
});
