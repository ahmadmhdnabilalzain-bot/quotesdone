// What one Twilio ApprovalRequests answer says about a template (6 Oct 2026).
// Twilio's error body carries the HTTP code in `status`, and the old read (`j.whatsapp.status ||
// j.status`) stored "404" in messaging_template as if Meta had said it. Now:
//   404            -> 'missing' (the Content SID no longer exists; final, like 'rejected')
//   other non-2xx  -> 'error:http_<code>' (no verdict: the caller never stamps it)
//   2xx            -> the WhatsApp verdict, or 'unknown'
// The HTTP code always comes back as `http`, for messaging_template.last_http_status.
export function twilioVerdict(httpStatus: number, body: any): { status: string; reason: string | null; http: number } {
  if (httpStatus === 404) return { status: 'missing', reason: null, http: httpStatus };
  if (httpStatus < 200 || httpStatus > 299) return { status: `error:http_${httpStatus}`, reason: null, http: httpStatus };
  const st = body?.whatsapp?.status;
  return { status: typeof st === 'string' && st ? st : 'unknown', reason: body?.whatsapp?.rejection_reason || null, http: httpStatus };
}
