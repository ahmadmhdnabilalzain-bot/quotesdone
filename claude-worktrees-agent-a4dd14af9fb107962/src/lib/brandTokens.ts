// Sealed brand tokens as data: the colour list the /brand page renders and the text/ground pairs
// whose WCAG contrast both the page and scripts/brand_contrast.mjs compute. The values mirror the
// CSS variables in src/app/globals.css — change a colour there and here together.

export type Swatch = { name: string; token: string; hex: string; role: string };
export const SWATCHES: { group: string; items: Swatch[] }[] = [
  { group: 'Ground', items: [
    { name: 'Navy deep', token: '--navy-deep', hex: '#050C12', role: 'Deepest ground, overlays' },
    { name: 'Navy', token: '--navy', hex: '#0A1720', role: 'Page ground' },
    { name: 'Surface', token: '--surf', hex: '#0F2231', role: 'Panels, cards' },
    { name: 'Navy hi', token: '--navy-hi', hex: '#132A3A', role: 'Raised plane, key-lit edge' },
    { name: 'Redact', token: '--redact', hex: '#1B3445', role: 'The seal: withheld identity, loading' },
  ] },
  { group: 'The one light', items: [
    { name: 'Teal deep', token: '--teal-deep', hex: '#0B8276', role: 'Gradient foot, pressed' },
    { name: 'Teal', token: '--teal', hex: '#14B8A6', role: 'Primary action, key light' },
    { name: 'Teal light', token: '--teal-light', hex: '#6EE7D4', role: 'Links, active state, figures' },
  ] },
  { group: 'The reveal (only)', items: [
    { name: 'Gold deep', token: '--gold-deep', hex: '#BD8E36', role: 'Reveal gradient foot' },
    { name: 'Gold', token: '--gold', hex: '#E3C065', role: 'Unsealed identity, done' },
    { name: 'Gold light', token: '--gold-light', hex: '#F6DD8C', role: 'The unseal edge light' },
  ] },
  { group: 'Text', items: [
    { name: 'Paper', token: '--paper', hex: '#EEF6F4', role: 'Primary text' },
    { name: 'Muted', token: '--muted', hex: '#A7B9BB', role: 'Secondary text' },
    { name: 'Faint', token: '--faint', hex: '#8199A3', role: 'Labels, metadata' },
  ] },
];

const hex = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const lum = (h: string) => {
  const [r, g, b] = hex(h).map((v) => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
/** WCAG 2.x contrast ratio between two opaque hex colours. */
export function contrast(a: string, b: string) {
  const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m);
  return (x + 0.05) / (y + 0.05);
}
/** `fg` at `alpha` over `bg`, flattened to an opaque hex (for tinted badge grounds). */
export function blend(fg: string, bg: string, alpha: number) {
  const f = hex(fg), g = hex(bg);
  return '#' + f.map((v, i) => Math.round(v * alpha + g[i] * (1 - alpha)).toString(16).padStart(2, '0')).join('');
}

const NAVY = '#0A1720', SURF = '#0F2231', DEEP = '#050C12', POP = '#0C1C28';
/** min: 4.5 body text, 3 large text (>=24px or >=18.66px bold) and UI glyphs. */
export const PAIRS: { fg: string; bg: string; use: string; min: 4.5 | 3 }[] = [
  { fg: '#EEF6F4', bg: NAVY, use: 'paper on navy', min: 4.5 },
  { fg: '#EEF6F4', bg: SURF, use: 'paper on surface', min: 4.5 },
  { fg: '#A7B9BB', bg: NAVY, use: 'muted on navy', min: 4.5 },
  { fg: '#A7B9BB', bg: SURF, use: 'muted on surface', min: 4.5 },
  { fg: '#A7B9BB', bg: '#15303F', use: 'muted on raised surface', min: 4.5 },
  { fg: '#8199A3', bg: NAVY, use: 'faint on navy', min: 4.5 },
  { fg: '#8199A3', bg: SURF, use: 'faint on surface', min: 4.5 },
  { fg: '#8199A3', bg: DEEP, use: 'faint on navy deep', min: 4.5 },
  { fg: '#6EE7D4', bg: NAVY, use: 'teal light (links) on navy', min: 4.5 },
  { fg: '#6EE7D4', bg: SURF, use: 'teal light on surface', min: 4.5 },
  { fg: '#14B8A6', bg: NAVY, use: 'teal on navy (UI, large)', min: 3 },
  { fg: '#03201C', bg: '#14B8A6', use: 'on-teal text on primary button', min: 4.5 },
  { fg: '#2A1F05', bg: '#E3C065', use: 'reveal button text on gold', min: 4.5 },
  { fg: '#F6DD8C', bg: NAVY, use: 'gold light (revealed name) on navy', min: 4.5 },
  { fg: '#E3C065', bg: SURF, use: 'gold on surface', min: 4.5 },
  { fg: '#EEF6F4', bg: POP, use: 'paper on popover', min: 4.5 },
  { fg: '#A7B9BB', bg: '#1B3445', use: 'muted on redact (sealed badge)', min: 4.5 },
  { fg: '#7DEBD9', bg: blend('#2BC4AE', SURF, 0.12), use: 'ok badge', min: 4.5 },
  { fg: '#F3D98E', bg: blend('#E3C065', SURF, 0.12), use: 'warn badge', min: 4.5 },
  { fg: '#9ACDF0', bg: blend('#5AA9DD', SURF, 0.12), use: 'info badge', min: 4.5 },
  { fg: '#F8A89C', bg: blend('#EE6E5E', SURF, 0.12), use: 'danger badge', min: 4.5 },
  { fg: '#0A1720', bg: '#EE6E5E', use: 'destructive button text', min: 4.5 },
  // the light portal theme
  { fg: '#0A1720', bg: '#F4F7F7', use: 'light: foreground on background', min: 4.5 },
  { fg: '#4A5E65', bg: '#FFFFFF', use: 'light: muted on card', min: 4.5 },
  { fg: '#FFFFFF', bg: '#0B7A6E', use: 'light: primary button text', min: 4.5 },
];
