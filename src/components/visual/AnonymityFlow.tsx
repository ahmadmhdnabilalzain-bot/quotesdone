'use client';
// Two-way anonymity: the brief travels customer → platform → suppliers with the customer masked,
// quotes travel back with every supplier masked, and only at the reveal do the two chosen parties
// see each other. SMIL packets, three phases on a timer; paused off-screen, static under
// reduced motion. In Arabic the diagram mirrors (customer on the right), text does not.
import { useEffect, useRef, useState } from 'react';
import { prefersReducedMotion, useSceneGate, type SceneProps } from './gate';

const T = {
  en: { customer: 'Customer', platform: 'QuotesDone', supplier: 'Supplier', hidden: 'identity hidden', revealed: 'name · licence · contact', steps: ['Brief goes out, you stay anonymous', 'Quotes come back, suppliers stay anonymous', 'You reveal one — 3% — both sides see each other'],
    alt: 'Diagram: the customer’s brief passes through QuotesDone to several suppliers without the customer’s identity. Quotes return through QuotesDone without the suppliers’ identities. Only when the customer pays the 3% reveal fee for one quote do that customer and that supplier see each other.' },
  ar: { customer: 'العميل', platform: 'كوتس دن', supplier: 'المورّد', hidden: 'الهوية مخفية', revealed: 'الاسم · الرخصة · التواصل', steps: ['يُرسل الطلب وتبقى هويتك مخفية', 'تعود العروض وتبقى هوية المورّدين مخفية', 'تكشف عرضًا واحدًا — ٣٪ — فيرى الطرفان بعضهما'],
    alt: 'مخطط: يمر طلب العميل عبر كوتس دن إلى عدة مورّدين دون هوية العميل، وتعود العروض عبر كوتس دن دون هوية المورّدين. ولا يرى العميل والمورّد بعضهما إلا عند دفع رسوم الكشف ٣٪ لعرض واحد.' },
};

const VW = 600;
const SUP_Y = [70, 150, 230];
const CHOSEN = 1;
const PHASE_MS = 3200;

export default function AnonymityFlow({ locale }: SceneProps) {
  const ref = useRef<HTMLDivElement>(null);
  const svg = useRef<SVGSVGElement>(null);
  const { active } = useSceneGate(ref);
  const [phase, setPhase] = useState(2);
  const t = T[locale];
  const rtl = locale === 'ar';
  const X = (x: number) => (rtl ? VW - x : x);
  const still = !active || prefersReducedMotion();

  useEffect(() => {
    if (still) return;
    const id = setInterval(() => setPhase((p) => (p + 1) % 3), PHASE_MS);
    return () => clearInterval(id);
  }, [still]);
  useEffect(() => {
    if (still) svg.current?.pauseAnimations();
    else svg.current?.unpauseAnimations();
  }, [still]);

  const custPath = `M${X(118)} 150 C${X(190)} 150 ${X(200)} 150 ${X(262)} 150`;
  const supPath = (y: number) => `M${X(338)} 150 C${X(400)} 150 ${X(410)} ${y} ${X(468)} ${y}`;
  const revealed = phase === 2;
  const gold = (on: boolean) => (on ? '#E3C065' : 'rgba(110,231,212,.35)');

  const Packet = ({ d, reverse, delay = 0 }: { d: string; reverse?: boolean; delay?: number }) =>
    still ? null : (
      <circle r="3.4" fill={reverse ? '#E3C065' : '#6EE7D4'}>
        <animateMotion dur="1.4s" begin={`${delay}s`} repeatCount="2" path={d} keyPoints={reverse ? '1;0' : '0;1'} keyTimes="0;1" calcMode="spline" keySplines=".16 1 .3 1" />
      </circle>
    );

  const Label = ({ x, y, title, open }: { x: number; y: number; title: string; open: boolean }) => (
    <g>
      <text x={x} y={y} textAnchor="middle" fill="#EAF4F2" fontSize={rtl ? 13 : 12} fontWeight={600} fontFamily="var(--font-head), system-ui">{title}</text>
      <text x={x} y={y + 16} textAnchor="middle" fill={open ? '#E3C065' : '#9DB2B2'} fontSize="9.5" fontFamily="var(--font-body), system-ui">{open ? t.revealed : t.hidden}</text>
      <rect x={x - 42} y={y + 7} width="84" height="12" rx="1" fill="#14303E" style={{ transformBox: 'fill-box', transformOrigin: rtl ? 'right center' : 'left center', transform: open ? 'scaleX(0)' : 'scaleX(1)', transition: 'transform .7s cubic-bezier(.16,1,.3,1)' }} />
    </g>
  );

  return (
    <div ref={ref} className="relative w-full">
      <svg ref={svg} key={phase} viewBox={`0 0 ${VW} 300`} className="h-auto w-full" aria-hidden>
        <path d={custPath} fill="none" stroke={gold(revealed)} strokeWidth="1.4" style={{ transition: 'stroke .6s' }} />
        {SUP_Y.map((y, i) => (
          <path key={y} d={supPath(y)} fill="none" stroke={gold(revealed && i === CHOSEN)} strokeWidth={revealed && i === CHOSEN ? 1.8 : 1.2} strokeDasharray={revealed && i !== CHOSEN ? '3 4' : undefined} style={{ transition: 'stroke .6s' }} />
        ))}

        {/* customer */}
        <circle cx={X(80)} cy="150" r="36" fill="#0C2330" stroke={gold(revealed)} />
        <circle cx={X(80)} cy="141" r="8" fill="none" stroke="#6EE7D4" strokeOpacity=".7" />
        <path d={`M${X(80) - 14} 166a14 11 0 0 1 28 0`} fill="none" stroke="#6EE7D4" strokeOpacity=".7" />
        <Label x={X(80)} y={212} title={t.customer} open={revealed} />

        {/* platform */}
        <path d={`M${X(300)} 104 l40 23 v46 l-40 23 l-40 -23 v-46 z`} fill="#0C2330" stroke="#14B8A6" strokeWidth="1.4" />
        <path d={`M${X(288)} 150 h24 M${X(300)} 138 v24`} stroke="#6EE7D4" strokeOpacity=".5" />
        <text x={X(300)} y="224" textAnchor="middle" fill="#6EE7D4" fontSize="11" fontWeight={600} fontFamily="var(--font-head), system-ui">{t.platform}</text>

        {/* suppliers */}
        {SUP_Y.map((y, i) => {
          const open = revealed && i === CHOSEN;
          return (
            <g key={y} opacity={revealed && !open ? 0.45 : 1} style={{ transition: 'opacity .6s' }}>
              <rect x={X(rtl ? 540 : 468)} y={y - 20} width="72" height="40" rx="8" fill="#0C2330" stroke={gold(open)} />
              <text x={X(504)} y={y + 4} textAnchor="middle" fill="#EAF4F2" fontSize="11" fontFamily="var(--font-head), system-ui">{t.supplier} {'ABC'[i]}</text>
              <rect x={X(504) - 26} y={y + 8} width="52" height="6" rx="1" fill="#14303E" style={{ transformBox: 'fill-box', transformOrigin: 'center', transform: open ? 'scaleX(0)' : 'scaleX(1)', transition: 'transform .7s cubic-bezier(.16,1,.3,1)' }} />
            </g>
          );
        })}

        {phase === 0 && (
          <>
            <Packet d={custPath} />
            {SUP_Y.map((y, i) => <Packet key={y} d={supPath(y)} delay={0.6 + i * 0.12} />)}
          </>
        )}
        {phase === 1 && (
          <>
            {SUP_Y.map((y, i) => <Packet key={y} d={supPath(y)} reverse delay={i * 0.15} />)}
            <Packet d={custPath} reverse delay={0.7} />
          </>
        )}

        {revealed && (
          <g>
            <rect x={X(300) - 34} y="72" width="68" height="20" rx="10" fill="#E3C065" />
            <text x={X(300)} y="86" textAnchor="middle" fill="#2A2000" fontSize="10" fontWeight={700} fontFamily="var(--font-mono), monospace">{rtl ? 'الكشف ٣٪' : 'Reveal · 3%'}</text>
          </g>
        )}
      </svg>
      <p className="mt-2 text-center text-[12.5px] text-muted" dir={rtl ? 'rtl' : 'ltr'} aria-live="off">{t.steps[phase]}</p>
      <p className="sr-only">{t.alt}</p>
    </div>
  );
}
