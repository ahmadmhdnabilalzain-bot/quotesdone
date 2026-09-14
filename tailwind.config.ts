import type { Config } from 'tailwindcss';

// BRAND VOCABULARY (website audit 14 Sep 2026, design-system section).
// Measured before: 749 arbitrary [Npx] font sizes, 30 [var(--line)] brackets, 9 corner radii with
// no names, and `text-faint` used 10 times while `faint` was not a colour here — that utility
// generated no CSS at all. Every token below maps onto a value already in globals.css, so adopting
// a token never changes the look; scripts/codemods/px_to_scale.mjs rewrites literals onto them.
const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy:  { DEFAULT: '#0C2330', deep: '#06121B', light: '#173A4B' },
        teal:  { DEFAULT: '#14B8A6', light: '#6EE7D4', deep: '#0B8276' },
        gold:  { DEFAULT: '#E3C065', light: '#F6DD8C', deep: '#BD8E36' },
        ink:   '#0A0A0A',
        paper: '#EAF4F2',
        faint: '#7C97A3',
        surf:  '#123041',
        redact: '#14303E',
        line:  'var(--line)',
        line2: 'var(--line2)',
        // Semantic status, derived from the key-light model rather than Tailwind's default palette
        // (152 uses of amber/emerald/red/sky/rose measured). HSL channels live in globals.css so
        // opacity modifiers (bg-ok/15) work.
        ok:     { DEFAULT: 'hsl(var(--ok) / <alpha-value>)',     fg: 'hsl(var(--ok-fg) / <alpha-value>)' },
        warn:   { DEFAULT: 'hsl(var(--warn) / <alpha-value>)',   fg: 'hsl(var(--warn-fg) / <alpha-value>)' },
        info:   { DEFAULT: 'hsl(var(--info) / <alpha-value>)',   fg: 'hsl(var(--info-fg) / <alpha-value>)' },
        danger: { DEFAULT: 'hsl(var(--danger) / <alpha-value>)', fg: 'hsl(var(--danger-fg) / <alpha-value>)' },
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: { DEFAULT: 'hsl(var(--primary))', foreground: 'hsl(var(--primary-foreground))' },
        secondary: { DEFAULT: 'hsl(var(--secondary))', foreground: 'hsl(var(--secondary-foreground))' },
        destructive: { DEFAULT: 'hsl(var(--destructive))', foreground: 'hsl(var(--destructive-foreground))' },
        muted: { DEFAULT: '#9DB2B2', foreground: 'hsl(var(--muted-foreground))' },
        accent: { DEFAULT: 'hsl(var(--accent))', foreground: 'hsl(var(--accent-foreground))' },
        popover: { DEFAULT: 'hsl(var(--popover))', foreground: 'hsl(var(--popover-foreground))' },
        card: { DEFAULT: 'hsl(var(--card))', foreground: 'hsl(var(--card-foreground))' }
      },
      // Named type scale. `label` is the floor: nothing reads below 12px (49 text nodes under 12px
      // were measured on the homepage). Display sizes read CSS variables so the Arabic locale gets
      // its own clamp scale (globals.css) from the same class.
      fontSize: {
        label: ['12px', { lineHeight: '1.4' }],
        small: ['13px', { lineHeight: '1.5' }],
        body:  ['14px', { lineHeight: '1.6' }],
        copy:  ['15px', { lineHeight: '1.65' }],
        lead:  ['clamp(16px, 0.6vw + 13.5px, 19px)', { lineHeight: '1.6' }],
        'display-sm': ['var(--fs-display-sm)', { lineHeight: '1.08' }],
        display: ['var(--fs-display)', { lineHeight: '1.02' }],
      },
      borderRadius: {
        lg: 'var(--radius)', md: 'calc(var(--radius) - 2px)', sm: 'calc(var(--radius) - 4px)',
        chip: '10px', panel: '14px', card: '22px', pill: '9999px',
      },
      // Elevation: navy-tinted, never black (globals.css header rule). e1..e3 are the .depth stack.
      boxShadow: {
        key: 'var(--key)',
        lift: 'var(--lift)',
        e1: 'var(--key), 0 2px 6px -3px rgba(0,12,20,.55)',
        e2: 'var(--key), 0 12px 28px -14px rgba(0,12,20,.8)',
        e3: 'var(--key), 0 2px 6px -3px rgba(0,12,20,.55), 0 12px 28px -14px rgba(0,12,20,.8), 0 44px 110px -60px rgba(0,12,20,.98)',
        'glow-teal': '0 16px 44px -16px rgba(20,184,166,.85)',
        'glow-gold': '0 16px 44px -18px rgba(227,192,101,.7)',
      },
      backgroundImage: {
        'brand-grad': 'linear-gradient(96deg,#EAF4F2 0%,#6EE7D4 42%,#EAF4F2 62%,#E3C065 100%)',
        'navy-field': 'linear-gradient(178deg,#173A4B 0%,#0C2330 34%,#06121B 100%)',
        'surf-grad': 'linear-gradient(170deg,rgba(18,48,65,.72),rgba(10,27,38,.72))',
        'teal-glow': 'radial-gradient(closest-side,rgba(20,184,166,.22),transparent 72%)',
        'gold-glow': 'radial-gradient(closest-side,rgba(227,192,101,.16),transparent 72%)',
      },
      fontFamily: {
        sans: ['var(--font-body)', 'system-ui', 'sans-serif'],
        head: ['var(--font-head)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-mono)', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']
      },
      spacing: { beat: '104px', 'beat-s': '72px', 'beat-l': '148px' },
      transitionTimingFunction: { expo: 'cubic-bezier(.16,1,.3,1)' },
      transitionDuration: { fast: '130ms', base: '220ms', slow: '400ms', slower: '750ms' },
      keyframes: {
        'accordion-down': { from: { height: '0' }, to: { height: 'var(--radix-accordion-content-height)' } },
        'accordion-up': { from: { height: 'var(--radix-accordion-content-height)' }, to: { height: '0' } }
      },
      animation: { 'accordion-down': 'accordion-down 0.2s ease-out', 'accordion-up': 'accordion-up 0.2s ease-out' }
    }
  },
  plugins: [require('tailwindcss-animate')]
};
export default config;
