// THE SERVICE EMIRATES ARE CHECKBOXES (founder, 15 Sep 2026): one checkbox per emirate plus "All
// emirates", in English and Arabic, never typed. They were pressed-state chip buttons (PR #695): a
// screen reader announced "toggle button", and there was no way to pick all seven at once. The value
// is unchanged — the English emirate names save_profile stores in leads.service_emirates, from which
// leads.emirate is derived server-side (#702).
import { useId } from 'react';
import { emirateLabel } from './serverCopy';

export const UAE_EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'] as const;

type Props = { lang: string; value: string[]; onChange: (next: string[]) => void; legend: React.ReactNode };

export default function EmirateCheckboxes({ lang, value, onChange, legend }: Props) {
  const id = useId();
  const ar = lang === 'ar';
  const picked = UAE_EMIRATES.filter((e) => value.includes(e));
  const all = picked.length === UAE_EMIRATES.length;
  const some = picked.length > 0 && !all;
  const toggle = (e: string) => onChange(value.includes(e) ? value.filter((x) => x !== e) : [...value, e]);
  const box = 'h-5 w-5 shrink-0 rounded border-input accent-[hsl(var(--primary))] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring';
  const row = 'flex min-h-11 cursor-pointer items-center gap-2.5 rounded-md border border-border px-3 text-[13.5px] text-foreground hover:bg-muted/40';
  return (
    <fieldset className="mt-1.5">
      <legend className="text-[13px] font-semibold leading-[1.65] text-muted-foreground">{legend}</legend>
      <label className={row + ' mt-2 w-fit font-semibold'} htmlFor={id + '-all'}>
        <input id={id + '-all'} type="checkbox" className={box} checked={all}
               ref={(el) => { if (el) el.indeterminate = some; }}
               aria-checked={some ? 'mixed' : all}
               onChange={() => onChange(all ? value.filter((x) => !(UAE_EMIRATES as readonly string[]).includes(x)) : [...new Set([...value, ...UAE_EMIRATES])])} />
        {ar ? 'كل الإمارات' : 'All emirates'}
      </label>
      <div className="mt-2 grid grid-cols-1 gap-2 min-[420px]:grid-cols-2 sm:grid-cols-3">
        {UAE_EMIRATES.map((e) => (
          <label key={e} className={row} htmlFor={id + '-' + e}>
            <input id={id + '-' + e} type="checkbox" className={box} checked={value.includes(e)} onChange={() => toggle(e)} />
            {emirateLabel(lang, e)}
          </label>
        ))}
      </div>
    </fieldset>
  );
}
