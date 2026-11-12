import * as React from 'react';
import { cn } from '@/lib/utils';
// An inset well (the input sits below the surface, a panel sits above it). Focus lights the edge
// teal with a soft halo; aria-invalid turns it danger. No black shadow.
// 16 PX AND 44 PX TALL TO A FINGER (12 Nov 2026, customer_support; browser perfection walk H3 and M20, founder ruling 1645: "a text
// box that is small"). Measured at 390x844: every box 15 px (`text-copy`) and 40 px tall; Safari on an iPhone zooms the page into
// any box under 16 px when it is focused, and 44 px is the floor for a thumb (ui/button.tsx). Under `pointer: coarse` only, as the
// button does, so the desktop's dense rows keep their size. Prevented by: scripts/checks/the_registration_form_answers_where_he_looks.test.mjs.
const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(({ className, type, ...props }, ref) => (
  <input
    type={type}
    ref={ref}
    className={cn(
      'flex h-10 w-full rounded-btn border border-input bg-navy-deep/55 px-3.5 py-2 text-copy pointer-coarse:min-h-11 pointer-coarse:text-[16px] text-foreground shadow-[inset_0_1px_3px_rgba(2,8,13,.6)] transition-[border-color,box-shadow] duration-base ease-expo placeholder:text-faint hover:border-line3 focus-visible:border-teal focus-visible:outline-hidden focus-visible:shadow-[inset_0_1px_3px_rgba(2,8,13,.6),0_0_0_3px_rgba(20,184,166,.18)] disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-danger file:border-0 file:bg-transparent file:text-small file:font-medium',
      className,
    )}
    {...props}
  />
));
Input.displayName = 'Input';
export { Input };
