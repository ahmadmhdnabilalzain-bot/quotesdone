import * as React from 'react';
import { Slot } from '@radix-ui/react-slot';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

// Sealed buttons. Filled variants are lit from within (.qd-hoverlit follows the pointer via
// ui/pointer-light) and wear the brand elevation; nothing casts a black shadow.
// `reveal` is gold and exists for ONE action: unsealing a supplier's identity (the 3% reveal).
// Using it anywhere else breaks the brand rule that gold only ever marks a reveal or a done state.
const buttonVariants = cva(
  'qd-hoverlit inline-flex select-none items-center justify-center gap-2 whitespace-nowrap rounded-btn font-medium transition-[transform,background-color,border-color,box-shadow,color] duration-base ease-expo active:scale-[.97] focus-visible:outline-hidden focus-visible:shadow-ring disabled:pointer-events-none disabled:opacity-45 motion-reduce:active:scale-100 [&_svg]:size-4 [&_svg]:shrink-0',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground shadow-e1 hover:bg-[#1ED0BC] hover:shadow-glow-teal',
        reveal: 'bg-linear-to-b from-gold-light to-gold text-[#2A1F05] font-semibold shadow-e1 hover:shadow-glow-gold',
        secondary: 'border border-border bg-secondary text-secondary-foreground shadow-e1 hover:bg-secondary/80',
        outline: 'border border-line2 bg-transparent text-foreground shadow-key hover:border-teal hover:text-teal-light',
        ghost: 'text-muted hover:bg-teal-light/6 hover:text-foreground',
        destructive: 'bg-danger text-navy shadow-e1 hover:bg-danger/90',
        link: 'text-teal-light underline-offset-4 hover:underline active:scale-100',
      },
      // EVERY BUTTON IS AT LEAST 44x44 TO A FINGER (22 Sep 2026, audit SP-M-01).
      //
      // MEASURED on the supplier portal on a phone: 53 buttons were 32px tall (`sm`, h-8) and five
      // about 24px; the language switch came out 44x32 and the theme toggle 37x32. WCAG 2.5.5 asks
      // for 44 and 2.5.8 for 24, and a 32px control is a miss on a 6-inch screen on either reading.
      //
      // The 44 is applied UNDER `pointer: coarse` only, and that is the whole point. The rule exists
      // for a fingertip; a mouse hits 32px exactly. Raising `sm` to h-11 outright would re-lay-out
      // every dense row in the customer portal, the OS dashboard and the marketing site — none of
      // which this audit looked at — to fix a defect none of their desktop users have.
      //
      // NOT a `::after` hit area, which is the usual trick and is wrong here: `.qd-hoverlit`, on
      // every one of these buttons, sets `overflow:hidden` for its pointer-following glow
      // (globals.css), so a pseudo-element larger than the button is clipped away and the target
      // does not grow at all. The box itself has to be the target.
      size: {
        sm: 'h-8 px-3 text-small pointer-coarse:min-h-11',
        default: 'h-10 px-4 text-copy pointer-coarse:min-h-11',
        lg: 'h-12 px-6 text-copy',
        xl: 'h-14 rounded-panel px-8 text-[16px]',
        icon: 'h-10 w-10 pointer-coarse:min-h-11 pointer-coarse:min-w-11',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  },
);
// A PRESS THAT IS WORKING SHOWS IT IS WORKING (12 Nov 2026, customer_support; browser perfection walk H2, founder ruling 1645:
// "there is no loading animation when you are submitting something"). Measured on production at 390x844: 0 running animations
// during every submit, 1.1-10.1 s each; only the words changed. `busy` puts a turning ring before the label, disables the button
// (so a second press sends nothing), and says so to a screen reader (aria-busy). The ring is the estate's one ring, `.qd-spin`
// (ui/busy.tsx Spinner, globals.css; it stands still under prefers-reduced-motion), drawn here because busy.tsx imports Button.
// Prevented by: src/components/ui/button.test.mjs.
export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> { asChild?: boolean; busy?: boolean; }
const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(({ className, variant, size, asChild = false, busy = false, disabled, children, ...props }, ref) => {
  const Comp = asChild ? Slot : 'button';
  if (asChild) return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props}>{children}</Comp>;
  return <Comp className={cn(buttonVariants({ variant, size, className }), busy && 'disabled:opacity-80')} ref={ref} disabled={disabled || busy} aria-busy={busy || undefined} {...props}>
    {busy ? <span data-busy="" aria-hidden="true" className="qd-spin" /> : null}{children}
  </Comp>;
});
Button.displayName = 'Button';
export { Button, buttonVariants };
