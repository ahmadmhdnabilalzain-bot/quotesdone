// THE ONE SHAPE OF A WHATSAPP EXCHANGE ROW (30 Sep 2026, senior-hire audit, seat customer_support).
// wa_inbound writes the reply on the inbound's own wa_messages row, after the reply was produced, so
// created_at used to be the REPLY time and no first-reply time existed (case_review printed "not recorded").
// Every row now carries created_at = the moment the inbound arrived, and replied_at = the moment the
// reply was written, set only when the reply was actually sent. Tested by wa_row.test.ts.
export function waRow(receivedAt: string, row: Record<string, unknown>, now = new Date()) {
  return { created_at: receivedAt, ...row, replied_at: row.sent === true ? now.toISOString() : null };
}
