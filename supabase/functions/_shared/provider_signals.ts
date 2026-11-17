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
//     signal: 63042 = the template is not usable YET (stay queued); 63016 = freeform outside the 24-hour window (a
//     retry never helps: it fails, and the founder fallback / email twin carries it). A rejection with NO code is not
//     guessed at either way: it is unknown and retried, at most UNKNOWN_RETRY_CAP times, then failed and surfaced.
//   * the transcriber is asked for ONE JSON object {"speech": boolean, "text": string}; `speech` is the model's own
//     structured answer. A reply that is not that object is unreadable, and the caller asks the user to try again —
//     never a placeholder guessed off the words.

import { parseJson } from './model_json.ts';
/** 63042: the template is not approved / usable YET — the row stays queued until it is. */
export const TWILIO_NOT_YET_CODES = new Set([63042]);
/** 63016: a freeform body outside the 24-hour customer window. Retrying never helps; it needs a template or email. */
export const TWILIO_OUTSIDE_WINDOW_CODES = new Set([63016]);
/** A rejection with no code is retried this many times, then treated as failed (and so surfaced). */
export const UNKNOWN_RETRY_CAP = 5;

export type TwilioVerdict = 'not_yet' | 'outside_window' | 'rejected' | 'unknown';
/** A failed Twilio send, judged by its structured code only. */
export function twilioVerdict(code: unknown): TwilioVerdict {
  const n = typeof code === 'number' ? code : (typeof code === 'string' && /^\d+$/.test(code) ? Number(code) : NaN);
  if (!Number.isFinite(n)) return 'unknown';
  if (TWILIO_NOT_YET_CODES.has(n)) return 'not_yet';
  if (TWILIO_OUTSIDE_WINDOW_CODES.has(n)) return 'outside_window';
  return 'rejected';
}

/** The transcriber's structured reply: {speech, text}. null = unreadable (the caller answers transcription_unreadable). */
export function readTranscript(content: unknown): { speech: boolean; text: string } | null {
  if (content && typeof content === 'object' && !Array.isArray(content)) content = JSON.stringify(content);   // a json response_format may arrive parsed
  const raw = typeof content === 'string' ? content : Array.isArray(content) ? content.map((p: { text?: string }) => p?.text || '').join('') : '';
  const o: unknown = parseJson(raw, { exact: true });
  if (!o || typeof o !== 'object' || typeof (o as { speech?: unknown }).speech !== 'boolean') return null;
  const t = (o as { text?: unknown }).text;
  if (t !== undefined && typeof t !== 'string') return null;
  const speech = (o as { speech: boolean }).speech;
  return { speech, text: speech ? String(t ?? '').trim() : '' };
}
