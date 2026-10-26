// QuotesDone brand tokens for edge code (6 Sep 2026).
//
// The founder's brand kit (QuotesDone_Brand_Kit.zip, 24 Jun 2026) is on file: its files are in the public
// `brand` bucket under kit/<zip path>, indexed by public.brand_assets, and its colours, typefaces and
// logo rules are rows of public.company_brand, rendered into every agent head as qd-company:brand. The
// hexes below are the kit's own (WHERE_TO_USE.txt) and the same values sit in src/app/globals.css. Change
// a colour here only when public.company_brand changes — this file is the edge-side copy, not a second
// palette.
export const BRAND = {
  teal: '#14B8A6', tealLight: '#6EE7D4', tealDeep: '#0B8276',
  gold: '#E3C065', goldLight: '#F6DD8C', goldDeep: '#BD8E36',
  navy: '#0C2330', navyHi: '#173A4B', navyDeep: '#06121B',
  ink: '#0A0A0A', paper: '#EAF4F2', muted: '#9DB2B2',
  bucket: 'brand',
  // Horizontal lockups, 1859x460 px, transparent. Dark = white wordmark for navy grounds; Light = navy
  // wordmark for white grounds. The artwork is the founder's and is never altered here — only placed.
  lockupDark: 'kit/05_Logo_Lockups/horizontal_OnDark_transparent.png',
  lockupLight: 'kit/05_Logo_Lockups/horizontal_OnLight_transparent.png',
  mark: 'kit/05_Logo_Lockups/mark_only_transparent_1200.png',
  lockupAspect: 1859 / 460,

  // TRIMMED LOCKUPS (8 Sep 2026, founder: "everywhere from now it should [be sized] in terms of
  // the height"). The supplied lockups are a 1859x460 box holding 1608x176 of artwork -- 38% of
  // the height, the rest empty alpha. Sized by width at 170px that renders a 16px wordmark beside
  // 15px body text, which is why the logo read as tiny. These derivatives are the same artwork
  // with the empty margin cropped: 1612x180, 98% ink. No pixel of the logo is altered -- the rule
  // above still holds, the artwork is only placed -- and the originals stay in the kit untouched.
  lockupDarkTrimmed: 'kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png',
  lockupLightTrimmed: 'kit/05_Logo_Lockups/horizontal_OnLight_trimmed.png',
  lockupTrimmedAspect: 1612 / 180,

  // HEIGHT IS THE UNIT. A width tells you nothing about how big a lockup looks, because it includes
  // whatever padding the asset was drawn inside; two assets at the same width look nothing alike.
  // These are public.company_brand rows logo.height_email / _ui / _document, kept here as the
  // edge-side copy the same way the colours are.
  logoHeight: { email: 28, ui: 24, document: 20 },
  tagline: 'UAE Sourcing Marketplace',
  fontDisplay: 'Poppins',
} as const;

/**
 * Width for a trimmed lockup at a given height. Set the height, let the width follow -- never both,
 * because company_brand.logo.dont forbids stretching and setting both is how an aspect ratio gets
 * broken the next time the asset is replaced.
 */
export function lockupWidthFor(heightPx: number): number {
  return Math.round(heightPx * BRAND.lockupTrimmedAspect);
}

/**
 * The <img> for a lockup, sized by height on whichever ground it sits.
 *
 * The alt text is load-bearing rather than decorative: the lockup CONTAINS the wordmark, and most
 * mail clients block images on first open, so without it a blocked image is a nameless header.
 */
export function lockupImg(opts: { ground?: 'dark' | 'light'; height?: number; extraStyle?: string } = {}): string {
  const h = opts.height ?? BRAND.logoHeight.email;
  const src = brandPublicUrl(opts.ground === 'light' ? BRAND.lockupLightTrimmed : BRAND.lockupDarkTrimmed);
  return `<img src="${src}" height="${h}" width="${lockupWidthFor(h)}" alt="QuotesDone" `
    + `style="display:block;border:0;height:${h}px;width:auto;max-width:100%;${opts.extraStyle || ''}"/>`;
}

/** '#RRGGBB' -> [r, g, b] in 0..1, the form pdf-lib's rgb() takes. */
export function hex01(hex: string): [number, number, number] {
  const n = parseInt(hex.replace('#', ''), 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

/** Public URL of a kit file, for mail and og:image (the bucket is public; nothing in it is secret). */
export function brandPublicUrl(path: string): string {
  return (Deno.env.get('SUPABASE_URL') || '') + '/storage/v1/object/public/' + BRAND.bucket + '/' + path;
}
