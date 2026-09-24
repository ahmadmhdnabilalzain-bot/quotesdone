// deno test --no-lock supabase/functions/pdf_native/the_supplier_list_renders.test.ts
// The founder's 18:00 supplier list (customer_support, 24 Sep 2026) is rendered from the blocks that
// fn_customer_support_campaign_list_tick builds (scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six.sql):
// h2, p, p, note, space, then ONE table of # / Company / Emirate / Language / Email. This renders that shape with
// 50 ZZ DEMO rows (the default daily cap), English and Arabic company names, with the options resilience_ping
// passes (letterhead, strict_glyphs false), and reads the text back: every row is on the PDF, on more than one page.
import { assert } from 'jsr:@std/assert@1';
import { renderPdf } from './render.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';

const FONTS = new URL('./fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => (/\.ttf$/.test(p) ? await Deno.readFile(new URL(p, FONTS)) : null);

Deno.test('the daily supplier list renders every row, across pages, English and Arabic names', async () => {
  const rows = Array.from({ length: 50 }, (_, i) => [String(i + 1),
    i % 5 === 0 ? 'ZZ DEMO مؤسسة التجربة ' + (i + 1) : 'ZZ DEMO Trading LLC ' + (i + 1),
    ['Dubai', 'Abu Dhabi', 'Sharjah', '-'][i % 4], i % 5 === 0 ? 'AR' : 'EN', 'zz***@example.invalid']);
  const blocks = [
    { t: 'h2', text: 'Suppliers to be invited on Monday 28 September 2026' },
    { t: 'p', text: 'The campaign is SWITCHED OFF (supplier_outreach_golive is false): NOTHING will be sent on Monday 28 September 2026. This is the list that WOULD be sent if it were on.' },
    { t: 'p', text: 'Today (Fri 25 Sep 2026): sent 0, bounced 0, unsubscribed 0, registered 0.' },
    { t: 'note', text: 'Selection: fn_supplier_invite_candidates(50), the sender\'s own; cap 50, eligible pool 17438. Emails are masked. Prepared by customer_support, by code.' },
    { t: 'space', h: 6 },
    { t: 'table', head: ['#', 'Company', 'Emirate', 'Language', 'Email'], widths: [0.06, 0.44, 0.14, 0.1, 0.26], rows },
  ];
  const r = await renderPdf({ title: 'Supplier campaign: OFF — would invite 50 supplier(s) on Mon 28 Sep', blocks,
    options: { letterhead: true, strict_glyphs: false } }, { fetchBytes });
  assert(r.ok, `refused: ${JSON.stringify((r as { body?: unknown }).body)}`);
  const pages = await pdfPages((r as { bytes: Uint8Array }).bytes);
  assert(pages.length >= 2, `50 rows fit on ${pages.length} page(s): the table did not break across pages as expected`);
  const text = pages.flatMap((p) => p.runs.map((x) => x.text)).join(' ');
  for (const n of [2, 25, 50]) assert(text.includes('Trading LLC ' + n), `row ${n} is missing from the PDF`);
  assert(text.includes('WOULD be sent') || text.includes('WOULD'), 'the switched-off sentence is missing');
});
