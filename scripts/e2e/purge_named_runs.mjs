// scripts/e2e/purge_named_runs.mjs - it_engineer, 2 Nov 2026. Remove the fixtures of runs NAMED on the command line, by exact tag.
//   node scripts/e2e/purge_named_runs.mjs <tag> [<tag> ...]      (QD_FIXTURES=1 and the Supabase token, i.e. Actions)
// List first, then the harness's own teardown per tag (never a broad delete - a-big-batch-delete-restarted-production),
// then close the tag's window, then re-count. A tag is refused if any lead carrying it is not a ZZ DEMO lead, if it is
// the founder's demo, or if its window is still open and was opened less than 30 minutes ago (a run in progress).
import { newRun, teardown, closeRehearsalWindow, q } from '../lib/demo_factory.mjs';
import { read, leftovers } from './fixtures.mjs';

const tags = process.argv.slice(2);
if (!tags.length || tags.some((t) => !/^[a-z0-9]{8}$/.test(t) || t === 'founderdemo')) { console.error('give 8-character run tags, never founderdemo'); process.exit(2); }

const list = async (t) => ({
  tag: t,
  auth: await read(`select id, email from auth.users where email like ${q(`qd-${t}-%@example.invalid`)} or email like ${q(`delivered+qd-${t}-%@resend.dev`)} order by created_at`),
  leads: await read(`select id, company_name from public.leads where ${q('qd_run:' + t)} = any(coalesce(tags,'{}'))`),
  windows: await read(`select run_tag, ended_at, expires_at from public.rehearsal_window where run_tag = ${q('qd_run:' + t)}`),
});

let bad = 0;
for (const t of tags) {
  const before = await list(t);
  console.log('BEFORE', JSON.stringify(before));
  const real = before.leads.filter((l) => !/^ZZ DEMO/.test(l.company_name || ''));
  if (real.length) { console.error(`REFUSED ${t}: lead(s) ${real.map((l) => l.id)} are not ZZ DEMO`); bad++; continue; }
  const [live] = await read(`select count(*)::int n from public.rehearsal_window where run_tag = ${q('qd_run:' + t)} and ended_at is null and expires_at > now() + interval '90 minutes'`);
  if (live.n) { console.error(`REFUSED ${t}: its window opened under 30 minutes ago and is still open`); bad++; continue; }
  try {
    const td = await teardown(newRun({ tag: t, quiet: true }));
    console.log('TORN DOWN', t, td.summary);
  } catch (e) { console.error(`TEARDOWN FAILED ${t}: ${e.message}`); bad++; }
  await closeRehearsalWindow(t);
  const after = await list(t);
  const left = await leftovers({ tag: t, ids: { inquiries: new Set(), quotes: new Set(), leads: new Set() } });
  console.log('AFTER', JSON.stringify(after), 'leftovers', JSON.stringify(left));
  if (after.auth.length || after.leads.length || after.windows.some((w) => !w.ended_at) || left.total) { console.error(`LEFT BEHIND ${t}`); bad++; }
}
process.exit(bad ? 1 : 0);
