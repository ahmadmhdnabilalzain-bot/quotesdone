'use client';
// The seven emirates as a 2.5D dot matrix. Outlines are deliberately stylised (hand-drawn
// polygons in a 400×280 east/south plane, not survey data) and the pulses are decoration — the
// map carries no counts and must never be given any it cannot measure.
import { useRef } from 'react';
import { useSceneGate, type SceneProps } from './gate';

type Pt = [number, number];
type Emirate = { en: string; ar: string; poly: Pt[]; label: Pt };

// Small emirates first: a dot takes the first polygon that contains it.
const EMIRATES: Emirate[] = [
  { en: 'Ajman', ar: 'عجمان', poly: [[272, 55], [280, 50], [286, 58], [282, 70]], label: [238, 28] },
  { en: 'Umm Al Quwain', ar: 'أم القيوين', poly: [[280, 50], [292, 40], [298, 52], [286, 58]], label: [262, 6] },
  { en: 'Dubai', ar: 'دبي', poly: [[235, 90], [250, 70], [262, 62], [275, 95], [270, 125], [255, 120]], label: [196, 70] },
  { en: 'Sharjah', ar: 'الشارقة', poly: [[262, 62], [272, 55], [282, 70], [300, 90], [292, 120], [275, 120], [275, 95]], label: [300, 150] },
  { en: 'Ras Al Khaimah', ar: 'رأس الخيمة', poly: [[292, 40], [310, 15], [325, 30], [318, 70], [300, 90], [282, 70], [286, 58], [298, 52]], label: [330, 4] },
  { en: 'Fujairah', ar: 'الفجيرة', poly: [[318, 70], [325, 42], [344, 60], [347, 110], [336, 140], [306, 128], [300, 90]], label: [372, 96] },
  { en: 'Abu Dhabi', ar: 'أبوظبي', poly: [[10, 150], [60, 140], [120, 130], [170, 118], [215, 96], [235, 90], [255, 120], [290, 160], [302, 176], [262, 262], [40, 262]], label: [110, 214] },
];

const inside = ([x, y]: Pt, poly: Pt[]) => {
  let hit = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
  }
  return hit;
};
// Oblique projection: the plane tilts away from the viewer, east rises slightly.
const proj = ([x, y]: Pt): Pt => [x * 0.92 + y * 0.48 + 10, y * 0.52 - x * 0.12 + 62];

const STEP = 6.5;
const DOTS: { p: Pt; e: number }[] = [];
for (let y = 0; y < 280; y += STEP)
  for (let x = 0; x < 400; x += STEP) {
    const e = EMIRATES.findIndex((em) => inside([x, y], em.poly));
    if (e >= 0) DOTS.push({ p: proj([x, y]), e });
  }
const CENTRES: Pt[] = EMIRATES.map((_, e) => {
  const own = DOTS.filter((d) => d.e === e);
  return [own.reduce((s, d) => s + d.p[0], 0) / own.length, own.reduce((s, d) => s + d.p[1], 0) / own.length];
});
const TINT = ['#6EE7D4', '#6EE7D4', '#14B8A6', '#6EE7D4', '#14B8A6', '#6EE7D4', '#14B8A6'];

export default function EmiratesMap({ locale }: SceneProps) {
  const ref = useRef<HTMLDivElement>(null);
  const { active } = useSceneGate(ref);
  const names = EMIRATES.map((e) => e[locale]).join(locale === 'ar' ? '، ' : ', ');

  return (
    <div ref={ref} className="relative h-full w-full">
      <style>{`@keyframes qd-map-pulse{0%{transform:scale(.4);opacity:.9}100%{transform:scale(3.2);opacity:0}}
.qd-map-ring{transform-box:fill-box;transform-origin:center;animation:qd-map-pulse 3.2s cubic-bezier(.16,1,.3,1) infinite}`}</style>
      <svg viewBox="0 0 520 240" className="h-full w-full" aria-hidden preserveAspectRatio="xMidYMid meet">
        {/* extrusion: a darker copy of each dot, dropped below it */}
        {DOTS.map((d, i) => (
          <circle key={`s${i}`} cx={d.p[0]} cy={d.p[1] + 4} r={1.5} fill="#0F2231" />
        ))}
        {DOTS.map((d, i) => (
          <circle key={i} cx={d.p[0]} cy={d.p[1]} r={1.6} fill={TINT[d.e]} opacity={0.5} />
        ))}
        {CENTRES.map(([cx, cy], e) => (
          <g key={e}>
            <circle
              className="qd-map-ring"
              cx={cx}
              cy={cy}
              r={4}
              fill="none"
              stroke={e === 2 ? '#6EE7D4' : '#14B8A6'}
              strokeWidth={0.8}
              style={{ animationDelay: `${e * 0.45}s`, animationPlayState: active ? 'running' : 'paused' }}
            />
            <circle cx={cx} cy={cy} r={2.6} fill={e === 2 ? '#EEF6F4' : '#6EE7D4'} />
          </g>
        ))}
        {EMIRATES.map((em, e) => {
          const [lx, ly] = [em.label[0] * 1.05, em.label[1] + 18];
          const [cx, cy] = CENTRES[e];
          return (
            <g key={em.en}>
              <line x1={cx} y1={cy} x2={lx} y2={ly + 3} stroke="rgba(110,231,212,.28)" strokeWidth={0.6} />
              <text x={lx} y={ly} textAnchor="middle" fill="#EEF6F4" fontSize={locale === 'ar' ? 11 : 9.5} fontFamily="var(--font-body), system-ui" letterSpacing={locale === 'ar' ? 0 : 0.4}>
                {em[locale]}
              </text>
            </g>
          );
        })}
      </svg>
      <p className="sr-only">
        {locale === 'ar' ? `خريطة توضيحية للإمارات السبع: ${names}.` : `Illustrative map of the seven emirates: ${names}.`}
      </p>
    </div>
  );
}
