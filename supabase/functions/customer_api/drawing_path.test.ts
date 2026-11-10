// M1 of the 10 Nov 2026 security checklist audit: create_inquiry attaches a drawing only when the path is one of the
// calling customer's own uploads (drawings/<customer id>/...). Before the fix it wrote any path from the request body,
// and my_inquiries signed it back. Ids below are ZZ DEMO shapes, not real customers.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ownDrawingPath } from './drawing_path.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const ME = '0b0b0b0b-zzde-mo00-0000-000000000001';
const OTHER = '0b0b0b0b-zzde-mo00-0000-000000000002';

Deno.test('no drawing is no drawing', () => {
  for (const v of [undefined, null, '', 0, false]) assertEquals(ownDrawingPath(ME, v), { ok: true, path: null });
});

Deno.test('the caller\'s own upload is attached as given', () => {
  const p = `drawings/${ME}/1784642799037_ZZDEMO_plan.pdf`;
  assertEquals(ownDrawingPath(ME, p), { ok: true, path: p });
});

Deno.test('another customer\'s upload, a redacted page or a path outside the prefix is refused', () => {
  for (const p of [
    `drawings/${OTHER}/1784642799037_ZZDEMO_plan.pdf`,     // the IDOR itself
    `drawings/${ME}`, `drawings/${ME}/`,                 // the prefix alone names no file
    `drawings/${ME}/../${OTHER}/1_plan.pdf`,             // a step out of the prefix
    `drawings/${ME}//x.pdf`, `drawings/${ME}/a\\b.pdf`, `drawings/${ME}/a\u0000.pdf`,
    'redacted/1b1b1b1b-0000-0000-0000-000000000000/page_p1.jpg',
    `/drawings/${ME}/1_plan.pdf`, `refphoto/${ME}/1.jpg`,
    `drawings/${ME}/` + 'x'.repeat(600),
  ]) assertEquals(ownDrawingPath(ME, p), { ok: false }, p);
  // a prefix match on a shorter id must not pass: drawings/12/ is not drawings/1/
  assertEquals(ownDrawingPath('1', 'drawings/12/1_plan.pdf'), { ok: false });
  assertEquals(ownDrawingPath('', 'drawings//1_plan.pdf'), { ok: false });
});

Deno.test('create_inquiry refuses a drawing path that is not the caller\'s own, before it is written', () => {
  const src = functionSource('customer_api');
  const start = src.indexOf("if (action === 'create_inquiry')");
  assert(start >= 0, 'create_inquiry handler not found');
  const body = src.slice(start);
  const check = body.search(/ownDrawingPath\(String\(cust\.id\),\s*drawing\?\.drawing_file_path\)/);
  const refuse = body.search(/if \(!own\.ok\) return J\(\{ error: 'drawing_not_yours'/);
  const write = body.search(/drawing_file_path: drawingPath/);
  assert(check >= 0, 'create_inquiry must pass the body drawing path through ownDrawingPath with the caller\'s customers.id');
  assert(refuse > check, 'create_inquiry must refuse (403 drawing_not_yours) when the path is not the caller\'s own');
  assert(write > refuse, 'the refusal must come before the path is written onto the inquiry');
  assert(!/const drawingPath = drawing\?\.drawing_file_path \?/.test(body), 'the body path must not be copied verbatim again');
});
