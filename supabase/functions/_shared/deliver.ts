// THE ONE DOOR AN EDGE FUNCTION USES TO SEND ANYTHING.
//
// Founder, 14 Sep 2026 (founder_instruction #207, verbatim): "always make sure things are in loop.
// nothing literally should ever be a one way communication".
//
// Until 14 Sep 2026 twelve call sites in eight files (seven functions and the shared hold desk,
// _shared/line_specs/workflow.ts) inserted into public.notifications themselves. Nothing tracked those rows: nobody learned whether they left, and nobody acted when they
// did not. Every one now calls this, which calls public.fn_customer_support_takes_delivery
// (scripts/sql/every_send_comes_back_to_whoever_asked.sql). Each row becomes a delivery.request from
// the seat that owns its type, customer_support queues it, and when the outbox is done with it the
// asking seat gets a delivery.result, re-checks it, and closes it or acts on it.
//
// scripts/checks/every_send_comes_back_to_whoever_asked.test.mjs fails if an edge function writes
// the outbox table by any other route.
//
// The row is the notifications row a caller would have inserted. It may add `dedupe_key` (the same
// request twice returns the first) and `requested_by` (to name the asking seat explicitly). Status,
// sender and requester of record are support's to set, never the caller's.

// deno-lint-ignore no-explicit-any
type Client = any;
export type DeliveryRow = Record<string, unknown>;
export interface Delivery {
  handoff_id: number | null;
  seat: string | null;
  status: string | null;
  notification_id: number | null;
  error: string | null;
}

/**
 * Ask customer_support to send one row or several. Returns the supabase-js shape ({ data, error })
 * so a caller that read `error` from the old insert reads it here unchanged. `error` is set when the
 * door refused the call or any row was not queued; the refusal is also on the handoff row, where the
 * watch reports it back to the asking seat, so a swallowed error here is still not a silent one.
 */
export async function requestDelivery(admin: Client, rowOrRows: DeliveryRow | DeliveryRow[]): Promise<{ data: Delivery[]; error: { message: string } | null }> {
  const rows = Array.isArray(rowOrRows) ? rowOrRows : [rowOrRows];
  if (!rows.length) return { data: [], error: null };
  const { data, error } = await admin.rpc('fn_customer_support_takes_delivery', { p_rows: rows });
  if (error) {
    const message = 'customer_support refused the delivery request: ' + String(error.message);
    console.error(message);
    return { data: [], error: { message } };
  }
  const out = (data ?? []) as Delivery[];
  const notQueued = out.filter((d) => d.error || d.notification_id == null);
  if (notQueued.length) {
    const message = notQueued.length + ' of ' + out.length + ' delivery request(s) not queued: '
      + notQueued.map((d) => '#' + d.handoff_id + ' ' + (d.error || 'nothing queued')).join('; ');
    console.error(message);
    return { data: out, error: { message } };
  }
  return { data: out, error: null };
}
