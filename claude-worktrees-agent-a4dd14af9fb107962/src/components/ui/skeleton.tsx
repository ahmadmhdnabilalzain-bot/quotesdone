import { cn } from '@/lib/utils';

// The brand's loading state IS the redaction bar (globals.css .redact): hard-edged, hatched, a mark
// that withholds rather than one that is pending. Bars arrive before the content they seal.
function Skeleton({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div aria-hidden className={cn('redact block h-3.5 w-full', className)} {...props} />;
}

export { Skeleton };
