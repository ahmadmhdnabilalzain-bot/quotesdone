// customer_api — small rules about a request: the refusal of an unsaved insert, the edit window, the
// anonymous supplier letter, and the label form of a code.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).

// A DATABASE MESSAGE IS NOT AN ANSWER TO A CUSTOMER (customer-portal audit CP-17, 22 Sep 2026).
// create_inquiry answered a failed insert with `error: e1.message`, so a constraint name, a column
// name or a driver string was printed on the customer's screen where a sentence belongs. The class
// decides the status — class 23 is the database REFUSING the row (a 4xx), anything else is ours —
// and the real message goes to the log, where an engineer reads it.
// deno-lint-ignore no-explicit-any
export function inquiryNotSaved(err: any): [Record<string, unknown>, number] {
  const sqlstate = String(err?.code || '');
  console.error('create_inquiry insert refused', JSON.stringify({ sqlstate, message: String(err?.message || '').slice(0, 300) }));
  const refused = sqlstate.startsWith('23');
  return [{ ok: false, error: refused ? 'request_refused' : 'request_not_saved', code: refused ? 'request_refused' : 'request_not_saved',
    message: refused ? 'We could not accept that request. Please check what you entered and try again.' : 'We could not save your request just now. Nothing was sent — please try again in a moment.',
    message_ar: refused ? 'تعذّر قبول هذا الطلب. يُرجى مراجعة ما أدخلته والمحاولة مرة أخرى.' : 'تعذّر حفظ طلبك الآن. لم يُرسل شيء — يُرجى المحاولة بعد لحظات.' },
    refused ? 400 : 500];
}
// NO EDIT WINDOW (16 Nov 2026). The one-hour edit window that lived here is gone: public.fn_edit_inquiry revises a request
// until it is revealed, paid or closed (scripts/sql/a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told.sql),
// and my_inquiries' `editable` follows the same rule.
// Anonymised quote labels must stay alphabetic beyond 26 quotes. String.fromCharCode(65 + i)
// emits '[', '\\', ']' from the 27th, so a customer with 30 quotes saw "Supplier [" and the
// comparison report referenced a label that did not exist in their list.
export function supplierLabel(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }

export function labelize(s: string): string { return String(s || '').replace(/[-_]/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase()); }
