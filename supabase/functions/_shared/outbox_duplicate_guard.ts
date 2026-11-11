// _shared/outbox_duplicate_guard.ts — the same message to the same person is sent once (it_engineer, 11 Nov 2026).
//
// Founder ruling 1631 (11 Nov 2026, "extremely important"): every agent reads the history before it sends anything,
// including notifications, and "even an automatic notification (e.g. a new code) checks the history, in case a bug is
// sending it again". Code decides this, not a model: it is a comparison, and it must hold when no model is up.
//
// MEASURED on production (notifications, 30 days to 11 Nov 2026, ZZ DEMO and example.invalid excluded): 731 rows, 0 of them
// carrying a dedupe_key (the unique index notifications_dedupe_key_uidx exists and nobody fills it). 129 rows repeated an
// earlier row's recipient, channel, subject and body within 10 minutes, every one a supplier_invite_seed (the inbox-
// placement seed list, requested twice on 10 Nov at 21:30:57 and 21:31:39, 42 s apart): 123 were cancelled by hand and
// 6 were SENT a second time. Nothing in send_outbox or send_whatsapp compared a row with what had just gone to that person.
//
// THE RULE: a row whose channel, recipient, type, subject and body equal a row that was sent (or is being sent) to the
// same person within the window is not sent. It is marked cancelled with the earlier row named, counted, and raised as an
// it_engineer finding by the caller. The window is the setting outbox_duplicate_window_min (default 10). Text that differs
// (a new sign-in code, a new quote number) is never a duplicate. The insert-time twin of this guard is the trigger in
// scripts/sql/notifications_refuse_the_same_message_to_the_same_person_within_the_window.sql (pending).
// prevented by: _shared/outbox_duplicate_guard.test.ts

export const DEFAULT_WINDOW_MIN = 10;

export interface OutboxRow {
  id: number | string; channel?: string | null; type?: string | null; to_email?: string | null; to_phone?: string | null;
  subject?: string | null; body?: string | null; created_at?: string | null; sent_at?: string | null; status?: string | null;
}

const fold = (s: unknown) => String(s ?? '').trim().toLowerCase();
const phoneTail = (s: unknown) => String(s ?? '').replace(/[^0-9]/g, '').slice(-9);
const text = (s: unknown) => String(s ?? '').replace(/\s+/g, ' ').trim();

/** Who it goes to: the folded email, else the last nine digits of the number (the estate's phone identity). */
export function recipientOf(r: OutboxRow): string {
  const e = fold(r.to_email);
  if (e) return 'e:' + e;
  const p = phoneTail(r.to_phone);
  return p ? 'p:' + p : '';
}

/** Two rows are the same message when this key is equal. '' (no recipient) is never compared. */
export function messageKey(r: OutboxRow): string {
  const who = recipientOf(r);
  if (!who) return '';
  return [fold(r.channel) || 'email', who, fold(r.type), text(r.subject), text(r.body)].join('\u0001');
}

const at = (r: OutboxRow) => Date.parse(String(r.sent_at ?? r.created_at ?? '')) || 0;

/** The earlier row this one repeats within the window, or null. `recent` holds rows already sent or being sent. */
export function duplicateOf(row: OutboxRow, recent: readonly OutboxRow[], windowMin = DEFAULT_WINDOW_MIN, now = Date.now()): OutboxRow | null {
  const key = messageKey(row);
  if (!key) return null;
  const since = now - Math.max(1, windowMin) * 60_000;
  let hit: OutboxRow | null = null;
  for (const r of recent) {
    if (String(r.id) === String(row.id)) continue;
    if (at(r) < since) continue;
    if (messageKey(r) !== key) continue;
    if (!hit || at(r) > at(hit)) hit = r;
  }
  return hit;
}

/** The note written on a refused row. */
export function duplicateNote(earlier: OutboxRow, now = Date.now()): string {
  const s = Math.max(0, Math.round((now - at(earlier)) / 1000));
  return `duplicate: the same message to the same person as notification #${earlier.id}, ${s} s earlier; not sent `
    + '(outbox duplicate guard, founder ruling 1631)';
}

/** The window from a setting value ('' or junk: the default). */
export const windowFrom = (v: unknown) => { const n = parseInt(String(v ?? ''), 10); return Number.isFinite(n) && n > 0 ? Math.min(n, 24 * 60) : DEFAULT_WINDOW_MIN; };

/** Rows sent (or being sent) to these recipients inside the window, read once per run. A failed read returns null, and the
 *  caller then sends as before (an unreadable history must not stop the outbox), recording that it could not check. */
// deno-lint-ignore no-explicit-any
export async function recentSends(admin: any, rows: readonly OutboxRow[], windowMin: number): Promise<OutboxRow[] | null> {
  const emails = [...new Set(rows.map((r) => String(r.to_email ?? '').trim()).filter(Boolean))];
  const phones = [...new Set(rows.map((r) => String(r.to_phone ?? '').trim()).filter(Boolean))];
  if (!emails.length && !phones.length) return [];
  const since = new Date(Date.now() - windowMin * 60_000).toISOString();
  const cols = 'id,channel,type,to_email,to_phone,subject,body,created_at,sent_at,status';
  const out: OutboxRow[] = [];
  try {
    for (const [col, vals] of [['to_email', emails], ['to_phone', phones]] as const) {
      if (!vals.length) continue;
      const { data, error } = await admin.from('notifications').select(cols).in(col, vals).in('status', ['sent', 'sending'])
        .gte('created_at', since).limit(1000);
      if (error) return null;
      out.push(...((data ?? []) as OutboxRow[]));
    }
  } catch (_e) { return null; }
  return out;
}
