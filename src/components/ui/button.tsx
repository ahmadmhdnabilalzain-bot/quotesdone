import * as React from 'react';
import { Slot } from '@radix-ui/react-slot';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

// Sealed buttons. Filled variants are lit from within (.qd-hoverlit follows the pointer via
// ui/pointer-light) and wear the brand elevation; nothing casts a black shadow.
// `reveal` is gold and exists for ONE action: unsealing a supplier's identity (the 3% reveal).
// Using it anywhere else breaks the brand rule that gold only ever marks a reveal or a done state.
const buttonVariants = cva(
  'qd-hoverlit inline-flex select-none items-center justify-center gap-2 whitespace-nowrap rounded-btn font-medium transition-[transform,background-color,border-color,box-shadow,color] duration-base ease-expo active:scale-[.97] focus-visible:outline-none focus-visible:shadow-ring disabled:pointer-events-none disabled:opacity-45 motion-reduce:active:scale-100 [&_svg]:size-4 [&_svg]:shrink-0',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground shadow-e1 hover:bg-[#1ED0BC] hover:shadow-glow-teal',
        reveal: 'bg-gradient-to-b from-gold-light to-gold text-[#2A1F05] font-semibold shadow-e1 hover:shadow-glow-gold',
        secondary: 'border border-line2 bg-surf text-foreground shadow-e1 hover:border-line3 hover:bg-surf-hi',
        outline: 'border border-line2 bg-transparent text-foreground shadow-key hover:border-teal hover:text-teal-light',
        ghost: 'text-muted hover:bg-teal-light/[0.06] hover:text-foreground',
        destructive: 'bg-danger text-navy shadow-e1 hover:bg-danger/90',
        link: 'text-teal-light underline-offset-4 hover:underline active:scale-100',
      },
      size: {
        sm: 'h-8 px-3 text-small',
        default: 'h-10 px-4 text-copy',
        lg: 'h-12 px-6 text-copy',
        xl: 'h-14 rounded-[12px] px-8 text-[16px]',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  },
);
export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> { asChild?: boolean; }
const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(({ className, variant, size, asChild = false, ...props }, ref) => {
  const Comp = asChild ? Slot : 'button';
  return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />;
});
Button.displayName = 'Button';
export { Button, buttonVariants };
