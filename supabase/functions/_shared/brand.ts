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
  tagline: 'UAE Sourcing Marketplace',
  fontDisplay: 'Poppins',
} as const;

/** '#RRGGBB' -> [r, g, b] in 0..1, the form pdf-lib's rgb() takes. */
export function hex01(hex: string): [number, number, number] {
  const n = parseInt(hex.replace('#', ''), 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

/** Public URL of a kit file, for mail and og:image (the bucket is public; nothing in it is secret). */
export function brandPublicUrl(path: string): string {
  return (Deno.env.get('SUPABASE_URL') || '') + '/storage/v1/object/public/' + BRAND.bucket + '/' + path;
}
