import { mgmtRead, PROD_REF } from 'file:///C:/Users/Opera/quotesdone/scripts/staging/qd_guard.mjs';
const r = await mgmtRead(PROD_REF, `
  with i as (select id from public.inquiries where brief_source='qd_demo_fixture')
  select (select count(*) from public.notifications n, i where n.inquiry_id=i.id)::text notifs,
         (select count(*) from public.inquiry_matches m, i where m.inquiry_id=i.id)::text matches,
         (select count(*) from public.notifications where status='queued')::text queued_total,
         (select routing::text from public.inquiries, i where inquiries.id=i.id) routing`);
const x = r[0];
console.log(`notifications for the fixture: ${x.notifs}`);
console.log(`inquiry_matches for the fixture: ${x.matches}  (gate_incomplete_match held)`);
console.log(`routing (dispatched_at proves dispatch ran): ${x.routing}`);
console.log(`queued notifications on production, all causes: ${x.queued_total}`);
const bad = Number(x.notifs) > 0 || Number(x.matches) > 0 || /dispatched_at/.test(String(x.routing || ''));
console.log(bad ? '\nFENCE BREACH' : '\nFENCE HELD: nothing was matched, nothing was notified, nothing was dispatched.');
process.exit(bad ? 1 : 0);
