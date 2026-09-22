// What a Resend delivery event writes onto the notifications row it is about (22 Sep 2026, it_engineer).
//
// MEASURED 22 Sep: 148 sent emails carried a provider_message_id and 0 carried a provider_status, so
// "sent" was the last word the estate had on any email. The column's CHECK
// (notifications_provider_status_known, every_whatsapp_says_whether_it_arrived.sql) allows Twilio's
// vocabulary only, so an email outcome is written in those words and the provider's own detail goes
// to provider_error_code:
//   email.delivery_delayed -> 'sending'      only onto a row with no status yet
//   email.delivered        -> 'delivered'    never over a final status
//   email.bounced          -> 'undelivered'  final; code 'bounce:<type>'
//   email.complained       -> 'delivered'    it arrived and the reader marked it spam; code 'complained'
//                                            but never onto an 'undelivered' row: a complaint landing
//                                            after a bounce would otherwise read the address as
//                                            reachable and overwrite 'bounce:permanent'.
// `onlyIf` is the PostgREST or-filter the update must also match, so a late event never moves a
// status backwards; null means the event is final and always applies. A bounce is the one event
// that overwrites anything: "it did not arrive" is the outcome that decides whether we mail again.
export type DeliveryOutcome = { status: 'sending' | 'delivered' | 'undelivered'; code: string | null; onlyIf: string | null };

export function deliveryOutcome(type: string, bounceType: string): DeliveryOutcome | null {
  const t = type.toLowerCase();
  if (t === 'email.delivery_delayed') return { status: 'sending', code: null, onlyIf: 'provider_status.is.null' };
  if (t === 'email.delivered') return { status: 'delivered', code: null, onlyIf: 'provider_status.is.null,provider_status.eq.sending' };
  if (t === 'email.bounced') return { status: 'undelivered', code: 'bounce:' + (bounceType.toLowerCase() || 'unknown'), onlyIf: null };
  if (t === 'email.complained') return { status: 'delivered', code: 'complained', onlyIf: 'provider_status.is.null,provider_status.eq.sending,provider_status.eq.delivered' };
  return null;
}
