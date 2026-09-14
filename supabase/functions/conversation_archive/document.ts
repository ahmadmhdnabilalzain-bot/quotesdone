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

function attachmentNames(a: unknown): string[] {
  if (Array.isArray(a)) {
    return a.map((x) => {
      if (x && typeof x === 'object') { const o = x as Record<string, unknown>; return String(o.filename ?? o.name ?? o.path ?? o.bucket_path ?? JSON.stringify(o)); }
      return String(x);
    }).filter(Boolean);
  }
  if (a && typeof a === 'object' && typeof (a as { count?: unknown }).count === 'number') {
    const n = (a as { count: number }).count;
    return n > 0 ? [`${n} attachment(s) - stored with the supplier or receipt documents`] : [];
  }
  return [];
}

export function dubaiTime(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso || '');
  return d.toLocaleString('en-GB', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });
}

// deno-lint-ignore no-explicit-any
export function conversationDocument(r: ConversationRow): Record<string, any> {
  const text = (r.body && r.body.trim()) ? r.body : (r.html ? stripHtml(r.html) : '');
  const ar = hasAr(String(r.subject || '') + text);
  const L = ar ? AR : EN;
  const pairs: [string, string][] = [
    [L.from, r.from_addr || '-'], [L.to, r.to_addr || '-'],
    [L.date, dubaiTime(r.occurred_at)], [L.channel, r.channel + ' - ' + (r.direction === 'out' ? L.out : L.in)],
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
  const atts = attachmentNames(r.attachments);
  if (atts.length) { blocks.push({ t: 'h2', text: L.attachments }); for (const a of atts) blocks.push({ t: 'li', text: a }); }
  return {
    lang: ar ? 'ar' : 'en',
    title: String(r.subject || (r.channel + ' ' + r.direction)).slice(0, 140),
    ref: `${r.source_table}:${r.source_id}`,
    date: dubaiTime(r.occurred_at),
    date_ar: dubaiTime(r.occurred_at),
    control: 'Correspondence archive',
    blocks,
    options: { strict_glyphs: false },
  };
}
