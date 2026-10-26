// The archived page carries the headers, the whole body and the attachment list, and an Arabic
// message renders in Arabic with nothing dropped. ZZ DEMO data only; no database is touched.
// Fonts come from the public brand bucket, so the render half needs SUPABASE_URL and is skipped
// without it; the document-shape half always runs.
//   SUPABASE_URL=https://<ref>.supabase.co deno test -A supabase/functions/conversation_archive/document.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { conversationDocument, type ConversationRow } from './document.ts';
import { renderPdf } from '../pdf_native/render.ts';

const base: ConversationRow = {
  source_table: 'inbound_messages', source_id: '999001', channel: 'email', direction: 'in',
  occurred_at: '2026-09-14T08:05:00Z', from_addr: 'zz.demo.customer@example.invalid', to_addr: 'info@quotesdone.com',
  cc: 'zz.demo.cc@example.invalid', subject: 'ZZ DEMO - fire alarm quotation', body: 'Line one.\n\nLine two of the ZZ DEMO email.',
  html: '<p>Line one.</p>', attachments: [{ filename: 'zz_demo_drawing.pdf' }], party_kind: 'company', party_id: null, inquiry_id: null,
};
const arabic: ConversationRow = { ...base, source_id: '999002', subject: 'ZZ DEMO - طلب عرض سعر لنظام إنذار الحريق',
  body: 'مرحبا، نرجو تزويدنا بعرض سعر لنظام إنذار الحريق في الطابق الأرضي.\nشكرا لكم.' };

Deno.test('the page names from, to, cc, date, subject, record and every attachment', () => {
  const d = conversationDocument(base);
  const kv = d.blocks.find((b: { t: string }) => b.t === 'kv').pairs as [string, string][];
  const m = Object.fromEntries(kv);
  assertEquals(m['From'], base.from_addr); assertEquals(m['To'], base.to_addr); assertEquals(m['Cc'], base.cc);
  assertEquals(m['Record'], 'inbound_messages:999001'); assertEquals(m['Date (Dubai)'].includes('12:05'), true);
  const text = JSON.stringify(d.blocks);
  assert(text.includes('Line two of the ZZ DEMO email.'), 'the whole body is on the page');
  assert(text.includes('zz_demo_drawing.pdf'), 'the attachment is listed');
  assertEquals(d.lang, 'en');
});

Deno.test('an Arabic message is laid out in Arabic', () => {
  const d = conversationDocument(arabic);
  assertEquals(d.lang, 'ar');
  assert(JSON.stringify(d.blocks).includes('من'), 'Arabic labels');
});

// Audit 22 Sep 2026, finding 5: the Arabic archive printed "Sept" and "Correspondence archive", and
// neither page carried the letterhead (so no licence line).
Deno.test('dates are "14 Sep 2026" / "14 سبتمبر 2026", the Arabic page has no English furniture, and both wear the letterhead', () => {
  const en = conversationDocument(base), ar = conversationDocument(arabic);
  assertEquals(en.date, '14 Sep 2026, 12:05');
  assertEquals(ar.date_ar, '14 سبتمبر 2026، 12:05');
  assertEquals(ar.control, 'أرشيف المراسلات');
  const arText = JSON.stringify([ar.blocks, ar.control, ar.date_ar]);
  assert(!/Sept|archive|received|email -/.test(arText), 'no English label on the Arabic page: ' + arText.slice(0, 200));
  assertEquals(en.options.letterhead, true); assertEquals(ar.options.letterhead, true);
});

// The suite runner grants no permissions, so env and net are asked for, not assumed.
const URL_ = Deno.permissions.querySync({ name: 'env', variable: 'SUPABASE_URL' }).state === 'granted'
  && Deno.permissions.querySync({ name: 'net' }).state === 'granted' ? Deno.env.get('SUPABASE_URL') : undefined;
Deno.test({ name: 'both render with the brand fonts and drop no character', ignore: !URL_, fn: async () => {
  const fetchBytes = async (p: string) => { try { const r = await fetch(`${URL_}/storage/v1/object/public/brand/${p}`); return r.ok ? new Uint8Array(await r.arrayBuffer()) : null; } catch { return null; } };
  for (const row of [base, arabic]) {
    const out = await renderPdf(conversationDocument(row), { fetchBytes });
    assert(out.ok, 'rendered');
    if (!out.ok) return;
    assertEquals(out.meta.glyphs_dropped, 0, `dropped: ${out.meta.glyphs_dropped_sample}`);
    if (row === arabic) assert(out.meta.fonts.arabic, 'the Arabic face was embedded');
    const dir = Deno.env.get('QD_PDF_OUT'); if (dir) await Deno.writeFile(`${dir}/${row.source_id}.pdf`, out.bytes);
  }
} });
