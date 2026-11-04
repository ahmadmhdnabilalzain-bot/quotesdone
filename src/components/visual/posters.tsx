// Static posters: the first paint of every scene, and the whole scene under reduced motion,
// low-power or no-WebGL. Pure markup, no hooks, no client JS — this file is the only part of
// src/components/visual/** that dynamic()'s `loading` pulls towards the page, so it must stay tiny.
import type { Locale } from './gate';

const frame = 'relative h-full w-full overflow-hidden';

/** Hero: five sealed slabs in depth under the key light; the chosen one gold, its bar sliding off. */
export function HeroPoster() {
  const slabs = [
    { x: 18, y: 86, s: 0.62, o: 0.32 },
    { x: 292, y: 80, s: 0.66, o: 0.38 },
    { x: 70, y: 64, s: 0.82, o: 0.6 },
    { x: 226, y: 60, s: 0.84, o: 0.62 },
    { x: 136, y: 40, s: 1, o: 1, gold: true },
  ];
  return (
    <div className={frame} aria-hidden>
      <svg viewBox="0 0 420 280" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid meet">
        <defs>
          <linearGradient id="hp-slab" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#15303F" />
            <stop offset="1" stopColor="#0A1720" />
          </linearGradient>
          <linearGradient id="hp-cone" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#6EE7D4" stopOpacity=".22" />
            <stop offset="1" stopColor="#6EE7D4" stopOpacity="0" />
          </linearGradient>
          <radialGradient id="hp-gold" cx=".5" cy=".5" r=".5">
            <stop offset="0" stopColor="#E3C065" stopOpacity=".28" />
            <stop offset="1" stopColor="#E3C065" stopOpacity="0" />
          </radialGradient>
        </defs>
        <path d="M185 -10 L235 -10 L330 280 L90 280 Z" fill="url(#hp-cone)" />
        <ellipse cx="210" cy="150" rx="120" ry="110" fill="url(#hp-gold)" />
        {slabs.map((c, i) => (
          <g key={i} transform={`translate(${c.x} ${c.y}) scale(${c.s})`} opacity={c.o}>
            <rect width="148" height="196" rx="10" fill="url(#hp-slab)" stroke={c.gold ? '#F6DD8C' : 'rgba(110,231,212,.34)'} strokeWidth={c.gold ? 1.4 : 1} />
            <rect x="12" y="1" width="124" height="1" fill={c.gold ? '#F6DD8C' : 'rgba(110,231,212,.6)'} opacity=".7" />
            {c.gold ? (
              <>
                <rect x="16" y="20" width="62" height="12" rx="2" fill="#F6DD8C" opacity=".92" />
                <rect x="82" y="20" width="54" height="12" rx="2" fill="#1B3445" />
                <rect x="82" y="18" width="2" height="16" fill="#F6DD8C" />
              </>
            ) : (
              <rect x="16" y="20" width="96" height="12" rx="2" fill="#1B3445" />
            )}
            {[52, 70, 88, 106, 124].map((y, k) => (
              <rect key={y} x="16" y={y} width={[112, 84, 104, 70, 96][k]} height="3" rx="1.5" fill="rgba(110,231,212,.2)" />
            ))}
            <rect x="16" y="160" width="64" height="9" rx="2" fill={c.gold ? '#F6DD8C' : 'rgba(110,231,212,.4)'} />
          </g>
        ))}
      </svg>
    </div>
  );
}

// 14 Sep 2026: this poster was a faint glow and a caption, and the live map mounts only after the
// first interaction, so a visitor who did not scroll saw an empty box on /supplier. The poster now
// draws the map itself: a dotted outline of the UAE and the seven emirates at their real positions
// (lon/lat projected onto the 420x280 box). The scene still replaces it once it mounts.
const EMIRATES: { x: number; y: number; en: string; ar: string; below?: boolean }[] = [
  { x: 242, y: 133, en: 'Abu Dhabi', ar: 'أبوظبي', below: true },
  { x: 312, y: 84, en: 'Dubai', ar: 'دبي', below: true },
  { x: 322, y: 71, en: 'Sharjah', ar: 'الشارقة' },
  { x: 331, y: 64, en: 'Ajman', ar: 'عجمان' },
  { x: 336, y: 55, en: 'Umm Al Quwain', ar: 'أم القيوين' },
  { x: 362, y: 40, en: 'Ras Al Khaimah', ar: 'رأس الخيمة' },
  { x: 390, y: 88, en: 'Fujairah', ar: 'الفجيرة', below: true },
];

export function MapPoster({ locale }: { locale: Locale }) {
  const ar = locale === 'ar';
  return (
    <div className={frame} aria-hidden>
      <svg viewBox="0 0 420 280" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid meet">
        <defs>
          <pattern id="mp-dots" width="7" height="7" patternUnits="userSpaceOnUse">
            <circle cx="1.5" cy="1.5" r="1.1" fill="rgba(110,231,212,.28)" />
          </pattern>
          <radialGradient id="mp-glow" cx=".72" cy=".3" r=".6">
            <stop offset="0" stopColor="#14B8A6" stopOpacity=".16" />
            <stop offset="1" stopColor="#14B8A6" stopOpacity="0" />
          </radialGradient>
        </defs>
        <rect width="420" height="280" fill="url(#mp-glow)" />
        <path d="M18 176 L96 160 L168 150 L238 138 L286 104 L318 76 L346 48 L366 28 L382 40 L398 70 L396 118 L372 150 L330 196 L262 238 L180 252 L104 240 L44 214 Z"
          fill="url(#mp-dots)" stroke="rgba(110,231,212,.22)" strokeWidth="1" />
        {EMIRATES.map((e) => (
          <g key={e.en}>
            <circle cx={e.x} cy={e.y} r="6" fill="#14B8A6" opacity=".18" />
            <circle cx={e.x} cy={e.y} r="2.6" fill="#6EE7D4" />
            <text x={e.x} y={e.below ? e.y + 16 : e.y - 9} textAnchor="middle" fontSize="9"
              fill="rgba(238,246,244,.72)" fontFamily={ar ? 'var(--font-ar), sans-serif' : 'var(--font-body), sans-serif'}>
              {ar ? e.ar : e.en}
            </text>
          </g>
        ))}
      </svg>
      <span className="absolute bottom-3 inset-s-4 font-mono text-label uppercase tracking-caps text-faint">
        {ar ? 'الإمارات السبع' : 'Seven emirates'}
      </span>
    </div>
  );
}

/** Generic poster for the SVG diagrams: a sealed sheet with a redaction bar. */
export function SheetPoster() {
  return (
    <div className={`${frame} rounded-frame border border-line bg-navy-deep/60`} aria-hidden>
      <div className="absolute inset-x-[8%] top-[14%] flex flex-col gap-3">
        <span className="redact redact-bar" />
        {[92, 70, 84, 60].map((w) => (
          <span key={w} className="block h-[3px] rounded-full bg-(--line2)" style={{ width: `${w}%` }} />
        ))}
      </div>
    </div>
  );
}
