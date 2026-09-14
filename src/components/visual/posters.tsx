// Static posters: the first paint of every scene, and the whole scene under reduced motion,
// low-power or no-WebGL. Pure markup, no hooks, no client JS — this file is the only part of
// src/components/visual/** that dynamic()'s `loading` pulls towards the page, so it must stay tiny.
import type { Locale } from './gate';

const frame = 'relative h-full w-full overflow-hidden';

/** Hero: three redacted quote panels in depth, the chosen one lit gold. */
export function HeroPoster() {
  return (
    <div className={frame} aria-hidden>
      <div className="absolute inset-0 bg-[radial-gradient(60%_50%_at_70%_85%,rgba(227,192,101,.16),transparent_70%),radial-gradient(70%_60%_at_30%_20%,rgba(20,184,166,.14),transparent_70%)]" />
      <svg viewBox="0 0 400 260" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid meet">
        {[
          { x: 40, y: 70, s: 0.78, o: 0.5, gold: false },
          { x: 250, y: 64, s: 0.78, o: 0.5, gold: false },
          { x: 130, y: 52, s: 1, o: 1, gold: true },
        ].map((c, i) => (
          <g key={i} transform={`translate(${c.x} ${c.y}) scale(${c.s})`} opacity={c.o}>
            <rect width="140" height="170" rx="12" fill="rgba(12,35,48,.72)" stroke={c.gold ? '#E3C065' : 'rgba(110,231,212,.3)'} />
            <rect x="16" y="18" width={c.gold ? 40 : 86} height="12" rx="1" fill={c.gold ? 'rgba(227,192,101,.9)' : '#14303E'} />
            {[48, 66, 84, 102].map((y) => (
              <rect key={y} x="16" y={y} width={y % 36 ? 108 : 84} height="3" rx="1.5" fill="rgba(110,231,212,.22)" />
            ))}
            <rect x="16" y="138" width="60" height="8" rx="1" fill={c.gold ? '#E3C065' : 'rgba(110,231,212,.35)'} />
          </g>
        ))}
      </svg>
    </div>
  );
}

export function MapPoster({ locale }: { locale: Locale }) {
  return (
    <div className={frame} aria-hidden>
      <div className="absolute inset-[12%] rounded-[40%] bg-[radial-gradient(closest-side,rgba(20,184,166,.14),transparent)]" />
      <span className="absolute bottom-3 start-4 font-mono text-[12px] uppercase tracking-[0.18em] text-faint">
        {locale === 'ar' ? 'الإمارات السبع' : 'Seven emirates'}
      </span>
    </div>
  );
}

/** Generic poster for the SVG diagrams: a hairline sheet with a redaction bar. */
export function SheetPoster() {
  return (
    <div className={`${frame} rounded-[18px] border border-[var(--line)] bg-navy-deep/60`} aria-hidden>
      <div className="absolute inset-x-[8%] top-[14%] flex flex-col gap-3">
        <span className="redact redact-bar" />
        {[92, 70, 84, 60].map((w) => (
          <span key={w} className="block h-[3px] rounded-full bg-[var(--line2)]" style={{ width: `${w}%` }} />
        ))}
      </div>
    </div>
  );
}
