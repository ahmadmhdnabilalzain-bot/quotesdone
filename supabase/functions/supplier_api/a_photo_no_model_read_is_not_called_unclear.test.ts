// A photo or a scan that no model could read is not called unclear (customer_support, quote_extract audit 10 Nov 2026).
// Under the model hold every photographed quotation was answered "please send a clearer copy", which is untrue of a sharp
// photo: the reader was simply not available. readQuotationFile now says why it read nothing.
import { assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { readQuotationFile } from './quote_review_flow.ts';
import { clearerCopyAsk } from '../_shared/clearer_copy.ts';

// a 1x1 PNG: an image with no text layer, so only a model could read it
const PNG = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='), (c) => c.charCodeAt(0));

Deno.test('a photo the model could not reach says so; one it read too little of asks for a clearer copy', async () => {
  const held = await readQuotationFile(PNG, 'quote.png', 'image/png', [], undefined, () => Promise.resolve({ ok: false, text: '', why: 'model_hold' }));
  assertEquals([held.proposal, held.reason], [null, 'model_hold']);
  const thin = await readQuotationFile(PNG, 'quote.png', 'image/png', [], undefined, () => Promise.resolve({ ok: true, text: '' }));
  assertEquals(thin.reason, 'model_answer_too_thin');
  assertMatch(clearerCopyAsk('supplier', 'en', 'quote.png', true), /not available at the moment/);
  assertMatch(clearerCopyAsk('supplier', 'en', 'quote.png'), /clearer copy/);
});
