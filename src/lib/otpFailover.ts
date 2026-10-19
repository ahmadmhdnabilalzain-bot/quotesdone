import { useEffect, useRef } from 'react';
// AUTOMATIC SMS FAILOVER FOR A WHATSAPP CODE (it_engineer, 18 Oct 2026; review of #1432).
// After a phone code is sent, the screen asks the server at fixed times whether the WhatsApp message arrived.
// The server (kyc phone_failover, login_otp failover) reads Twilio's delivery status and sends the same code
// by SMS when it was undelivered, failed, or is still not delivered 45 s after the send. The times bracket
// that 45 s so the SMS goes within ~15 s of the deadline. `ping` resolves to the server's answer; an answer
// whose state is 'delivered', 'sent_sms' or 'nothing_to_do' stops the schedule (login_otp always answers
// {ok:true} with no state, so its schedule simply runs out). Returns a cancel function.
export const FAILOVER_PINGS_S = [15, 30, 47, 62];
const FINAL = new Set(['delivered', 'sent_sms', 'nothing_to_do']);
export function scheduleFailover(ping: () => Promise<{ state?: string } | null | undefined>, onSms?: () => void): () => void {
  let stopped = false;
  const timers = FAILOVER_PINGS_S.map((s) => setTimeout(async () => {
    if (stopped) return;
    const j = await ping().catch(() => null);
    if (stopped) return;
    if (j?.state === 'sent_sms') onSms?.();
    if (j?.state && FINAL.has(j.state)) cancel();
  }, s * 1000));
  function cancel() { stopped = true; timers.forEach(clearTimeout); }
  return cancel;
}

// One schedule per screen, cancelled when a new code is requested and when the screen unmounts.
export function useFailover() {
  const cancel = useRef<(() => void) | null>(null);
  useEffect(() => () => cancel.current?.(), []);
  return (ping: () => Promise<{ state?: string } | null | undefined>, onSms?: () => void) => {
    cancel.current?.();
    cancel.current = scheduleFailover(ping, onSms);
  };
}
