// supplier_api — what a registration hands fn_marketing_first_touch_record (marketing, 15 Nov 2026).
// Pure, so it is tested without a database (first_touch_payload.test.ts).
//
// The browser's kept tags (src/lib/firstTouch.ts) are sent as they are; anything else, null included, is sent as {}, so the
// routine always runs and records the opened invitation (leads.invite_clicked_at) when the browser kept nothing. Returning
// early on a missing touch is the cause of "marketing_first_touch has 0 rows" and must not come back.
export function firstTouchPayload(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw as Record<string, unknown> : {};
}

/** Why the routine recorded nothing, when that is worth a log line; null when recorded, or when there was simply no tag. */
export function firstTouchRefusal(data: unknown): string | null {
  if (!data || typeof data !== 'object') return null;
  const d = data as { ok?: boolean; recorded?: boolean; reason?: string; detail?: string };
  if (d.recorded !== false) return null;
  if (d.reason === 'no_utm' || d.reason === undefined) return null;   // an untagged registration with no opened invitation
  return String(d.reason) + (d.detail ? ': ' + d.detail : '');
}
