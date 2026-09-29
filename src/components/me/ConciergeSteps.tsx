// @ts-nocheck
// THE FIRST-REQUEST CONCIERGE (customer_support, 29 Sep 2026; founder ledger 1018).
//
// The guidance customer_api returns (action 'concierge', and `concierge` on every create_inquiry answer):
// four steps - describe the job, attach PDF or CAD (DWG/DXF) drawings only (ruling 1000), give the trade's
// specs from its verified pack, what happens next - and, for a request held for its specs, exactly what is
// missing. Every sentence is written by the server in the customer's language
// (scripts/sql/customer_support_guides_a_first_request_step_by_step_and_asks_a_held_one_for_its_specs.sql);
// this component only lays it out, so the portal and the e-mail cannot say two different things.
import { t } from './portalText';

export function ConciergeSteps({ guide, lang, title, held = null, className = '' }) {
  if (!guide || !Array.isArray(guide.steps) || !guide.steps.length) return null;
  const missing = held && held.held && Array.isArray(held.missing) ? held.missing : [];
  return (
    <details open className={'rounded-xl border border-primary/30 bg-primary/5 px-3 py-2 text-[12.5px] ' + className} data-testid="concierge">
      <summary className="cursor-pointer font-semibold text-foreground">{title}</summary>
      {missing.length ? (
        <div className="mt-1.5">
          <p className="font-semibold text-foreground">{t(lang, 'cg_missing')}</p>
          <ul className="ms-4 list-disc text-muted-foreground">{missing.map((m) => <li key={m.key}>{m.ask}</li>)}</ul>
        </div>
      ) : null}
      <ol className="ms-4 mt-1.5 list-decimal space-y-1.5 text-muted-foreground">
        {guide.steps.map((s) => (
          <li key={s.key}><b className="text-foreground">{s.title}</b><div className="whitespace-pre-line">{s.body}</div></li>
        ))}
      </ol>
    </details>
  );
}
