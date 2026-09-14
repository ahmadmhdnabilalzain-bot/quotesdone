'use client';

import * as React from 'react';
import * as ProgressPrimitive from '@radix-ui/react-progress';
import { cn } from '@/lib/utils';

// The track is a redaction well; the fill is the teal light, growing from the reader's start edge
// (scaleX from inline-start, so RTL fills right-to-left without a mirrored transform).
const Progress = React.forwardRef<React.ElementRef<typeof ProgressPrimitive.Root>, React.ComponentPropsWithoutRef<typeof ProgressPrimitive.Root>>(
  ({ className, value, ...props }, ref) => (
    <ProgressPrimitive.Root ref={ref} className={cn('relative h-1.5 w-full overflow-hidden rounded-pill bg-redact shadow-[inset_0_0_0_1px_rgba(110,231,212,.12)]', className)} {...props}>
      <ProgressPrimitive.Indicator
        className="h-full w-full origin-left rounded-pill bg-gradient-to-r from-teal-deep to-teal-light shadow-[0_0_12px_rgba(110,231,212,.6)] transition-transform duration-slow ease-expo rtl:origin-right rtl:bg-gradient-to-l"
        style={{ transform: `scaleX(${Math.max(0, Math.min(100, value || 0)) / 100})` }}
      />
    </ProgressPrimitive.Root>
  ),
);
Progress.displayName = ProgressPrimitive.Root.displayName;

export { Progress };
