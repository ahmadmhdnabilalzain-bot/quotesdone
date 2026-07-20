import type { Config } from 'tailwindcss';
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
      borderRadius: { lg: 'var(--radius)', md: 'calc(var(--radius) - 2px)', sm: 'calc(var(--radius) - 4px)' },
      fontFamily: {
        sans: ['var(--font-body)', 'system-ui', 'sans-serif'],
        head: ['var(--font-head)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-mono)', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']
      },
      spacing: { beat: '104px', 'beat-s': '72px', 'beat-l': '148px' },
      transitionTimingFunction: { expo: 'cubic-bezier(.16,1,.3,1)' },
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
