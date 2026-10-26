import * as React from 'react';
import { cn } from '@/lib/utils';
// An inset well (the input sits below the surface, a panel sits above it). Focus lights the edge
// teal with a soft halo; aria-invalid turns it danger. No black shadow.
const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(({ className, type, ...props }, ref) => (
  <input
    type={type}
    ref={ref}
    className={cn(
      'flex h-10 w-full rounded-btn border border-input bg-navy-deep/55 px-3.5 py-2 text-copy text-foreground shadow-[inset_0_1px_3px_rgba(2,8,13,.6)] transition-[border-color,box-shadow] duration-base ease-expo placeholder:text-faint hover:border-line3 focus-visible:border-teal focus-visible:outline-none focus-visible:shadow-[inset_0_1px_3px_rgba(2,8,13,.6),0_0_0_3px_rgba(20,184,166,.18)] disabled:cursor-not-allowed disabled:opacity-50 aria-[invalid=true]:border-danger file:border-0 file:bg-transparent file:text-small file:font-medium',
      className,
    )}
    {...props}
  />
));
Input.displayName = 'Input';
export { Input };
