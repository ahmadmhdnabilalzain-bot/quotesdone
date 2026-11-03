import { clsx, type ClassValue } from 'clsx';
import { extendTailwindMerge } from 'tailwind-merge';

// tailwind-merge must know the brand's named scales (the @theme block in src/app/globals.css). Without this it cannot
// tell a named font size (`text-copy`, `text-label`) from a text colour (`text-on-teal`), treats
// them as one group, and drops whichever came first — measured 14 Sep 2026: every Button lost its
// text colour to its size class (dark-on-teal rendered as inherited white), and a className size
// on a Badge was discarded the same way. Registering the scales makes each land in its own group.
const twMerge = extendTailwindMerge({
  extend: {
    classGroups: {
      'font-size': [{ text: ['label', 'small', 'body', 'copy', 'lead', 'h3', 'h2', 'display-sm', 'display', 'display-xl'] }],
      rounded: [{ rounded: ['chip', 'btn', 'panel', 'card', 'frame', 'pill'] }],
      shadow: [{ shadow: ['key', 'lift', 'e1', 'e2', 'e3', 'glow-teal', 'glow-gold', 'ring'] }],
      tracking: [{ tracking: ['display', 'caps'] }],
    },
  },
});

export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }
