import type { Config } from 'tailwindcss';

// BRAND VOCABULARY — direction A "Sealed" (14 Sep 2026). Every key that existed before still exists,
// so no class name in the codebase changes; the values are the Sealed ones. Colours that are also
// CSS variables read the variable, so globals.css stays the single source of truth for values.
// Type, tracking and weight scales read variables too: the Arabic locale redefines them in
// globals.css (its own display clamps, and every letter-spacing token collapses to 0).
const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy:  { DEFAULT: '#0A1720', deep: '#050C12', light: '#132A3A' },
        teal:  { DEFAULT: '#14B8A6', light: '#6EE7D4', deep: '#0B8276' },
        // gold is the REVEAL: an unsealed identity or a done state. Nothing else.
        gold:  { DEFAULT: '#E3C065', light: '#F6DD8C', deep: '#BD8E36' },
        ink:   '#050C12',
        paper: '#EEF6F4',
        faint: '#8199A3',
        surf:  { DEFAULT: '#0F2231', hi: '#15303F' },
        redact: '#1B3445',
        'on-teal': '#03201C',
        line:  'var(--line)',
        line2: 'var(--line2)',
        line3: 'var(--line3)',
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
        muted: { DEFAULT: '#A7B9BB', foreground: 'hsl(var(--muted-foreground))' },
        accent: { DEFAULT: 'hsl(var(--accent))', foreground: 'hsl(var(--accent-foreground))' },
        popover: { DEFAULT: 'hsl(var(--popover))', foreground: 'hsl(var(--popover-foreground))' },
        card: { DEFAULT: 'hsl(var(--card))', foreground: 'hsl(var(--card-foreground))' },
      },
      // Named type scale. `label` (12px) is the floor. Display/h2/h3/lead read variables, so the
      // same class yields the dedicated Arabic scale (taller leading, weight 700, zero tracking).
      fontSize: {
        label: ['12px', { lineHeight: '1.4' }],
        small: ['13px', { lineHeight: '1.5' }],
        body:  ['14px', { lineHeight: '1.6' }],
        copy:  ['15px', { lineHeight: '1.65' }],
        lead:  ['var(--fs-lead)', { lineHeight: 'var(--lh-lead)' }],
        h3:    ['var(--fs-h3)', { lineHeight: 'var(--lh-h3)', letterSpacing: 'var(--ls-snug)', fontWeight: '600' }],
        h2:    ['var(--fs-h2)', { lineHeight: 'var(--lh-h2)', letterSpacing: 'var(--ls-tight)', fontWeight: 'var(--fw-display)' }],
        'display-sm': ['var(--fs-display-sm)', { lineHeight: 'var(--lh-display-sm)', letterSpacing: 'var(--ls-tight)', fontWeight: 'var(--fw-display)' }],
        display: ['var(--fs-display)', { lineHeight: 'var(--lh-display)', letterSpacing: 'var(--ls-display)', fontWeight: 'var(--fw-display)' }],
        'display-xl': ['var(--fs-display-xl)', { lineHeight: 'var(--lh-display-xl)', letterSpacing: 'var(--ls-display)', fontWeight: 'var(--fw-display)' }],
      },
      letterSpacing: {
        display: 'var(--ls-display)', tight: 'var(--ls-tight)', snug: 'var(--ls-snug)',
        normal: 'var(--ls-normal)', wide: 'var(--ls-wide)', caps: 'var(--ls-caps)',
      },
      borderRadius: {
        lg: 'var(--radius)', md: 'calc(var(--radius) - 2px)', sm: 'calc(var(--radius) - 4px)',
        chip: '6px', btn: '10px', panel: '12px', card: '16px', frame: '18px', pill: '9999px',
      },
      // Elevation: navy-tinted, never black. Values live in globals.css (the light portal overrides them).
      boxShadow: {
        key: 'var(--key)',
        lift: 'var(--lift)',
        e1: 'var(--e1)',
        e2: 'var(--e2)',
        e3: 'var(--e3)',
        'glow-teal': 'var(--glow-teal)',
        'glow-gold': 'var(--glow-gold)',
        ring: 'var(--ring)',
      },
      backgroundImage: {
        'brand-grad': 'linear-gradient(96deg,#EEF6F4 0%,#6EE7D4 45%,#EEF6F4 64%,#A7F3E6 100%)',
        'navy-field': 'radial-gradient(120% 80% at 18% 0%,#163247 0%,#0A1720 46%,#050C12 100%)',
        'surf-grad': 'linear-gradient(170deg,rgba(21,48,63,.78),rgba(10,23,32,.72))',
        'teal-glow': 'radial-gradient(closest-side,rgba(20,184,166,.28),transparent 72%)',
        'gold-glow': 'radial-gradient(closest-side,rgba(227,192,101,.22),transparent 72%)',
        unseal: 'linear-gradient(90deg,rgba(227,192,101,0),rgba(246,221,140,.95),rgba(227,192,101,0))',
        noise: 'var(--noise)',
      },
      fontFamily: {
        sans: ['var(--font-body)', 'system-ui', 'sans-serif'],
        head: ['var(--font-head)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-mono)', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      spacing: { beat: '112px', 'beat-s': '72px', 'beat-l': '160px' },
      transitionTimingFunction: { expo: 'cubic-bezier(.16,1,.3,1)' },
      transitionDuration: { fast: '130ms', base: '220ms', slow: '400ms', slower: '750ms' },
      keyframes: {
        'accordion-down': { from: { height: '0' }, to: { height: 'var(--radix-accordion-content-height)' } },
        'accordion-up': { from: { height: 'var(--radix-accordion-content-height)' }, to: { height: '0' } },
      },
      animation: { 'accordion-down': 'accordion-down 0.2s ease-out', 'accordion-up': 'accordion-up 0.2s ease-out' },
    },
  },
  plugins: [require('tailwindcss-animate')],
};
export default config;
