#!/usr/bin/env python3
"""
Batch 0 step 4 — make the corpus import idempotent, and make its report able to say so.

WHAT WENT WRONG (finding A-01, 4 Aug 2026)
The importer upserts decision rules on `rule_id`. 28 of the 67 packages emit a rule that carries
BOTH a flat `rule_id` and a record envelope. A fix to the shape detector changed which of the two
values was written into the key column - from the flat `R-002-dewa-...` to the envelope's
`rule-structural-steel-...`. Different key, so every one of those upserts INSERTED instead of
updating, and 3,325 original rows survived carrying an empty rule body. The run reported
"rows=52,697 rejected=0 write_errors=0" and was, by its own measure, a success.

Two separate defects, and both are fixed here:

  1. THE KEY WAS NOT INVARIANT UNDER SHAPE. canonical_rule_key() below returns the same key for
     the same source rule whichever branch of the detector claims it.

  2. THE REPORT COULD NOT HAVE NOTICED. "rows" counted lines read from a file. Nothing measured
     what the database did. preflight() and reconcile() below measure the database, before and
     after, and report expected / inserted / updated / unchanged / stale / rejected separately.

The guard that matters most is the pre-flight one: a change of upsert key is detected BEFORE the
first write, not after. Detecting it afterwards is just a nicer way to describe the same 3,325 rows.
"""
import hashlib, json, os, re, urllib.request, urllib.error

PROD_REF = 'htdblwldjkcgjvmqkbeh'
TOKEN_PATH = os.path.expanduser('~/.supabase/access-token')


class ProductionRefusal(RuntimeError):
    pass


def assert_not_production(ref, what='write'):
    """Mirror of qd_guard.mjs. Exact match, fail closed: a typo must not fall through."""
    if not isinstance(ref, str) or not re.fullmatch(r'[a-z]{20}', ref):
        raise ProductionRefusal(f'target ref {ref!r} is not a valid project ref')
    if ref == PROD_REF:
        raise ProductionRefusal(f'{what} targeted production ({PROD_REF}). Batch 0 forbids this.')
    return ref


def canonical_rule_key(r, shape):
    """One key per decision rule, invariant under the shape the package happens to use.

    The source rule id is the only identifier present in BOTH shapes, so it is the key:
      flat     -> r['rule_id']
      wrapped  -> structured_data['rule_id']
    Measured on production 4 Aug 2026: 468 of 10,392 wrapped rules carry no source rule id.
    Those fall back to record_id, which is stable precisely because such a rule has no other
    identity to drift to. Collisions of coalesce(source_rule_id, record_id) across the 12,929
    genuine rules: zero, globally and per category.
    """
    if shape == 'flat':
        return r['rule_id']
    sd = r.get('structured_data') or {}
    return sd.get('rule_id') or r['record_id']


def _post(ref, sql):
    token = (os.environ.get('SUPABASE_ACCESS_TOKEN') or open(TOKEN_PATH).read()).strip()
    req = urllib.request.Request(
        f'https://api.supabase.com/v1/projects/{ref}/database/query',
        data=json.dumps({'query': sql}).encode('utf-8'),
        # Without an explicit User-Agent, urllib sends "Python-urllib/3.x" and Cloudflare answers
        # 403 "error code: 1010" in front of the management API. The node tooling never hit this
        # because fetch() sets one. Cost: one confusing 403 that looks like an auth failure.
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json',
                 'User-Agent': 'quotesdone-kb-idempotency/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode('utf-8') or 'null')
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'management API {e.code}: {e.read().decode("utf-8", "replace")[:400]}')


READ_ONLY = re.compile(r'\b(insert|update|delete|truncate|drop|alter|create|grant|revoke)\b', re.I)


def db_read(ref, sql):
    """Reads are allowed against any project including production - A-01 was diagnosed that way."""
    if READ_ONLY.search(re.sub(r'--[^\n]*', '', sql)):
        raise ProductionRefusal('db_read was handed a statement that writes')
    return _post(ref, sql)


def db_write(ref, sql):
    assert_not_production(ref, 'db_write')
    return _post(ref, sql)


RULE_KEYS_SQL = """
select rule_id, coalesce(source_rule_id,'') as source_rule_id, coalesce(record_id,'') as record_id
  from kb_stage.decision_rules order by rule_id
"""

DIGEST_SQL = """
select
 (select count(*) from kb_stage.decision_rules) as rules_n,
 (select md5(coalesce(string_agg(rule_id,'|' order by rule_id),'')) from kb_stage.decision_rules) as rules_key_digest,
 (select md5(coalesce(string_agg(rule_id||':'||md5(coalesce(when_json::text,'')||coalesce(then_json::text,'')),'|' order by rule_id),''))
    from kb_stage.decision_rules) as rules_body_digest,
 (select count(*) from kb_stage.records) as records_n,
 (select md5(coalesce(string_agg(record_id,'|' order by record_id),'')) from kb_stage.records) as records_key_digest,
 (select md5(coalesce(string_agg(record_id||':'||coalesce(content_sha256,''),'|' order by record_id),''))
    from kb_stage.records) as records_body_digest
"""


def digests(ref):
    return db_read(ref, DIGEST_SQL)[0]


def fetch_rule_keys(ref):
    return {row['rule_id']: row for row in db_read(ref, RULE_KEYS_SQL)}


def classify(expected, present):
    """expected: {key: {'source_rule_id':..,'record_id':..}} from the archives
       present:  {key: row} from the database
    Returns the five numbers a report has to carry, plus the A-01 signature."""
    exp_keys, db_keys = set(expected), set(present)
    missing = exp_keys - db_keys          # will be INSERTed
    matched = exp_keys & db_keys          # will be UPDATEd or left UNCHANGED
    stale = db_keys - exp_keys            # in the database, in no archive

    # THE A-01 SIGNATURE, detected before a single row is written.
    # A stale key that appears as the source_rule_id of an expected rule is not junk data: it is
    # the SAME rule under the PREVIOUS key scheme. That is an upsert-key change, and continuing
    # would insert a second copy of every one of them - which is exactly what happened on 4 Aug.
    # A previous key scheme could have used EITHER identifier the rule carries. Indexing only
    # source_rule_id found nothing when the database was keyed on record_id - which is precisely
    # the scheme A-01 left behind, so the detector missed the case it was written for and the run
    # was refused as ordinary staleness instead. Index both.
    alias_index = {}
    for k, v in expected.items():
        for alias in (v.get('source_rule_id'), v.get('record_id')):
            if alias and alias != k:
                alias_index.setdefault(alias, []).append(k)
    superseded = {s: alias_index[s] for s in stale if s in alias_index}

    return {
        'expected': len(exp_keys),
        'present_before': len(db_keys),
        'to_insert': len(missing),
        'to_upsert_existing': len(matched),
        'stale': len(stale),
        'stale_superseded_by_key_change': len(superseded),
        'stale_sample': sorted(stale)[:20],
        'superseded_sample': [{'old_key': k, 'now_keyed_as': v} for k, v in list(superseded.items())[:20]],
    }


class UpsertKeyChanged(RuntimeError):
    pass


class StaleKeysPresent(RuntimeError):
    pass


def gate(verdict, allow_stale=False):
    """Fail closed, BEFORE the first write.

    An upsert-key change is never permitted silently: it is not a data problem the run can
    absorb, it is a schema decision that needs a migration and an approval. Ordinary stale keys
    (rules withdrawn from a package) are also refused by default, because on 4 Aug 'a few extra
    rows' was the whole finding; --allow-stale makes accepting them a deliberate act.
    """
    if verdict['stale_superseded_by_key_change'] > 0:
        raise UpsertKeyChanged(
            f"UPSERT KEY CHANGED: {verdict['stale_superseded_by_key_change']} rows in the database "
            f"are keyed under a scheme this archive no longer produces. Importing now would insert "
            f"a duplicate of each instead of updating it - finding A-01, exactly. "
            f"Sample: {json.dumps(verdict['superseded_sample'][:3])}")
    if verdict['stale'] > 0 and not allow_stale:
        raise StaleKeysPresent(
            f"{verdict['stale']} keys exist in the database and in no archive. "
            f"Sample: {verdict['stale_sample'][:5]}. Re-run with --allow-stale to accept them.")
    return True


def reconcile(before, after, expected_rules, expected_records, rejected):
    """The five numbers, measured from the database rather than asserted by the writer."""
    inserted = after['rules_n'] - before['rules_n']
    r = {
        'rules_expected': expected_rules,
        'rules_before': before['rules_n'],
        'rules_after': after['rules_n'],
        'rules_inserted': inserted,
        'rules_body_changed': before['rules_body_digest'] != after['rules_body_digest'],
        'rules_keys_changed': before['rules_key_digest'] != after['rules_key_digest'],
        'records_expected': expected_records,
        'records_before': before['records_n'],
        'records_after': after['records_n'],
        'records_inserted': after['records_n'] - before['records_n'],
        'rejected': rejected,
        'count_matches_archive': after['rules_n'] == expected_rules and after['records_n'] == expected_records,
    }
    r['idempotent'] = (before['rules_n'] > 0 and inserted == 0
                       and not r['rules_keys_changed'] and r['count_matches_archive'])
    return r
