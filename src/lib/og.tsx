import { ImageResponse } from 'next/og';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

// SOCIAL CARDS (website audit 14 Sep 2026: "every share of every page is a bare text card").
//
// Fonts are TTF copies of the self-hosted Tajawal faces in public/fonts/og. They exist because
// satori (the renderer behind next/og) reads TTF/OTF/WOFF and NOT woff2, which is all public/fonts
// held. They were decompressed from those exact woff2 files (wawoff2), so the glyphs are identical.
// Tajawal's Latin cut is a static 800, while Space Grotesk is a variable font and satori renders
// only a variable font's default instance — so Tajawal carries both scripts here.
//
// Two satori behaviours, both MEASURED on rendered cards in this change:
//  · Two fonts registered under ONE family name at the same weight: satori used only the first and
//    Latin text fell back to its default face. So the Arabic and Latin files get distinct names and
//    the family list names both (satori falls through per glyph).
//  · Satori shapes Arabic correctly (letters join) but lays words out left-to-right, so an Arabic
//    sentence read backwards. RTL text is therefore split into words, each a flex item in a
//    row-reverse wrapping row: first word on the right, wrapping right-to-left like the browser.
export const OG_SIZE = { width: 1200, height: 630 };

const face = (f: string) => readFile(join(process.cwd(), 'public/fonts/og', `${f}.ttf`));
const FAMILY = 'QD Latin, QD Arabic';
const hasArabic = (s: string) => /[؀-ۿ]/.test(s);

// BrandMark.tsx's paths, as a data URI (satori draws <img> SVG reliably; inline gradient ids less so).
const MARK = 'data:image/svg+xml;base64,' + Buffer.from(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800"><defs>' +
  '<linearGradient id="t" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6ee7d4"/><stop offset=".55" stop-color="#14b8a6"/><stop offset="1" stop-color="#0b8276"/></linearGradient>' +
  '<linearGradient id="g" x1="0" y1="0" x2=".3" y2="1"><stop offset="0" stop-color="#f6dd8c"/><stop offset=".5" stop-color="#e3c065"/><stop offset="1" stop-color="#bd8e36"/></linearGradient></defs>' +
  '<circle cx="400" cy="398" r="92" fill="none" stroke="url(#t)" stroke-width="50"/>' +
  '<path d="M434 470 L486 524 L582 408" fill="none" stroke="url(#g)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/></svg>',
).toString('base64');

const FOOT = {
  en: 'Anonymous quotes from vetted UAE suppliers · quotesdone.com',
  ar: 'عروض أسعار مجهولة من موردين موثوقين في الإمارات · quotesdone.com',
};

/** A run of text; Arabic runs are laid out word by word right-to-left (see header). */
function Text({ text, size, weight, color, lineHeight = 1.25 }: { text: string; size: number; weight: number; color?: string; lineHeight?: number }) {
  const base = { fontSize: size, fontWeight: weight, color, lineHeight };
  if (!hasArabic(text)) return <div style={{ display: 'flex', ...base }}>{text}</div>;
  return (
    <div style={{ display: 'flex', flexDirection: 'row-reverse', flexWrap: 'wrap', columnGap: Math.round(size * 0.26), ...base }}>
      {text.split(/\s+/).map((w, i) => <div key={i} style={{ display: 'flex' }}>{w}</div>)}
    </div>
  );
}

/** `rtl` follows the TITLE's language (an English blog post under /ar keeps an LTR title). */
export async function renderOg(o: { locale: string; kicker: string; title: string; rtl?: boolean }) {
  const ar = o.locale === 'ar';
  const rtl = o.rtl ?? ar;
  const [a800, l800, a500, l500] = await Promise.all([
    face('tajawal-800-arabic'), face('tajawal-800-latin'), face('tajawal-500-arabic'), face('tajawal-500-latin'),
  ]);
  const size = o.title.length > 70 ? 50 : o.title.length > 44 ? 60 : 70;
  const row = ar ? 'row-reverse' : 'row';
  return new ImageResponse(
    (
      <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
        padding: '64px 72px', color: '#EAF4F2', fontFamily: FAMILY,
        backgroundColor: '#0C2330',
        backgroundImage: 'radial-gradient(circle at 18% 12%, rgba(20,184,166,.30), transparent 48%), radial-gradient(circle at 92% 96%, rgba(227,192,101,.20), transparent 46%), linear-gradient(178deg,#173A4B 0%,#0C2330 40%,#06121B 100%)' }}>
        <div style={{ display: 'flex', flexDirection: row, alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', flexDirection: row, alignItems: 'center' }}>
            {/* decorative brand mark inside the image; the card's alt text is set by each route */}
            {/* oxlint-disable-next-line nextjs/no-img-element */}
            <img src={MARK} width={84} height={84} alt="QuotesDone mark" style={{ margin: '-14px' }} />
            <div style={{ display: 'flex', fontSize: 38, fontWeight: 800, margin: '0 22px' }}>QuotesDone</div>
          </div>
          <div style={{ display: 'flex', padding: '8px 20px', borderRadius: 999,
            border: '1px solid rgba(110,231,212,.35)', backgroundColor: 'rgba(110,231,212,.07)' }}>
            <Text text={o.kicker} size={22} weight={500} color="#6EE7D4" />
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: rtl ? 'flex-end' : 'flex-start' }}>
          <div style={{ display: 'flex', maxWidth: 1040 }}>
            <Text text={o.title} size={size} weight={800} lineHeight={1.2} />
          </div>
          {/* the redaction bar — the brand's own mark for a withheld identity */}
          <div style={{ display: 'flex', flexDirection: rtl ? 'row-reverse' : 'row', marginTop: 34 }}>
            {[150, 96, 210].map((w) => (
              <div key={w} style={{ width: w, height: 16, margin: '0 7px', backgroundColor: '#14303E', border: '1px solid rgba(110,231,212,.22)' }} />
            ))}
          </div>
        </div>
        <div style={{ display: 'flex', justifyContent: ar ? 'flex-end' : 'flex-start' }}>
          <Text text={FOOT[ar ? 'ar' : 'en']} size={24} weight={500} color="#9DB2B2" />
        </div>
      </div>
    ),
    {
      ...OG_SIZE,
      fonts: [
        { name: 'QD Latin', data: l800, weight: 800, style: 'normal' },
        { name: 'QD Latin', data: l500, weight: 500, style: 'normal' },
        { name: 'QD Arabic', data: a800, weight: 800, style: 'normal' },
        { name: 'QD Arabic', data: a500, weight: 500, style: 'normal' },
      ],
    },
  );
}
