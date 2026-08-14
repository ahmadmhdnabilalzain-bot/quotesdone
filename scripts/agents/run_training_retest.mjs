// Drive an open remediation through a real retest.
//
// fn_remediation_step only closes a remediation as `passed` on a score that an actual retest
// produced: the score is read out of agent_train's response, never supplied by this script. A
// remediation that does not reach 0.8 stays open, and that is the correct outcome, not a failure
// of the runner.
//
//   node scripts/agents/run_training_retest.mjs --ref=<project-ref> [--agents=spec_fitout,spec_mep] [--n=5]
import { readFileSync, existsSync } from 'node:fs';

const arg = (k, d) => (process.argv.find((a) => a.startsWith(`--${k}=`)) || `--${k}=${d}`).slice(k.length + 3);
const REF = arg('ref', '');
const AGENTS = arg('agents', 'spec_fitout,spec_mep').split(',').filter(Boolean);
const N = Number(arg('n', '5'));
if (!REF) { console.error('usage: --ref=<project-ref>'); process.exit(2); }

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.error('no SUPABASE_ACCESS_TOKEN'); process.exit(2); }

async function q(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${r.status} ${t}`);
  return JSON.parse(t);
}

// The scoped credential, not the shared one: internal_credential id 100 ('action.invoker') is the
// only active credential whose scope contains agent_train, and it is what actually drove the
// training runs on 14 Aug. Presenting inbound_secret here returns 401, correctly.
const secret = (await q(`select value from app_secrets where key='cred_action_invoker'`))[0].value;

for (const agent of AGENTS) {
  const open = await q(`select id, baseline_score, attempts, max_attempts, status
                          from agent_remediation
                         where agent_key='${agent}' and status in ('open','retesting')
                         order by opened_at desc limit 1`);
  if (!open.length) { console.log(`${agent}: no open remediation`); continue; }
  const rem = open[0];

  const res = await fetch(`https://${REF}.supabase.co/functions/v1/agent_train`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, agent_key: agent, purpose: 'retest',
                           n: N, remediation_id: Number(rem.id) }),
  });
  const body = await res.text();
  let out; try { out = JSON.parse(body); } catch { out = { raw: body }; }
  console.log(`${agent}: remediation ${rem.id} (baseline ${rem.baseline_score ?? 'unset'}) -> HTTP ${res.status}`);
  console.log('  ' + JSON.stringify(out).slice(0, 900));

  const after = await q(`select status, attempts, baseline_score, latest_score, blocks_autonomy,
                                round(cost_aed,3) cost_aed
                           from agent_remediation where id=${Number(rem.id)}`);
  console.log('  after: ' + JSON.stringify(after[0]));
}
