'use client';
// The supplier's profile score and ranked fixes (T3). English only: suppliers read English.
import { profileScore } from './profileScore';

const TAB_NAME = { documents: 'Documents', services: 'Services', profile: 'Profile' } as const;

export default function ProfileScore({ me, eligibility, go }: { me: any; eligibility: any; go: (where: string) => void }) {
  if (!me) return null;
  const { score, todo } = profileScore(me, eligibility);
  return (
    <section aria-labelledby="qd-profile-score-h" className="qd-panel mb-4 p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 id="qd-profile-score-h" className="font-head text-h3 tracking-snug text-foreground">Profile score</h2>
        <span className="font-head text-[22px] font-semibold tabular-nums text-foreground">{score}<span className="text-[14px] text-muted-foreground">/100</span></span>
      </div>
      <div className="mt-3 qd-meter" role="progressbar" aria-label="Profile score" aria-valuemin={0} aria-valuemax={100} aria-valuenow={score}>
        <span style={{ width: `${score}%` }} />
      </div>
      {todo.length === 0
        ? <p className="mt-3 text-copy text-muted-foreground">Your profile is complete.</p>
        : <ol className="mt-4 space-y-2">
          {todo.map((i) => (
            <li key={i.key} className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-copy text-foreground">{i.label} <span className="text-muted-foreground tabular-nums">(+{i.points})</span></span>
              <button type="button" className="min-h-11 rounded-md border border-border px-3 text-[13px] font-semibold hover:bg-muted focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
                onClick={() => go(i.tab)}>Go to {TAB_NAME[i.tab]}</button>
            </li>
          ))}
        </ol>}
    </section>
  );
}
