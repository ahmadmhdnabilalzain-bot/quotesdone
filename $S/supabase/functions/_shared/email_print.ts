// THE COVERING EMAIL, PRINTED TO PDF — the fallback when a receipt arrives with no vendor file.
//
// The founder, 9 September 2026: "i wanna be able to click any record and see the actual invoice or
// receipt or email print pdf if none exist".
//
// WHAT THIS REPLACES, and why it was wrong. Both writers that book an expense — resend_inbound and
// the accountant's expense_sweep — stored `receipt.html`, text/html, when the email carried no
// attachment: the raw message body wrapped in a <pre>. Measured on production 9 Sep 2026, five of
// the nine booked receipts held exactly that. It is not a document you can hand anyone: it has no
// letterhead, no statement of which expense it evidences, and a browser is the only thing that can
// open it. An expense record's evidence should be a PDF like every other document this company
// issues.
//
// TWO THINGS IT IS CAREFUL ABOUT.
//
// 1. pdf_native NAMES ITS OWN PATH. The caller must use the `path` it RETURNS and never compose one,
//    because that returned value is the only string certain to name the object that was written.
//
// 2. THE INVISIBLE PADDING IS STRIPPED FIRST. Marketing receipts pad the inbox preview with
//    zero-width filler — measured: 138x U+2007 and 138x U+034F in one OpenRouter receipt, 122x
//    U+200C in a GoDaddy one. pdf_native drops any character its fonts cannot render and reports the
//    count, so left in place that filler puts a permanent 276 on `glyphs_dropped` and a REAL loss of
//    content would be indistinguishable from it. Stripped, a non-zero count is a finding.
//
// A NULL RETURN IS NEVER SILENT: it carries the reason, so the caller can archive the HTML instead
// and say in the record why the print is missing rather than pretending the email was never kept.

export type EmailPrintInput = {
  entryId?: number | null;
  vendor: string;
  amount: number | string;
  currency: string;
  chargedOn: string;
  sourceMsgId?: string | null;
  subject?: string | null;
  from?: string | null;
  to?: string | null;
  date?: string | null;
  /** the message text; the HTML body is only used when there is no text part */
  text?: string | null;
  html?: string | null;
  /** what the source email attached, if anything — named on the print so the two are never confused */
  attachmentNames?: string[];
};

export type EmailPrintResult =
  | { ok: true; path: string; name: string; contentType: 'application/pdf'; bytes: number; glyphsDropped: number }
  | { ok: false; reason: string };

const INVISIBLE = /[͏​‌‍⁠﻿­]/g;
const ODD_SPACE = /[   ]/g;

const stripHtml = (s: string) =>
  String(s || '')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<\/(p|div|tr|h\d)>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&#36;/g, '$').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/[ \t]+/g, ' ');

/** wrap tokens no line can fit (tracking links run to 400+ characters) so nothing is drawn off-page */
const softWrap = (s: string) =>
  s.split(/(\s+)/).map((t) => (t.length > 95 ? (t.match(/.{1,95}/g) || [t]).join(' ') : t)).join('');

export async function emailPrintPdf(
  // deno-lint-ignore no-explicit-any
  admin: any,
  supabaseUrl: string,
  input: EmailPrintInput,
): Promise<EmailPrintResult> {
  try {
    const { data: sr } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_to_pdf_native').maybeSingle();
    const secret = sr?.value as string | undefined;
    if (!secret) return { ok: false, reason: 'app_secrets.cred_fn_to_pdf_native is unreadable, so pdf_native could not be called' };

    const raw = String(input.text || '').trim() || stripHtml(String(input.html || ''));
    const clean = raw.replace(INVISIBLE, '').replace(ODD_SPACE, ' ');
    const paras = clean.replace(/\r/g, '').split(/\n{2,}/)
      .map((p) => softWrap(p.replace(/\n/g, ' ').replace(/[ \t]+/g, ' ').trim()))
      .filter((p) => p.length > 0).slice(0, 260);

    const names = (input.attachmentNames || []).filter(Boolean);
    const blocks: Record<string, unknown>[] = [
      { t: 'h2', text: 'Print of the covering email' },
      { t: 'kv', pairs: [
        ['Vendor', String(input.vendor)],
        ['Amount', `${input.amount} ${input.currency}`],
        ['Charged on', String(input.chargedOn)],
        ['Expense record', input.entryId ? `expense_entries #${input.entryId}` : 'pending'],
        ['Source message', String(input.sourceMsgId || '-')],
        ['From', String(input.from || '-')],
        ['To', String(input.to || '-')],
        ['Received', String(input.date || '-')],
        ['Subject', softWrap(String(input.subject || '-'))],
        ['Vendor file on the email', names.length ? names.join(', ') : 'none'],
      ] },
      { t: 'note', text: 'This is a PDF PRINT OF THE EMAIL, not the vendor\'s own invoice document. '
        + (names.length
          ? 'The source message carries the vendor file named above; it could not be stored as this record\'s document.'
          : 'The source message carried no vendor file at all.')
        + ' Long links in the original are wrapped across lines to fit the page; their text is unchanged.' },
      { t: 'h3', text: 'Message as received' },
      ...paras.map((text) => ({ t: 'p', text, size: 9.5 })),
    ];

    const r = await fetch(`${supabaseUrl}/functions/v1/pdf_native`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        __secret: secret,
        title: `Email print — ${input.vendor} ${input.amount} ${input.currency}`,
        date: String(input.chargedOn),
        bucket: 'receipt-files',
        folder: `receipts/email-prints/${String(input.chargedOn)}`,
        name: `email-print-${input.entryId ?? 'new'}-${String(input.vendor).replace(/[^\w.-]+/g, '_')}`,
        blocks,
        options: { letterhead: true },
      }),
      signal: AbortSignal.timeout(90_000),
    });
    const j = await r.json().catch(() => ({} as Record<string, unknown>));
    if (!r.ok || !j.ok || !j.path) {
      return { ok: false, reason: `pdf_native returned HTTP ${r.status} ${JSON.stringify(j).slice(0, 200)}` };
    }
    return {
      ok: true,
      path: String(j.path),                       // the path IT named, never one composed here
      name: `email-print-${input.entryId ?? 'new'}.pdf`,
      contentType: 'application/pdf',
      bytes: Number(j.bytes || 0),
      glyphsDropped: Number(j.glyphs_dropped || 0),
    };
  } catch (e) {
    return { ok: false, reason: 'email print threw: ' + String((e as Error)?.message || e).slice(0, 160) };
  }
}
