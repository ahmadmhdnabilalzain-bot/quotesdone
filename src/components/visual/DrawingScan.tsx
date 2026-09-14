'use client';
// An authored fit-out floor plan (original linework, no third-party art) is scanned top to bottom;
// the title block's contact fields are blacked out as the line passes, and BOQ rows assemble
// beside it. Quantities are shown as redaction-style bars — this is a demonstration, not an
// extraction, and it must never print a figure it did not measure.
import { useRef } from 'react';
import { useSceneGate, type SceneProps } from './gate';

const LOOP = 8; // seconds

const T = {
  en: {
    demo: 'Demonstration',
    boq: 'Bill of quantities',
    unit: 'Unit',
    fields: ['CLIENT', 'CONTRACTOR', 'TEL', 'EMAIL'],
    rows: [
      ['Gypsum board partition, 12.5 mm double layer', 'm²'],
      ['Suspended ceiling, mineral tile 600 × 600', 'm²'],
      ['Timber door set, single leaf', 'nr'],
      ['Porcelain floor tiling 600 × 600', 'm²'],
      ['Emulsion paint, two coats', 'm²'],
    ],
    alt: 'Demonstration: a floor-plan drawing is scanned, the contact details in its title block are hidden, and bill-of-quantities rows are built from the drawing.',
  },
  ar: {
    demo: 'عرض توضيحي',
    boq: 'جدول الكميات',
    unit: 'الوحدة',
    fields: ['CLIENT', 'CONTRACTOR', 'TEL', 'EMAIL'],
    rows: [
      ['قواطع جبس، طبقتان ١٢٫٥ مم', 'م²'],
      ['سقف معلّق، بلاطات معدنية ٦٠٠ × ٦٠٠', 'م²'],
      ['طقم باب خشبي، ضلفة واحدة', 'عدد'],
      ['تبليط أرضيات بورسلين ٦٠٠ × ٦٠٠', 'م²'],
      ['دهان إيملشن، طبقتان', 'م²'],
    ],
    alt: 'عرض توضيحي: يُمسح مخطط أرضي، وتُخفى بيانات الاتصال في جدول العنوان، وتُبنى بنود جدول الكميات من المخطط.',
  },
};

// Row i appears when the scan line crosses ~(22 + 12i)% of the loop; everything clears at 94%.
const rowKeyframes = T.en.rows
  .map((_, i) => {
    const s = 22 + i * 12;
    return `@keyframes qd-boq-${i}{0%,${s}%{opacity:0;transform:translateY(8px)}${s + 5}%,92%{opacity:1;transform:none}100%{opacity:0}}`;
  })
  .join('');

const CSS = `
@keyframes qd-scan{0%{transform:translateY(0);opacity:0}6%{opacity:1}80%{transform:translateY(300px);opacity:1}86%,100%{transform:translateY(300px);opacity:0}}
@keyframes qd-blackout{0%,62%{transform:scaleX(0)}70%,92%{transform:scaleX(1)}100%{transform:scaleX(0)}}
${rowKeyframes}
.qd-ds-run .qd-scan{animation:qd-scan ${LOOP}s linear infinite}
.qd-ds-run .qd-black{animation:qd-blackout ${LOOP}s cubic-bezier(.16,1,.3,1) infinite}
${T.en.rows.map((_, i) => `.qd-ds-run .qd-row-${i}{animation:qd-boq-${i} ${LOOP}s cubic-bezier(.16,1,.3,1) infinite}`).join('\n')}
.qd-black{transform-box:fill-box;transform-origin:left center}
`;

const LINE = { stroke: '#6EE7D4', strokeOpacity: 0.7, fill: 'none' } as const;
const THIN = { stroke: '#6EE7D4', strokeOpacity: 0.35, fill: 'none', strokeWidth: 0.6 } as const;

function Sheet({ fields }: { fields: string[] }) {
  return (
    <svg viewBox="0 0 320 300" className="h-full w-full" aria-hidden>
      <rect x="4" y="4" width="312" height="292" rx="6" fill="#0C2330" stroke="rgba(110,231,212,.19)" />
      {/* grid bubbles A–D / 1–4 */}
      {['A', 'B', 'C', 'D'].map((g, i) => (
        <g key={g}>
          <line x1={40 + i * 62} y1="22" x2={40 + i * 62} y2="206" {...THIN} strokeDasharray="4 3" />
          <circle cx={40 + i * 62} cy="18" r="7" {...THIN} />
          <text x={40 + i * 62} y="21" textAnchor="middle" fontSize="7" fill="#6EE7D4">{g}</text>
        </g>
      ))}
      {[1, 2, 3, 4].map((n, i) => (
        <g key={n}>
          <line x1="22" y1={40 + i * 54} x2="236" y2={40 + i * 54} {...THIN} strokeDasharray="4 3" />
          <circle cx="16" cy={40 + i * 54} r="7" {...THIN} />
          <text x="16" y={43 + i * 54} textAnchor="middle" fontSize="7" fill="#6EE7D4">{n}</text>
        </g>
      ))}
      {/* walls */}
      <path d="M40 40H226V202H40Z" {...LINE} strokeWidth="3" />
      <path d="M102 40V120M40 120H90M114 120H164M164 120V202M164 150H226" {...LINE} strokeWidth="2" />
      {/* door swings */}
      <path d="M90 120A24 24 0 0 1 114 96" {...THIN} />
      <path d="M90 120H114" {...THIN} />
      <path d="M164 174A24 24 0 0 0 188 150" {...THIN} />
      {/* dimension line */}
      <path d="M40 222H226M40 217V227M226 217V227" {...THIN} />
      <rect x="112" y="217" width="42" height="9" fill="#0C2330" />
      <path d="M118 222H148" stroke="#6EE7D4" strokeOpacity="0.5" strokeWidth="1.5" />
      {/* title block */}
      <path d="M244 204H312V292H244Z" {...THIN} />
      {fields.map((f, i) => (
        <g key={f}>
          <text x="248" y={216 + i * 20} fontSize="5.5" fill="#9DB2B2" letterSpacing="0.6">{f}</text>
          <path d={`M248 ${222 + i * 20}H${300 - i * 6}`} stroke="#EAF4F2" strokeOpacity="0.55" strokeWidth="2" />
          <rect className="qd-black" x="247" y={218 + i * 20} width={56 - i * 6} height="8" fill="#14303E" />
        </g>
      ))}
      {/* scan line */}
      <g className="qd-scan" style={{ transform: 'translateY(300px)', opacity: 0 }}>
        <rect x="4" y="0" width="312" height="18" fill="url(#qd-scan-glow)" />
        <line x1="4" y1="18" x2="316" y2="18" stroke="#14B8A6" strokeWidth="1.2" />
      </g>
      <defs>
        <linearGradient id="qd-scan-glow" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#14B8A6" stopOpacity="0" />
          <stop offset="1" stopColor="#14B8A6" stopOpacity="0.25" />
        </linearGradient>
      </defs>
    </svg>
  );
}

export default function DrawingScan({ locale }: SceneProps) {
  const ref = useRef<HTMLDivElement>(null);
  const { active } = useSceneGate(ref);
  const t = T[locale];

  return (
    <div ref={ref} dir={locale === 'ar' ? 'rtl' : 'ltr'} className={`relative flex h-full w-full flex-col gap-4 sm:flex-row ${active ? 'qd-ds-run' : ''}`}>
      <style>{CSS}</style>
      <div className="relative min-h-[220px] flex-1" dir="ltr">
        <Sheet fields={t.fields} />
      </div>
      <div className="flex flex-1 flex-col justify-center gap-2" aria-hidden>
        <div className="flex items-center justify-between pb-1 font-mono text-[10px] uppercase tracking-[0.16em] text-faint">
          <span>{t.boq}</span>
          <span className="rounded-full border border-[var(--line2)] px-2 py-0.5 normal-case tracking-normal">{t.demo}</span>
        </div>
        {t.rows.map(([desc, unit], i) => (
          <div key={desc} className={`qd-row-${i} flex items-center gap-3 rounded-lg border border-[var(--line)] bg-teal-light/[0.03] px-3 py-2.5`}>
            <span className="min-w-0 flex-1 text-[12.5px] leading-snug text-paper/90">{desc}</span>
            <span className="shrink-0 font-mono text-[10.5px] text-muted" title={t.unit}>{unit}</span>
            <span className="redact h-2.5 shrink-0" style={{ width: 28 + ((i * 17) % 26) }} />
          </div>
        ))}
      </div>
      <p className="sr-only">{t.alt}</p>
    </div>
  );
}
