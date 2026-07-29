import { Reveal } from '@/components/motion/primitives';

/**
 * Shared, centered section intro for the reworked homepage. Presentational
 * only — it renders the content passed to it and adds no data or logic.
 * `index` is the mono section number shown inside the kicker chip.
 */
export function SectionHeader({
  eyebrow,
  index,
  title,
  sub,
  align = 'center',
}: {
  eyebrow: string;
  index: string;
  title: React.ReactNode;
  sub?: string;
  align?: 'center' | 'start';
}) {
  const centered = align === 'center';
  return (
    <Reveal
      className={
        centered ? 'mx-auto flex max-w-[62ch] flex-col items-center text-center' : 'flex flex-col items-start text-start'
      }
    >
      <span className="inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.04] px-3.5 py-1.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light backdrop-blur-sm">
        <span className="node-dot" aria-hidden />
        {eyebrow}
        <span className="tabular text-faint/60">/ {index}</span>
      </span>
      <h2 className="crisp mt-6 text-balance font-head text-[clamp(30px,4.4vw,54px)] font-semibold leading-[1.02] tracking-[-0.045em] text-white">
        {title}
      </h2>
      {sub ? (
        <p
          className={`mt-5 text-pretty text-[clamp(15.5px,1.7vw,18px)] leading-relaxed text-muted ${
            centered ? 'max-w-[58ch]' : 'max-w-[56ch]'
          }`}
        >
          {sub}
        </p>
      ) : null}
    </Reveal>
  );
}
