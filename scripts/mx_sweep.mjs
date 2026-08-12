// MX sweep — ask DNS whether each lead e-mail domain can receive mail at all.
//
// This is most of what a paid list verifier does, at zero cost. Current bounce is 5/62 = 8.06%
// against an 0.08 brake that has already paused the sender once, and 8,927 domains had never been
// asked the question.
//
// RFC 5321 5.1: a domain with no MX but an A/AAAA record still receives mail (implicit MX). So a
// domain is deliverable if EITHER resolves; only one that resolves to neither is refused, and
// NXDOMAIN is recorded separately from a timeout because a timeout is a missing measurement, not a
// verdict. fn_email_sendable only blocks on kind in ('nxdomain','no_records') — an 'error' row
// stays sendable.
//
//   node scripts/mx_sweep.mjs --ref=<project-ref> [--limit=N] [--recheck-days=30]
//
// Safe to re-run: rows are upserted, and domains checked inside --recheck-days are skipped.
import { Resolver } from 'node:dns/promises';
import { readFileSync } from 'node:fs';

const arg = (k, d) => { const m = process.argv.find((a) => a.startsWith(`--${k}=`)); return m ? m.split('=')[1] : d; };
const REF = arg('ref');
const LIMIT = Number(arg('limit', '0')) || 0;
const RECHECK_DAYS = Number(arg('recheck-days', '30'));
const CONCURRENCY = Number(arg('concurrency', '60'));
if (!REF) { console.error('usage: node scripts/mx_sweep.mjs --ref=<project-ref>'); process.exit(2); }

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}
const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// Public resolvers, not the machine's: a corporate or ISP resolver that NXDOMAIN-hijacks would
// mark live domains dead, and this writes a gate that stops mail.
const resolver = new Resolver({ timeout: 5000, tries: 2 });
resolver.setServers(['1.1.1.1', '8.8.8.8', '9.9.9.9']);

async function check(domain) {
  try {
    const mx = await resolver.resolveMx(domain);
    if (mx && mx.length) {
      const hosts = mx.sort((a, b) => a.priority - b.priority).slice(0, 4).map((m) => m.exchange);
      return { has_mx: true, kind: 'mx', hosts };
    }
  } catch (e) {
    if (!['ENOTFOUND', 'ENODATA', 'NXDOMAIN'].includes(e.code)) {
      return { has_mx: true, kind: 'error', hosts: [String(e.code || e.message).slice(0, 40)] };
    }
    if (e.code === 'ENOTFOUND' || e.code === 'NXDOMAIN') {
      // The domain itself does not exist. Still confirm there is no A record before condemning it.
      try {
        const a = await resolver.resolve4(domain);
        if (a && a.length) return { has_mx: true, kind: 'a_implicit', hosts: a.slice(0, 2) };
      } catch { /* fall through */ }
      return { has_mx: false, kind: 'nxdomain', hosts: [] };
    }
  }
  // ENODATA on MX: domain exists, no MX. Implicit-MX rule applies if it has an address record.
  try {
    const a = await resolver.resolve4(domain);
    if (a && a.length) return { has_mx: true, kind: 'a_implicit', hosts: a.slice(0, 2) };
  } catch (e) {
    if (!['ENOTFOUND', 'ENODATA', 'NXDOMAIN'].includes(e.code)) {
      return { has_mx: true, kind: 'error', hosts: [String(e.code || e.message).slice(0, 40)] };
    }
  }
  return { has_mx: false, kind: 'no_records', hosts: [] };
}

const rows = await sql(`
  select distinct lower(split_part(l.email,'@',2)) as domain
  from leads l
  where l.email is not null and l.email <> ''
    and l.email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$'
    and not exists (
      select 1 from email_domain_mx m
      where m.domain = lower(split_part(l.email,'@',2))
        and m.checked_at > now() - interval '${RECHECK_DAYS} days')
  order by 1 ${LIMIT ? `limit ${LIMIT}` : ''}`);

const domains = rows.map((r) => r.domain).filter(Boolean);
console.log(`${domains.length} domain(s) to check, concurrency ${CONCURRENCY}`);

const results = [];
let done = 0;
async function worker(queue) {
  for (;;) {
    const d = queue.pop();
    if (!d) return;
    const res = await check(d);
    results.push({ domain: d, ...res });
    if (++done % 500 === 0) console.log(`  ${done}/${domains.length}`);
  }
}
const queue = domains.slice();
await Promise.all(Array.from({ length: CONCURRENCY }, () => worker(queue)));

// Write in batches; one statement per 500 rows keeps each request well inside the 8 s timeout.
for (let i = 0; i < results.length; i += 500) {
  const chunk = results.slice(i, i + 500);
  const values = chunk.map((r) =>
    `(${lit(r.domain)}, ${r.has_mx}, ${lit(r.kind)}, ` +
    `${r.hosts && r.hosts.length ? `array[${r.hosts.map(lit).join(',')}]::text[]` : 'null'}, now())`).join(',\n');
  await sql(`insert into email_domain_mx (domain, has_mx, kind, hosts, checked_at)
             values ${values}
             on conflict (domain) do update
               set has_mx = excluded.has_mx, kind = excluded.kind,
                   hosts = excluded.hosts, checked_at = excluded.checked_at;`);
  console.log(`  wrote ${Math.min(i + 500, results.length)}/${results.length}`);
}

const tally = results.reduce((a, r) => { a[r.kind] = (a[r.kind] || 0) + 1; return a; }, {});
console.log('\nby kind:', JSON.stringify(tally));
console.log('undeliverable domains:', results.filter((r) => !r.has_mx).length);
