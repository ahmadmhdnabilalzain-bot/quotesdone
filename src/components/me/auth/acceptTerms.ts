// THE CUSTOMER'S "FINISH & CONTINUE": one press of kyc accept_terms (ProfileGate.tsx). Kept apart from the component so the one
// rule that matters is executed by a test, not read: the dashboard opens (onDone) ONLY when kyc answered ok.
//
// 13 Nov 2026, 08:47 (a ZZ DEMO customer): kyc's acceptance write was cancelled behind a rehearsal's table lock, kyc answered ok
// anyway, and the page opened the dashboard of a customer with no acceptance on record. kyc now reads the write back and answers
// 503 terms_not_recorded with the sentence in both languages (kyc/acceptance_write.ts); this keeps him on the step, re-enables
// the button and shows that sentence (errText renders a message that comes in both languages as it is).
export type Call = (fn: string, body: Record<string, unknown>, token: string) => Promise<Record<string, unknown> | null>;
export async function acceptTermsStep(o: {
  call: Call; token: string; marketing_consent: boolean; lang: string; onDone: () => void;
  setBusy: (b: string) => void; setMsg: (m: string) => void; errText: (j: unknown, lang: string, key?: string) => string;
  polls?: number; wait?: (ms: number) => Promise<void>;
}): Promise<boolean> {
  const wait = o.wait ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  o.setBusy('terms'); o.setMsg('');
  const j = await o.call('kyc', { action: 'accept_terms', marketing_consent: o.marketing_consent === true }, o.token).catch(() => null);
  if (!(j && j.ok)) { o.setBusy(''); o.setMsg(o.errText(j, o.lang, 'load_failed')); return false; }
  // THE CERTIFICATE LANDS AFTER THE ANSWER (kyc accept_terms renders the signed PDF in the background), and the account is
  // complete only once it has (terms_signed). Reading the state once left the customer on this unchanged form, with no word,
  // until they reloaded (measured 2 Nov 2026 by the sign-up walk: still here 60 s after "Finish & continue"). The button
  // stays on "Finishing…" while the state is asked again, every 2.5 s for up to two minutes.
  for (let i = 0; i < (o.polls ?? 48); i++) {
    const s = await o.call('kyc', { action: 'state' }, o.token).catch(() => null);
    if (s && s.terms_signed) break;
    await wait(2500);
  }
  o.setBusy(''); o.onDone(); return true;
}
