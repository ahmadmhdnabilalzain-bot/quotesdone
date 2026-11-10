// THE ONE SHAPE OF A WHATSAPP EXCHANGE ROW (30 Sep 2026, senior-hire audit, seat customer_support).
// wa_inbound writes the reply on the inbound's own wa_messages row, after the reply was produced, so
// created_at used to be the REPLY time and no first-reply time existed (case_review printed "not recorded").
// Every row now carries created_at = the moment the inbound arrived, and replied_at = the moment the
// reply was written, set only when the reply was actually sent. Tested by wa_row.test.ts.
export function waRow(receivedAt: string, row: Record<string, unknown>, now = new Date()) {
  return { created_at: receivedAt, ...row, replied_at: row.sent === true ? now.toISOString() : null };
}

// WHAT ARRIVED IS NAMED ON THE ROW, NOT ONLY COUNTED (it_engineer, 10 Nov 2026, channels audit). The arrival row carried "media": 1
// and the turn's row "media_count": 1, so a voice note, a drawing or a photo sent on WhatsApp was in no table: nothing could hear,
// read or show it again (no transcription exists on WhatsApp yet, media_in.ts). Each attachment's Twilio reference and declared
// type are kept; fetching it still needs our Twilio credentials (media.ts fetchTwilioMedia pins the host). At most five, as read.
// prevented by: the_whole_exchange.test.ts (the arrival row keeps a reference to every attachment).
export function mediaItems(media: { url: string; mime: string }[]): { url: string; mime: string }[] {
  return media.slice(0, 5).map((m) => ({ url: String(m.url).slice(0, 500), mime: String(m.mime || '').slice(0, 100) }));
}
