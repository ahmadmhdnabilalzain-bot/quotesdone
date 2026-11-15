// THE DATE PRINTED ON A SUPPLIER'S QUOTATION, as a calendar day (sales_engineer, 15 Nov 2026; founder ruling, ledger 1697:
// "Quotation validity depends on what the supplier mentions in his quotation. No specific period").
//
// A validity the supplier states as a period ("valid 30 days", "30 days from date") is counted from the quotation's own date;
// public.fn_quote_validity_until does that in the database from quotes.quotation_date, and from the day we received the
// quotation when this is NULL. This turns the date as written (read by quote_extract or the terms reader) into that column:
// day first for numeric dates, as written in the UAE; English or Arabic month names; Arabic-Indic digits. Anything else is
// NULL, never a guess, and so is a date after tomorrow in Dubai: a quotation is not issued in the future, so such a date is a
// misreading (a delivery date, a US-style 11/12), and counting a validity from it would lengthen it.
import { parseDate } from './document_expiry/dates.ts';

const AR_MONTH: [RegExp, string][] = [
  [/يناير/g, 'Jan'], [/فبراير/g, 'Feb'], [/مارس/g, 'Mar'], [/[أاإ]بريل/g, 'Apr'], [/مايو/g, 'May'], [/يونيو/g, 'Jun'],
  [/يوليو/g, 'Jul'], [/[أا]غسطس/g, 'Aug'], [/سبتمبر/g, 'Sep'], [/[أا]كتوبر/g, 'Oct'], [/نوفمبر/g, 'Nov'], [/ديسمبر/g, 'Dec'],
];

/** The Dubai calendar day of an instant, as YYYY-MM-DD. */
export const dubaiDay = (t: Date): string => new Date(t.getTime() + 4 * 3600e3).toISOString().slice(0, 10);

/** YYYY-MM-DD for the date a quotation prints, or null when it prints none we can read for certain. */
export function quotationDateOf(raw: unknown, now: Date = new Date()): string | null {
  let s = String(raw ?? '').trim().slice(0, 80);
  if (!s) return null;
  s = s.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6F0));
  for (const [re, en] of AR_MONTH) s = s.replace(re, ' ' + en + ' ');
  s = s.replace(/\s+/g, ' ');
  const d = parseDate(s);
  if (!d) return null;
  const tomorrow = dubaiDay(new Date(now.getTime() + 86400e3));
  return d <= tomorrow ? d : null;
}
