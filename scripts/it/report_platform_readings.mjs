// Readings only a Supabase management token can take, handed to the IT engineer
// (public.fn_it_platform_ingest): database backups and PITR, the disk size the plan allows, and the
// organisation's members for the access review. Run by .github/workflows/it-weekly-readings.yml.
// Prints counts only: never a key, never a member's email.
//
//   node scripts/it/report_platform_readings.mjs
import { sql, lit, PROJECT_REF } from '../lib/db.mjs';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const token = process.env.SUPABASE_ACCESS_TOKEN?.trim()
  || (existsSync(join(homedir(), '.supabase', 'access-token')) ? readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim() : '');
if (!token) { console.error('no Supabase management token'); process.exit(2); }
const api = async (path) => {
  const r = await fetch(`https://api.supabase.com${path}`, { headers: { Authorization: `Bearer ${token}` } });
  return { ok: r.ok, status: r.status, json: r.ok ? await r.json().catch(() => null) : null };
};
const unavailable = (why) => ({ basis: 'unavailable', reason: why });

const b = await api(`/v1/projects/${PROJECT_REF}/database/backups`);
const backups = b.ok
  ? { basis: 'measured', pitr_enabled: !!b.json?.pitr_enabled,
      latest_backup_at: (b.json?.backups ?? []).map((x) => x.inserted_at).sort().pop() ?? null }
  : unavailable(`backups answered ${b.status}`);

const p = await api(`/v1/projects/${PROJECT_REF}`);
const d = await api(`/v1/projects/${PROJECT_REF}/config/disk`);
const disk = d.ok && d.json?.attributes?.size_gb
  ? { basis: 'measured', size_bytes: Math.round(Number(d.json.attributes.size_gb) * 1024 ** 3) }
  : unavailable(`disk config answered ${d.status}`);

let members = unavailable('project organisation unreadable');
if (p.ok && p.json?.organization_id) {
  const m = await api(`/v1/organizations/${p.json.organization_id}/members`);
  members = m.ok
    ? { basis: 'measured', principals: (m.json ?? []).map((x) => ({ principal: x.user_id, role: x.role_name })) }
    : unavailable(`members answered ${m.status}`);
}

const [r] = await sql(`select public.fn_it_platform_ingest(${lit(JSON.stringify({ backups, disk, members }))}::jsonb) r`);
console.log(`platform readings: backups ${backups.basis}, disk ${disk.basis}, members ${members.basis} ->`, JSON.stringify(r.r));
