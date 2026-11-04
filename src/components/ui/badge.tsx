import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

// Status reads the semantic tokens (ok/warn/info/danger). `sealed` marks a withheld identity,
// `revealed` an opened one (gold — reveal only). `dot` adds a leading status light.
const badgeVariants = cva('inline-flex items-center gap-1.5 rounded-pill border px-2.5 py-0.5 text-label font-medium transition-colors', {
  variants: {
    variant: {
      default: 'border-teal/30 bg-teal/12 text-teal-light',
      secondary: 'border-line2 bg-teal-light/5 text-foreground',
      outline: 'border-line2 text-foreground',
      ok: 'border-ok/30 bg-ok/12 text-ok-fg',
      warn: 'border-warn/30 bg-warn/12 text-warn-fg',
      info: 'border-info/30 bg-info/12 text-info-fg',
      danger: 'border-danger/30 bg-danger/12 text-danger-fg',
      destructive: 'border-danger/30 bg-danger/12 text-danger-fg',
      sealed: 'border-line2 bg-redact font-mono text-muted',
      revealed: 'border-gold/40 bg-gold/12 text-gold-light',
    },
  },
  defaultVariants: { variant: 'default' },
});
export interface BadgeProps extends React.HTMLAttributes<HTMLDivElement>, VariantProps<typeof badgeVariants> { dot?: boolean; }
function Badge({ className, variant, dot, children, ...props }: BadgeProps) {
  return (
    <div className={cn(badgeVariants({ variant }), className)} {...props}>
      {dot ? <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-current shadow-[0_0_8px_currentColor]" /> : null}
      {children}
    </div>
  );
}
export { Badge, badgeVariants };
