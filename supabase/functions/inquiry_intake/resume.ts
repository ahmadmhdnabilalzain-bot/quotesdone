// A HALF-FINISHED REQUEST CHAT IS RESUMED ON ANY RETURN (sales_engineer, CUSTOMER_W2, 16 Nov 2026; holes/CUSTOMER.md item 7).
// Before: the draft's id lived only in the browser (src/components/me/NewRequest.tsx React state) and the server resumed a
// draft only when the client sent intake_id, so a reload, another tab or his phone started a blank chat and he was asked
// everything again; a complete draft he never sent was expired at 30 days with nothing said.
// Now the server finds his newest open draft by his signed-in address: `resume` returns it with its conversation, and a first
// message with no intake_id continues it unless he asked for a fresh request (`fresh`). The nudges at 24 and 72 hours are
// public.fn_sales_engineer_nudges_unfinished_requests (scripts/sql/an_unfinished_request_chat_is_kept_and_he_is_nudged_at_a_day_and_three_days.sql).
// prevented by: inquiry_intake/a_half_finished_request_is_resumed_on_any_return.test.ts
// deno-lint-ignore-file no-explicit-any

/** A draft is open for resuming for as long as the abandoned-intake duty leaves it open (decision_policy intake_abandoned_days). */
export const RESUME_DAYS = 30;
export const OPEN_STATUSES = ['needs_info', 'ready'] as const;

export type DraftRow = { id: string; status?: string | null; updated_at?: string | null; created_at?: string | null; turns?: any[] | null };

/** Open: still collecting or complete-but-unsent, he said something, and touched inside the window. */
export function isOpenDraft(row: DraftRow, now: number = Date.now(), days: number = RESUME_DAYS): boolean {
  if (!row || !(OPEN_STATUSES as readonly string[]).includes(String(row.status || ''))) return false;
  const turns = Array.isArray(row.turns) ? row.turns : [];
  if (!turns.some((t) => t && t.role === 'user' && String(t.text || '').trim())) return false;
  const at = Date.parse(String(row.updated_at || row.created_at || ''));
  return Number.isFinite(at) && now - at < days * 86400e3;
}

/** His newest open draft, or null. */
export function newestOpenDraft<T extends DraftRow>(rows: T[] | null | undefined, now: number = Date.now(), days: number = RESUME_DAYS): T | null {
  const open = (rows || []).filter((r) => isOpenDraft(r, now, days));
  open.sort((a, b) => Date.parse(String(b.updated_at || b.created_at || '')) - Date.parse(String(a.updated_at || a.created_at || '')));
  return open[0] ?? null;
}

/** The conversation as the request screen shows it: his messages and the sales engineer's replies, nothing internal. */
export function transcriptOf(turns: any[] | null | undefined): { role: 'user' | 'assistant'; text: string }[] {
  return (Array.isArray(turns) ? turns : [])
    .filter((t) => t && (t.role === 'user' || t.role === 'assistant') && String(t.text || '').trim())
    .map((t) => ({ role: t.role, text: String(t.text).slice(0, 4000) }))
    .slice(-100);
}
