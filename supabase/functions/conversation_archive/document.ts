// conversation_archive/document.ts — one saved conversation message, as the input pdf_native's
// renderer takes. Pure: row in, document body out, so the test renders it without a database.
//
// The founder, 14 Sep 2026: "if the provider has one month history then we print a pdf copy of that
// email and keep it in our back up". The page carries what a court or an auditor would ask for:
// who wrote, to whom, copied to whom, when (Dubai time), the subject, the whole body and the list
// of attachments. A message with Arabic in it is laid out right to left with Arabic labels, because
// the renderer shapes Arabic only on that path.
import { hasAr } from '../pdf_native/render.ts';

export type ConversationRow = {
  source_table: string; source_id: string; channel: string; direction: string; occurred_at: string;
  from_addr: string | null; to_addr: string | null; cc: string | null; subject: string | null;
  body: string | null; html: string | null; attachments: unknown;
  party_kind: string | null; party_id: string | null; inquiry_id: string | null;
};

const EN = { from: 'From', to: 'To', cc: 'Cc', date: 'Date (Dubai)', subject: 'Subject', channel: 'Channel', direction: 'Direction',
  ref: 'Record', message: 'Message', attachments: 'Attachments', none: '(no text)', in: 'received', out: 'sent' };
const AR = { from: 'من', to: 'إلى', cc: 'نسخة إلى', date: 'التاريخ (دبي)', subject: 'الموضوع', channel: 'القناة', direction: 'الاتجاه',
  ref: 'السجل', message: 'الرسالة', attachments: 'المرفقات', none: '(لا يوجد نص)', in: 'وارد', out: 'صادر' };

export function stripHtml(h: string): string {
  return String(h || '')
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|tr|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/[ \t]+/g, ' ').replace(/\n\s*\n\s*\n+/g, '\n\n').trim();
}

function attachmentNames(a: unknown, ar = false): string[] {
  if (Array.isArray(a)) {
    return a.map((x) => {
      if (x && typeof x === 'object') { const o = x as Record<string, unknown>; return String(o.filename ?? o.name ?? o.path ?? o.bucket_path ?? JSON.stringify(o)); }
      return String(x);
    }).filter(Boolean);
  }
  if (a && typeof a === 'object' && typeof (a as { count?: unknown }).count === 'number') {
    const n = (a as { count: number }).count;
    // 22 Sep 2026 (DL-14): on an Arabic page this one line printed in English. It is a count and a
    // place, not a filename, so it is written in the page's language. The count precedes a noun that
    // is not "day", so no ar_days() form is involved.
    if (n <= 0) return [];
    return [ar ? `عدد المرفقات: ${n} — محفوظة مع مستندات المورّد أو الإيصالات`
               : `${n} attachment(s) - stored with the supplier or receipt documents`];
  }
  return [];
}

// Dubai time as "14 Sep 2026, 12:05" / "14 سبتمبر 2026، 12:05", built from numeric parts. The locale's
// own short month printed "Sept" (en-GB, current ICU) on BOTH pages, English on the Arabic one (audit of
// every document we issue, 22 Sep 2026, finding 5). Prevented by document.test.ts.
const MON_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MON_AR = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
export function dubaiTime(iso: string, lang: 'en' | 'ar' = 'en'): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso || '');
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(d).map((x) => [x.type, x.value]));
  const mon = (lang === 'ar' ? MON_AR : MON_EN)[Number(p.month) - 1];
  return `${p.day} ${mon} ${p.year}${lang === 'ar' ? '،' : ','} ${p.hour}:${p.minute}`;
}
const CHANNEL_AR: Record<string, string> = { email: 'البريد الإلكتروني', whatsapp: 'واتساب', sms: 'رسالة نصية', chat: 'المحادثة', portal: 'البوابة', voice: 'مكالمة صوتية' };

const esc = (s: unknown) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/**
 * THE LIGHTER COPY (it_engineer, 2 Nov 2026; review of #1797). A message the PDF renderer cannot draw inside the edge's
 * 2 s CPU cap is kept as ONE self-contained HTML file carrying the same fields, the whole text and the attachment list
 * as the PDF would - no fonts, no layout engine, linear in the text, so it always fits. Kept like the PDF (backups +
 * Dropbox, fn_conversation_archived); the sweep switches to it after ATTEMPTS_BEFORE_COPY failed attempts.
 */
export const ATTEMPTS_BEFORE_COPY = 3;
export function conversationHtml(r: ConversationRow): string {
  const text = (r.body && r.body.trim()) ? r.body : (r.html ? stripHtml(r.html) : '');
  const ar = hasAr(String(r.subject || '') + text);
  const L = ar ? AR : EN;
  const rows: [string, string][] = [[L.from, r.from_addr || '-'], [L.to, r.to_addr || '-'],
    [L.date, dubaiTime(r.occurred_at, ar ? 'ar' : 'en')], [L.channel, r.channel + ' - ' + (r.direction === 'out' ? L.out : L.in)]];
  if (r.cc) rows.push([L.cc, r.cc]);
  rows.push([L.ref, `${r.source_table}:${r.source_id}`], [L.subject, r.subject || '-']);
  const atts = attachmentNames(r.attachments, ar);
  return '<!doctype html><html lang="' + (ar ? 'ar' : 'en') + '" dir="' + (ar ? 'rtl' : 'ltr') + '"><head><meta charset="utf-8"><title>'
    + esc(r.subject || (r.channel + ' ' + r.direction)) + '</title></head><body>'
    + '<p>' + esc(ar ? 'أرشيف المراسلات - QuotesDone' : 'Correspondence archive - QuotesDone') + '</p><table>'
    + rows.map(([k, v]) => '<tr><th>' + esc(k) + '</th><td>' + esc(v) + '</td></tr>').join('') + '</table>'
    + '<h2>' + esc(L.message) + '</h2><pre style="white-space:pre-wrap">' + esc(text || L.none) + '</pre>'
    + (atts.length ? '<h2>' + esc(L.attachments) + '</h2><ul>' + atts.map((a) => '<li>' + esc(a) + '</li>').join('') + '</ul>' : '')
    + '</body></html>';
}

// deno-lint-ignore no-explicit-any
export function conversationDocument(r: ConversationRow): Record<string, any> {
  const text = (r.body && r.body.trim()) ? r.body : (r.html ? stripHtml(r.html) : '');
  const ar = hasAr(String(r.subject || '') + text);
  const L = ar ? AR : EN;
  const pairs: [string, string][] = [
    [L.from, r.from_addr || '-'], [L.to, r.to_addr || '-'],
    [L.date, dubaiTime(r.occurred_at, ar ? 'ar' : 'en')], [L.channel, (ar ? (CHANNEL_AR[String(r.channel).toLowerCase()] ?? r.channel) : r.channel) + ' - ' + (r.direction === 'out' ? L.out : L.in)],
  ];
  if (r.cc) pairs.push([L.cc, r.cc]);
  pairs.push([L.ref, `${r.source_table}:${r.source_id}`]);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [
    { t: 'kv', pairs },
    { t: 'h3', text: L.subject + ': ' + (r.subject || '-') },
    { t: 'h2', text: L.message },
  ];
  const paras = text.replace(/\r\n/g, '\n').split(/\n/).map((s) => s.trimEnd());
  let any = false;
  for (const p of paras) { if (p.trim()) { blocks.push({ t: 'p', text: p }); any = true; } else blocks.push({ t: 'space', h: 4 }); }
  if (!any) blocks.push({ t: 'p', text: L.none });
  const atts = attachmentNames(r.attachments, ar);
  if (atts.length) { blocks.push({ t: 'h2', text: L.attachments }); for (const a of atts) blocks.push({ t: 'li', text: a }); }
  return {
    lang: ar ? 'ar' : 'en',
    title: String(r.subject || (r.channel + ' ' + r.direction)).slice(0, 140),
    ref: `${r.source_table}:${r.source_id}`,
    date: dubaiTime(r.occurred_at, 'en'),
    date_ar: dubaiTime(r.occurred_at, 'ar'),
    control: ar ? 'أرشيف المراسلات' : 'Correspondence archive',
    blocks,
    // The letterhead is what prints the issuer's licence line (audit 22 Sep 2026, finding 5).
    options: { letterhead: true, strict_glyphs: false },
  };
}
