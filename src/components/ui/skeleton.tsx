import { cn } from "@/lib/utils"

// The brand's loading idiom is the redaction bar (globals.css .redact: hard-edged, hatched), which
// the design system chose over the grey pulsing rectangle this file shipped with.
function Skeleton({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return <div aria-hidden className={cn("redact block", className)} {...props} />
}

export { Skeleton }
