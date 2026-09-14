import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';
// Status variants read the semantic tokens (tailwind.config.ts ok/warn/info/danger), not Tailwind's
// default palette — `ok` was bg-emerald-500/15 text-emerald-400 before.
const badgeVariants = cva('inline-flex items-center rounded-pill border px-2.5 py-0.5 text-label font-semibold transition-colors', {
  variants: { variant: {
    default: 'border-transparent bg-primary/15 text-primary',
    secondary: 'border-transparent bg-white/10 text-foreground',
    outline: 'text-foreground border-border',
    ok: 'border-transparent bg-ok/15 text-ok-fg',
    warn: 'border-transparent bg-warn/15 text-warn-fg',
    info: 'border-transparent bg-info/15 text-info-fg',
    danger: 'border-transparent bg-danger/15 text-danger-fg',
    destructive: 'border-transparent bg-danger/15 text-danger-fg',
  } }, defaultVariants: { variant: 'default' }
});
export interface BadgeProps extends React.HTMLAttributes<HTMLDivElement>, VariantProps<typeof badgeVariants> {}
function Badge({ className, variant, ...props }: BadgeProps) { return <div className={cn(badgeVariants({ variant }), className)} {...props} />; }
export { Badge, badgeVariants };
