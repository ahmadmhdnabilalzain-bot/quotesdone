import * as React from 'react';
import { cn } from '@/lib/utils';

// Card IS the sealed panel (.qd-panel: layered glass, inner highlight, specular hairline, navy
// elevation). `interactive` lifts on hover and lights under the pointer.
type CardProps = React.HTMLAttributes<HTMLDivElement> & { interactive?: boolean };
const Card = React.forwardRef<HTMLDivElement, CardProps>(({ className, interactive, ...props }, ref) => (
  <div ref={ref} className={cn('qd-panel text-card-foreground', interactive && 'qd-panel-hover qd-lit', className)} {...props} />
));
Card.displayName = 'Card';
const CardHeader = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('flex flex-col gap-1.5 p-6', className)} {...props} />
));
CardHeader.displayName = 'CardHeader';
const CardTitle = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('font-head text-[17px] font-semibold leading-snug tracking-snug text-white', className)} {...props} />
));
CardTitle.displayName = 'CardTitle';
const CardDescription = React.forwardRef<HTMLParagraphElement, React.HTMLAttributes<HTMLParagraphElement>>(({ className, ...props }, ref) => (
  <p ref={ref} className={cn('text-body text-muted', className)} {...props} />
));
CardDescription.displayName = 'CardDescription';
const CardContent = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('p-6 pt-0', className)} {...props} />
));
CardContent.displayName = 'CardContent';
const CardFooter = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('flex items-center gap-3 border-t border-line px-6 py-4', className)} {...props} />
));
CardFooter.displayName = 'CardFooter';
export { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter };
