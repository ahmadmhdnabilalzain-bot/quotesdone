// provider_signals — what a provider TOLD us, read from its structured fields, never from its free text.
// Seat: customer_support. 23 Sep 2026, founder_instruction 886-903 (decision points send_whatsapp.pending_template,
// transcribe.no_speech).
//
// BEFORE:
//   * send_whatsapp decided "the template is awaiting Meta's approval, keep the row queued" by a regex over Twilio's
//     error MESSAGE (/approv|not (yet )?approved|template.*(pending|invalid|not found)|63016|63042/) — English prose
//     Twilio may reword at any time, read for its meaning.
//   * transcribe decided "the audio held no speech" by a regex over the model's transcript
//     (/^(no speech|silence|inaudible|no audio|blank|empty)$/) — so a caller who SAID "silence" got an empty result.
// NOW:
//   * Twilio returns a numeric `code` beside its message on every rejection (its REST error object). The code is the
//     signal; the codes that mean "not deliverable YET, keep it queued" are the two the old regex already named.
//     A rejection that carries NO code is not guessed at either way: it is unknown, and the row is retried.
//   * the transcriber is asked for ONE JSON object {"speech": boolean, "text": string}; `speech` is the model's own
//     structured answer. A reply that is not that object is unreadable, and the caller asks the user to try again —
//     never a placeholder guessed off the words.

/** Twilio error codes after which the WhatsApp row stays queued (the template is not deliverable yet). */
export const TWILIO_NOT_YET_CODES = new Set([63016, 63042]);

export type TwilioVerdict = 'not_yet' | 'rejected' | 'unknown';
/** A failed Twilio send, judged by its structured code only. */
export function twilioVerdict(code: unknown): TwilioVerdict {
  const n = typeof code === 'number' ? code : (typeof code === 'string' && /^\d+$/.test(code) ? Number(code) : NaN);
  if (!Number.isFinite(n)) return 'unknown';
  return TWILIO_NOT_YET_CODES.has(n) ? 'not_yet' : 'rejected';
}

/** The transcriber's structured reply: {speech, text}. null = unreadable (the caller answers transcription_unreadable). */
export function readTranscript(content: unknown): { speech: boolean; text: string } | null {
  const raw = typeof content === 'string' ? content : Array.isArray(content) ? content.map((p: { text?: string }) => p?.text || '').join('') : '';
  const m = raw.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  let o: unknown;
  try { o = JSON.parse(m ? m[1] : raw.trim()); } catch (_e) { return null; }
  if (!o || typeof o !== 'object' || typeof (o as { speech?: unknown }).speech !== 'boolean') return null;
  const t = (o as { text?: unknown }).text;
  if (t !== undefined && typeof t !== 'string') return null;
  const speech = (o as { speech: boolean }).speech;
  return { speech, text: speech ? String(t ?? '').trim() : '' };
}
