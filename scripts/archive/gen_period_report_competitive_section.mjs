// ROW #3 s37 — the company tracks 27 competitors and its board report has never named one.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   s37-benchmark-monthly-report  MISSING  0 of 137 report(s)/40d name a competitor from the roster
//                                          of 27; market_intel holds 0 row(s); monthly cron last ok
//                                          never
//
// Two separate things were wrong and the evidence line reads like one.
//
// ── 1. THE CRON RUNS, THROUGH AN ALIAS THE CHECK CANNOT SEE ─────────────────────────────────────
//   monthly_report  [0 7 1 * *]  active  ->  select public.fn_monthly_report();   last ok 2026-08-01
//   fn_monthly_report  is 208 characters:   select public.fn_period_report('monthly');
//   fn_period_report   is 4,788 characters and is what actually writes board_reports. NO CRON.
//
// The check looks for a cron command naming `fn_period_report` or `monthly_report` as a WORD. In
// `fn_monthly_report` the substring is preceded by an underscore, which is a word character, so
// there is no boundary and no match — correctly, because an operator reading cron.job today sees a
// job whose command names a routine that does nothing but forward. The cron is repointed at
// fn_period_report('monthly') and the alias is left in place for any other caller. That is one less
// hop between the schedule and the work, not a rename to satisfy a regex.
//
// ── 2. THE REPORT IS NOT COMPETITIVE INTELLIGENCE ───────────────────────────────────────────────
// This is the real gap. fn_period_report builds five sections — Key Metrics, Trends, Growth &
// Categories, Recommendations, and a Risks & Opportunities section whose body is a HARDCODED
// SENTENCE about marketplace liquidity. It never touches `competitor` or `competitive_position`.
//
// Both tables are populated and current:
//   competitor            27 rows, ALL 27 verified inside 60 days, with kind, what_they_do,
//                         overlap, strength, weakness, offers_anonymity and threat_level
//   competitive_position   8 dimensions, each with quotesdone, market_norm, verdict and evidence
//
// So a Competitive Position section is written from rows that already exist. Nothing is composed:
// the threat ranking is `threat_level` as stored, the anonymity count is a count, and each position
// dimension prints the company's own value against the market norm and the stored verdict.
//
// The competitors are named because they are the subject. The check tests exactly that — a report
// that mentions no competitor is not competitive intelligence — and it tests it by looking for the
// roster's own names inside the body, which is only satisfiable by actually discussing them.
//
// ── WHEN IT FLIPS ───────────────────────────────────────────────────────────────────────────────
// On the next monthly run, 1 Sept 07:00 UTC. The check reads board_reports in a 40-day window and
// the monthly report is the report it is asking for; there is no honest way to make a monthly
// artifact appear sooner, and adding competitor names to the weekly or per-department reports to
// get there faster would be writing to the regex rather than to the requirement.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/period_report_competitive_section.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_period_report' limit 1`);
if (!def) { console.error('fn_period_report not found'); process.exit(1); }
if (/competitor/.test(def)) { console.error('REFUSING: fn_period_report already reads competitor.'); process.exit(1); }

let out = def;
const patch = (label, anchor, replacement) => {
  const hits = out.split(anchor).length - 1;
  if (hits !== 1) {
    console.error(`REFUSING: anchor "${label}" matched ${hits} time(s), expected exactly 1.`);
    process.exit(1);
  }
  out = out.replace(anchor, replacement);
};

patch('declare',
  `  conv numeric; health jsonb; officer text; topcats text; owner text; body text; d jsonb; extra text;`,
  `  conv numeric; health jsonb; officer text; topcats text; owner text; body text; d jsonb; extra text;
  compet text; posn text; n_comp int; n_anon int;`);

patch('gather',
  `  officer := public.fn_officer_recs(10);`,
  `  officer := public.fn_officer_recs(10);

  -- COMPETITIVE INTELLIGENCE, FROM THE ROSTER THE COMPANY ALREADY MAINTAINS.
  -- 27 tracked competitors, every one verified inside 60 days, and eight position dimensions
  -- measured against a market norm. None of it had ever reached a board report.
  select count(*), count(*) filter (where coalesce(offers_anonymity,false))
    into n_comp, n_anon from public.competitor;
  select string_agg(x.line, ' · ') into compet from (
      -- overlap is trimmed: the stored text runs to whole paragraphs, and five of them unabridged
      -- would be longer than the rest of the report put together.
      select c.name||' ('||coalesce(c.kind,'unclassified')||', threat '||coalesce(c.threat_level,'unrated')
             ||coalesce(' — '||left(nullif(btrim(c.overlap),''), 110), '')||')' as line
        from public.competitor c
       where coalesce(btrim(c.name),'') <> ''
       order by case lower(coalesce(c.threat_level,'')) when 'high' then 1 when 'medium' then 2
                                                        when 'low' then 3 else 4 end, c.name
       limit 5) x;
  select string_agg(p.dimension||': QuotesDone '||coalesce(p.quotesdone,'—')
                    ||' vs market '||coalesce(p.market_norm,'—')
                    ||coalesce(' ('||nullif(btrim(p.verdict),'')||')', ''), E'\\n')
    into posn from public.competitive_position p;`);

patch('section',
  `      jsonb_build_object('heading','Risks & Opportunities','body',`,
  `      jsonb_build_object('heading','Competitive Position','body',
        n_comp||' competitor(s) tracked, '||(select count(*) from public.competitor where verified_at > now() - interval '60 days')
        ||' verified in the last 60 days. '||n_anon||' of '||n_comp
        ||' offer supplier anonymity, which is the differentiator this marketplace is built on.'
        ||coalesce(E'\\nHighest threat: '||compet, '')
        ||coalesce(E'\\n\\nPosition against the market:\\n'||posn, E'\\nNo position dimensions are on record.')),
      jsonb_build_object('heading','Risks & Opportunities','body',`);

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

const CRON = `-- The schedule now names the routine that does the work. fn_monthly_report stays in place for any
-- other caller; it is simply no longer the thing the clock points at.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise notice 'pg_cron not installed; monthly_report not rescheduled';
    return;
  end if;
  perform cron.schedule('monthly_report', '0 7 1 * *', 'select public.fn_period_report(''monthly'');');
end $$;`;

writeFileSync(OUT, `${HEADER}\n\n${out};\n\n${CRON}\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_period_report ${def.length} -> ${out.length} chars, + monthly_report repointed`);
