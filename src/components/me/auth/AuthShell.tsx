// @ts-nocheck
'use client';
import { Seal, Kicker } from '@/components/ui/sealed';
import { Check } from 'lucide-react';
import { t } from '../portalText';

// THE DOORWAY GOT THE SAME TREATMENT AS THE HOUSE.
//
// Signing in and finishing a profile were a single 400px card floating in the middle of an
// otherwise empty dark page — the same "extremely basic" the founder described about the portal
// behind it, on the screen a customer sees FIRST. This is the standard two-column product sign-in:
// the promise on one side, the form on the other, and on a phone just the form, because a phone
// has no room for a column of reassurance above the field you came to type in.
//
// The three lines are the product's actual terms, not marketing filler — free to post, anonymous
// until you choose, 3% only on a reveal. A customer deciding whether to sign up is deciding about
// exactly those three facts.
function AuthShell({ lang, children }) {
  const points = ['auth_p1', 'auth_p2', 'auth_p3'];
  return (
    <div className="mx-auto grid w-full max-w-[1080px] items-center gap-10 px-4 py-10 sm:px-5 md:min-h-[76vh] md:grid-cols-[1.05fr_minmax(380px,420px)] md:py-16">
      <div className="hidden md:block">
        <Kicker>{t(lang, 'auth_kicker')}</Kicker>
        <h2 className="mt-5 font-head text-h2 text-foreground">{t(lang, 'auth_h')}</h2>
        <p className="mt-4 max-w-[46ch] text-lead text-muted-foreground">{t(lang, 'auth_sub')}</p>
        {/* The promise, under the brand's own redaction bar: it seals and unseals on a loop. */}
        <p className="mt-6 font-head text-[17px] font-semibold tracking-snug text-foreground"><Seal loop className="max-w-full">{t(lang, 'auth_seal')}</Seal></p>
        <ol className="qd-stagger reveal-stagger mt-8 flex flex-col divide-y divide-border border-y border-border">
          {points.map((k, i) => (
            <li key={k} className="flex items-start gap-4 py-3.5">
              <span className="tabular mt-0.5 w-6 shrink-0 font-mono text-label text-primary">{String(i + 1).padStart(2, '0')}</span>
              <span className="text-copy leading-relaxed text-foreground/90">{t(lang, k)}</span>
              <Check className="ms-auto mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
            </li>
          ))}
        </ol>
      </div>
      <div className="w-full justify-self-center md:justify-self-end">{children}</div>
    </div>
  );
}
export { AuthShell };
