import { useId } from 'react';

type BrandMarkProps = {
  className?: string;
  title?: string;
};

/**
 * QuotesDone brand mark — teal "Q" ring + gold checkmark.
 * Recreated as inline SVG from the official brand-kit vector (mark_color.svg,
 * viewBox 0 0 800 800) so it stays razor-sharp at any size and carries the
 * exact brand gradients. Decorative by default (aria-hidden); pass a `title`
 * to expose an accessible label.
 */
export function BrandMark({ className, title }: BrandMarkProps) {
  // Unique gradient ids per instance. This was 'bm' for every untitled mark, so the header and the
  // footer both emitted id="bm-teal"/"bm-gold" (duplicate ids, flagged by the Front-End Checklist
  // audit of the live homepage, 14 Sep 2026). useId works in server components and is stable
  // across server render and hydration; the colons it contains are stripped for url(#…).
  const uid = `bm${useId().replace(/[^a-zA-Z0-9_-]/g, '')}`;
  return (
    <svg
      viewBox="0 0 800 800"
      className={className}
      role={title ? 'img' : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
      focusable="false"
    >
      {title ? <title>{title}</title> : null}
      <defs>
        <linearGradient id={`${uid}-teal`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#6ee7d4" />
          <stop offset="0.55" stopColor="#16b8a6" />
          <stop offset="1" stopColor="#0b8276" />
        </linearGradient>
        <linearGradient id={`${uid}-gold`} x1="0" y1="0" x2="0.3" y2="1">
          <stop offset="0" stopColor="#f6dd8c" />
          <stop offset="0.5" stopColor="#e3c065" />
          <stop offset="1" stopColor="#bd8e36" />
        </linearGradient>
      </defs>
      <circle
        cx="400"
        cy="398"
        r="92"
        fill="none"
        stroke={`url(#${uid}-teal)`}
        strokeWidth="50"
      />
      <path
        d="M434 470 L486 524 L582 408"
        fill="none"
        stroke={`url(#${uid}-gold)`}
        strokeWidth="44"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
