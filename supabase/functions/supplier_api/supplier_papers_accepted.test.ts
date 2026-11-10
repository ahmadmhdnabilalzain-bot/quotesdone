// A supplier's company profile or catalogue in Word or PowerPoint is accepted and read, never a 415.
// Stage-2 run f4294be8 (12 Oct 2026): process_docs passed SAFE_UPLOAD (PDF + images) for the profile, so
// every .docx/.pptx profile refused the WHOLE request with HTTP 415 and the licence sent with it was
// never read - 5 of 9 suppliers fell to reg_licence. This replays that input.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { sanitizeUpload, SAFE_UPLOAD, SAFE_SUPPLIER_PAPERS } from '../_shared/attachment.ts';
import { docxFixture, docmFixture, pptxFixture } from '../_shared/doc_read/office.fixtures.ts';
// The function is index.ts plus its modules (9 Nov 2026 split): read all of it, as the node checks do.
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const PPTX = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

Deno.test('a Word or PowerPoint profile passes the supplier-papers gate (and the old gate refused it)', async () => {
  for (const [bytes, mime] of [[await docxFixture(), DOCX], [await pptxFixture(), PPTX]] as const) {
    assertEquals(sanitizeUpload({ input: bytes, declaredMime: mime, filename: 'profile', allow: SAFE_UPLOAD }).ok, false);
    const r = sanitizeUpload({ input: bytes, declaredMime: mime, filename: 'profile', allow: SAFE_SUPPLIER_PAPERS });
    assert(r.ok, JSON.stringify(r));
  }
});

Deno.test('a macro document is still refused on the supplier-papers gate', async () => {
  assertEquals(sanitizeUpload({ input: await docmFixture(), declaredMime: DOCX, filename: 'profile.docx', allow: SAFE_SUPPLIER_PAPERS }).ok, false);
});

Deno.test('process_docs gates the profile and the catalogues with SAFE_SUPPLIER_PAPERS', async () => {
  const src = functionSource('supplier_api');
  assert(/filename: prof\.filename \|\| 'profile', allow: SAFE_SUPPLIER_PAPERS/.test(src), 'company profile gate');
  assert(/filename: c\.filename \|\| 'catalog', allow: SAFE_SUPPLIER_PAPERS/.test(src), 'catalogue gate');
});
