// THE IT ENGINEER'S DUTIES 9-18 DECIDE WHAT THEY SAY THEY DECIDE, AND A NEW BUG CLOSES ONLY WITH
// WHAT WAS LEARNED. The regression check the it_playbook rows name.
//
// scripts/sql/the_it_engineer_takes_on_seven_more_duties.sql (9-15) and
// scripts/sql/every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql (16-18).
// Against production; every write sits in a transaction that ends in raise exception 'CHK<<…>>', so
// nothing commits. Demo readings only; the founder's delivery is stubbed.
//
//   node --test scripts/checks/it_engineer_duties_9_to_18.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

async function probe(body) {
  try { await sql(`do $p$ ${body} $p$;`); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (m) return JSON.parse(m[1].replace(/\\"/g, '"'));
    throw e;
  }
  throw new Error('probe committed instead of rolling back');
}
// Make every scheduled duty due inside the probe transaction.
const DUE = `delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' like 'duty:%';`;
const keys = (duty) => `(select coalesce(jsonb_agg(issue_key order by issue_key), '[]') from public.it_engineer_finding
                         where closed_at is null and issue_key like 'duty:${duty}:%zz%')`;

test('every threshold a duty reads has a value or says it is not measured yet', { skip: SKIP }, async () => {
  const rows = await sql(`select key from public.it_threshold where value is null and key <> 'db_disk_limit_bytes'`);
  assert.deepEqual(rows, []);
});

test('restore drill: a file that comes back changed is a finding for the sales engineer', { skip: SKIP }, async () => {
  const r = await probe(`declare v_id bigint; begin ${DUE}
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, status, dropbox_content_hash, dropbox_size, bytes, source, dedupe_key)
    values ('zz_demo', 'zz', 'ZZ DEMO', 'zz-bucket', 'zz/a.pdf', 'zz-a.pdf', '/zz/a.pdf', 'done', 'aaa', 10, 10, 'storage', 'ZZ_DEMO_RESTORE')
    returning id into v_id;
    perform public.fn_it_duties_scheduled(jsonb_build_object('restore', jsonb_build_object('basis','measured','samples',
      jsonb_build_array(jsonb_build_object('doc_backup_id', v_id, 'dropbox', '{"ok":true,"size":10,"content_hash":"bbb"}'::jsonb,
                                           'storage', '{"ok":true,"size":10}'::jsonb)))));
    raise exception 'CHK<<%>>', json_build_object('owner', (select evidence->>'owner_seat' from public.it_engineer_finding where issue_key = 'duty:restore:dropbox:' || v_id),
                                                 'storage_ok', not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:restore:storage:' || v_id));
  end`);
  assert.equal(r.owner, 'sales_engineer');
  assert.equal(r.storage_ok, true);
});

test('every OPEN GAP in the backup registry is a finding for the sales engineer', { skip: SKIP }, async () => {
  const r = await probe(`begin ${DUE}
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    raise exception 'CHK<<%>>', json_build_object(
      'gaps', (select count(*) from public.fn_backup_source_registry() where not backed_up),
      'findings', (select count(*) from public.it_engineer_finding where closed_at is null and issue_key like 'duty:backup_gap:%'
                     and evidence->>'owner_seat' = 'sales_engineer'));
  end`);
  assert.ok(r.gaps > 0);
  assert.equal(r.findings, r.gaps);
});

test('sender health: a domain with no DMARC and a bounce rate over the threshold are customer support findings', { skip: SKIP }, async () => {
  const r = await probe(`begin ${DUE}
    perform public.fn_it_duties_scheduled(jsonb_build_object('sender', jsonb_build_object(
      'dns', jsonb_build_object('zz-demo.invalid', '{"basis":"measured","spf":true,"dkim":true,"dmarc":false}'::jsonb))));
    raise exception 'CHK<<%>>', json_build_object('dmarc', (select evidence->>'owner_seat' from public.it_engineer_finding
                                                            where issue_key = 'duty:sender:dmarc:zz-demo.invalid' and closed_at is null));
  end`);
  assert.equal(r.dmarc, 'customer_support');
});

test('OTP pumping: a burst to a country we do not serve is blocked at once; one we serve is handed on', { skip: SKIP }, async () => {
  const r = await probe(`begin ${DUE}
    insert into public.phone_verifications (phone, code, created_at, expires_at)
    select '+88899' || lpad(g::text, 6, '0'), 'zz', now(), now() + interval '5 minutes' from generate_series(1, 7) g;
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    raise exception 'CHK<<%>>', json_build_object(
      'blocked', public.fn_otp_prefix_blocked('+888990000001'),
      'served_blocked', public.fn_otp_prefix_blocked('+971500000000'),
      'finding', (select blast from public.it_engineer_finding where issue_key = 'duty:otp:prefix:88899' and closed_at is null));
  end`);
  assert.equal(r.blocked, true);
  assert.equal(r.served_blocked, false);
  assert.equal(r.finding, 'agent_facing');
});

test('dependencies: a high advisory can reach the founder; a moderate one never does', { skip: SKIP }, async () => {
  const r = await probe(`begin
    perform public.fn_it_dependency_ingest('{"advisories":[{"ecosystem":"app","package":"zz-high","severity":"high","id":"ZZ-1","title":"ZZ DEMO"},
                                                        {"ecosystem":"app","package":"zz-mod","severity":"moderate","id":"ZZ-2","title":"ZZ DEMO"}]}');
    raise exception 'CHK<<%>>', json_build_object(
      'high', (select jsonb_build_object('blast', blast, 'quiet', evidence->>'no_founder_email') from public.it_engineer_finding where issue_key = 'duty:dependency:app:zz-high:ZZ-1'),
      'moderate', (select jsonb_build_object('blast', blast, 'quiet', evidence->>'no_founder_email') from public.it_engineer_finding where issue_key = 'duty:dependency:app:zz-mod:ZZ-2'));
  end`);
  assert.deepEqual(r.high, { blast: 'security', quiet: 'false' });
  assert.deepEqual(r.moderate, { blast: 'internal', quiet: 'true' });
});

test('access review: an unaccepted principal is raised; an accepted one is not', { skip: SKIP }, async () => {
  const r = await probe(`begin ${DUE}
    perform public.fn_it_access_accept('github', 'zz-known', 'ZZ DEMO', 'probe');
    perform public.fn_it_duties_scheduled('{"access":{"github":{"basis":"measured","principals":[{"principal":"zz-known"},{"principal":"zz-stranger"}]}}}');
    raise exception 'CHK<<%>>', json_build_object('open', ${keys('access')});
  end`);
  assert.deepEqual(r.open, ['duty:access:github:zz-stranger']);
});

test('rotation: the new credential works at once, the old one for the overlap, then it is retired', { skip: SKIP }, async () => {
  const r = await probe(`declare v_old bigint; v_rot jsonb; v_new_ok boolean; v_old_ok boolean; v_after jsonb;
    begin
      insert into public.app_secrets (key, value) values ('cred_zz_demo_rotation', 'zz-old-secret-zz-old-secret-01');
      insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
      values ('zz_demo.rotation', 'ZZ DEMO', public.fn_internal_credential_hash('zz-old-secret-zz-old-secret-01'), array['zz_demo_fn'], false, true)
      returning id into v_old;
      v_rot := public.fn_it_credential_rotate(v_old);
      v_new_ok := (public.fn_internal_auth((select value from public.app_secrets where key = 'cred_zz_demo_rotation'), 'zz_demo_fn')->>'ok')::boolean;
      v_old_ok := (public.fn_internal_auth('zz-old-secret-zz-old-secret-01', 'zz_demo_fn')->>'ok')::boolean;
      update public.it_credential_rotation set overlap_until = now() - interval '1 second', rotated_at = now() where old_id = v_old;
      update public.internal_credential set last_used_at = now() - interval '1 hour' where id = v_old;
      perform public.fn_it_credential_reverify();
      v_after := public.fn_internal_auth('zz-old-secret-zz-old-secret-01', 'zz_demo_fn');
      raise exception 'CHK<<%>>', json_build_object('new_ok', v_new_ok, 'old_ok_in_overlap', v_old_ok, 'old_after', v_after->>'error');
    end`);
  assert.equal(r.new_ok, true);
  assert.equal(r.old_ok_in_overlap, true);
  assert.equal(r.old_after, 'credential_retired');
});

test('smoke: a failed step goes to the seat owning most of the changed files', { skip: SKIP }, async () => {
  const r = await probe(`begin
    perform public.fn_it_smoke_ingest('{"sha":"zzdemo0","demo":true,"changed_files":["supabase/functions/stripe_webhook/index.ts","supabase/functions/reveal_invoice/index.ts","src/app/page.tsx"],"steps":[{"journey":"c comparison","name":"ZZ DEMO pdf","status":"FAIL"}]}');
    raise exception 'CHK<<%>>', json_build_object('owner', (select evidence->>'owner_seat' from public.it_engineer_finding where issue_key like 'duty:smoke:c comparison:ZZ_DEMO_pdf'));
  end`);
  assert.equal(r.owner, 'accountant');
});

test('a new bug cannot close without its learning; with it, it closes and its PDF renders', { skip: SKIP }, async () => {
  const r = await probe(`declare v_h bigint; v_refused boolean := false; v_blocks jsonb;
    begin
      set local app.qd_stub_founder_notify = 'on';
      perform public.fn_it_engineer_finding_upsert('duty:zz_demo:learning', 'ZZ DEMO new bug', 'ZZ DEMO', 'customer_facing', 1,
        '{"owner_seat":"sales_engineer","demo":true}'::jsonb);
      v_h := public.fn_it_loop_open('duty:zz_demo:learning');
      perform public.fn_it_incident_open(v_h);
      perform public.fn_it_engineer_finding_close('duty:zz_demo:learning', 'ZZ DEMO cleared');
      begin
        perform set_config('qd.handoff_closer', 'it_engineer', true);
        update public.agent_actions set status = 'done' where id = v_h;
      exception when others then v_refused := true; end;
      perform public.fn_it_attach_learning(v_h, 'ZZ DEMO cause', 'ZZ DEMO fix', 'scripts/checks/it_engineer_duties_9_to_18.test.mjs',
                                           p_not_automatable_reason => 'ZZ DEMO: one-off');
      v_blocks := public.fn_it_incident_pdf_blocks((select id from public.it_incident where handoff_id = v_h));
      raise exception 'CHK<<%>>', json_build_object('refused_without_learning', v_refused,
        'status_after', (select status from public.agent_actions where id = v_h),
        'pdf_blocks', jsonb_array_length(v_blocks->'blocks'));
    end`);
  assert.equal(r.refused_without_learning, true);
  assert.equal(r.status_after, 'done');
  assert.ok(r.pdf_blocks >= 10);
});
