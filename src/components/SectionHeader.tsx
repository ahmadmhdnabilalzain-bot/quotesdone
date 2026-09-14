import s from '@/components/home/sealed.module.css';

/**
 * The homepage section intro: a mono index + eyebrow, one large h2, an optional sub. Start-aligned
 * by default (editorial), centred for the closing sections. Presentational only.
 */
export function SectionHeader({
  eyebrow,
  index,
  title,
  sub,
  align = 'start',
  aside,
}: {
  eyebrow: string;
  index: string;
  title: React.ReactNode;
  sub?: string;
  align?: 'center' | 'start';
  aside?: React.ReactNode;
}) {
  const centered = align === 'center';
  return (
    <div
      className={`${s.rise} flex flex-col gap-6 ${
        centered ? 'mx-auto max-w-[68ch] items-center text-center' : 'md:flex-row md:items-end md:justify-between'
      }`}
    >
      <div className={centered ? 'flex flex-col items-center' : 'max-w-[760px]'}>
        <span className={`${s.eyebrow} flex items-center gap-3 text-teal-light`}>
          <span className="font-mono tabular text-faint">{index}</span>
          <span className="h-px w-8 bg-teal/50" aria-hidden />
          {eyebrow}
        </span>
        <h2 className={`${s.h2} mt-6 text-balance font-head font-semibold text-white`}>{title}</h2>
        {sub ? <p className="mt-5 max-w-[58ch] text-pretty text-[clamp(15.5px,1.6vw,18px)] leading-relaxed text-muted">{sub}</p> : null}
      </div>
      {aside ? <div className="shrink-0">{aside}</div> : null}
    </div>
  );
}
