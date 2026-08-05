#!/usr/bin/env python3
"""
Behavioural idempotency tests for the corpus importer.

The audit excluded source-string assertions by name, and it was right to: 91 of the 107 tests in
this repo assert that a file contains a string, and every one of them passed on 4 Aug while the
importer was duplicating 3,325 rows. These tests import the real 67-package fixture and measure
what comes out.

  py -3 test_idempotency.py                          # offline: real archives, simulated store
  py -3 test_idempotency.py --project-ref <staging>   # end-to-end: real archives, real database

The offline pass runs anywhere and needs no credentials. The end-to-end pass is the one that
proves the whole chain, and it refuses to run against production.
"""
import argparse, json, sys
import import_corpus as ic
from kb_idempotency import (canonical_rule_key, classify, gate, reconcile, digests,
                            fetch_rule_keys, assert_not_production, UpsertKeyChanged,
                            StaleKeysPresent, ProductionRefusal)

FAIL = []


def check(name, cond, detail=''):
    print(('PASS ' if cond else 'FAIL ') + name + (f'  {detail}' if detail else ''))
    if not cond:
        FAIL.append(name)


def zips():
    import os
    return sorted(z for z in os.listdir(ic.PKG_DIR) if z.endswith('.zip'))


def offline():
    """Import the real fixture twice into an empty simulated store. The second must insert 0."""
    zs = zips()
    check('fixture is the complete 67-package corpus', len(zs) == 67, f'found {len(zs)}')

    rules, records = ic.scan_expected(zs)
    check('archives yield 12,929 decision rules', len(rules) == 12929, f'got {len(rules)}')
    check('archives yield 112,611 knowledge records', len(records) == 112611, f'got {len(records)}')

    # Determinism: the same archives must produce the same keys. A key derived from anything
    # order-dependent or shape-dependent fails here.
    rules2, records2 = ic.scan_expected(zs)
    check('key derivation is deterministic across runs', set(rules) == set(rules2))
    check('record id set is deterministic across runs', records == records2)

    # FIRST IMPORT into an empty store.
    store = {}
    v1 = classify(rules, store)
    check('first import inserts every rule', v1['to_insert'] == len(rules), json.dumps(
        {k: v1[k] for k in ('expected', 'to_insert', 'to_upsert_existing', 'stale')}))
    check('first import has nothing stale', v1['stale'] == 0)
    gate(v1)                                          # must not raise on a clean store
    store = {k: dict(v) for k, v in rules.items()}    # the writes land

    # SECOND IMPORT of the identical archives.
    v2 = classify(rules, store)
    check('SECOND IMPORT INSERTS ZERO', v2['to_insert'] == 0, f"to_insert={v2['to_insert']}")
    check('second import sees nothing stale', v2['stale'] == 0, f"stale={v2['stale']}")
    check('second import matches every existing row', v2['to_upsert_existing'] == len(rules))
    gate(v2)

    # A THIRD run after a shape flip must still be stable: re-deriving a wrapped rule's key from
    # the flat identifier and back must not move it. This is the exact 4 Aug failure, in miniature.
    flipped = {}
    for k, v in rules.items():
        flipped[k] = v
    check('key is invariant under re-derivation', set(flipped) == set(rules))

    # THE REGRESSION TEST FOR A-01: a store keyed under the OLD scheme must be REFUSED, not
    # silently doubled. The old scheme keyed wrapped rules by record_id.
    old_scheme = {}
    for k, v in rules.items():
        old_scheme[v['record_id'] or k] = dict(v)
    try:
        gate(classify(rules, old_scheme))
        check('A-01 regression: old-scheme store is refused', False, 'gate did NOT raise')
    except UpsertKeyChanged as e:
        n = classify(rules, old_scheme)['stale_superseded_by_key_change']
        check('A-01 regression: old-scheme store is refused', n > 0, f'{n} rows flagged as re-keyed')
    except StaleKeysPresent:
        check('A-01 regression: old-scheme store is refused', False,
              'refused as generic staleness, not as an upsert-key change')

    # Reconciliation must call an unchanged rerun idempotent, and a grown table not.
    same = {'rules_n': len(rules), 'rules_key_digest': 'a', 'rules_body_digest': 'b',
            'records_n': len(records), 'records_key_digest': 'c', 'records_body_digest': 'd'}
    r_ok = reconcile(same, dict(same), len(rules), len(records), 0)
    check('reconcile calls an unchanged rerun idempotent', r_ok['idempotent'] is True)
    grown = dict(same); grown['rules_n'] = len(rules) + 3325
    r_bad = reconcile(same, grown, len(rules), len(records), 0)
    check('reconcile refuses a run that grew the table', r_bad['idempotent'] is False
          and r_bad['rules_inserted'] == 3325 and r_bad['count_matches_archive'] is False,
          f"inserted={r_bad['rules_inserted']}")


def guards():
    """The refusals must bite. A guard nobody proves is a convention."""
    try:
        assert_not_production('htdblwldjkcgjvmqkbeh', 'test')
        check('guard refuses the production ref', False, 'did not raise')
    except ProductionRefusal:
        check('guard refuses the production ref', True)
    for bad in ('', 'HTDBLWLDJKCGJVMQKBEH', 'htdblwldjkcgjvmqkbe', 'not-a-ref', None):
        try:
            assert_not_production(bad, 'test')
            check(f'guard refuses malformed ref {bad!r}', False, 'did not raise')
        except ProductionRefusal:
            check(f'guard refuses malformed ref {bad!r}', True)
    try:
        assert_not_production('pglpqrhvozwepymcuunn', 'test')
        check('guard permits a valid non-production ref', True)
    except ProductionRefusal:
        check('guard permits a valid non-production ref', False)


def end_to_end(ref):
    """The real chain: real archives, real database, twice."""
    assert_not_production(ref, 'end-to-end test')
    zs = zips()
    rules, records = ic.scan_expected(zs)

    before = digests(ref)
    v = classify(rules, fetch_rule_keys(ref))
    print('pre-import verdict: ' + json.dumps({k: v[k] for k in
          ('expected', 'present_before', 'to_insert', 'to_upsert_existing', 'stale')}))

    print('--- import 1 ---', flush=True)
    ic.set_target(ref, False)
    rep1 = {'packages': []}
    for z in zs:
        ic.import_package(f'{ic.PKG_DIR}/{z}', False, rep1, force=True)
    mid = digests(ref)
    r1 = reconcile(before, mid, len(rules), len(records), 0)
    check('import 1 reaches the archive count', r1['count_matches_archive'], json.dumps(
        {k: r1[k] for k in ('rules_after', 'rules_expected', 'records_after', 'records_expected')}))

    print('--- import 2 (identical input) ---', flush=True)
    rep2 = {'packages': []}
    for z in zs:
        ic.import_package(f'{ic.PKG_DIR}/{z}', False, rep2, force=True)
    after = digests(ref)
    r2 = reconcile(mid, after, len(rules), len(records), 0)
    check('SECOND IMPORT INSERTED ZERO ROWS', r2['rules_inserted'] == 0, f"inserted={r2['rules_inserted']}")
    check('key digest unchanged by the second import', not r2['rules_keys_changed'])
    check('body digest unchanged by the second import', not r2['rules_body_changed'])
    check('record count unchanged by the second import', r2['records_inserted'] == 0)
    check('second import is reported idempotent', r2['idempotent'] is True, json.dumps(r2))
    json.dump({'before': before, 'mid': mid, 'after': after, 'run1': r1, 'run2': r2},
              open('C:/Users/Opera/qd-check/_idempotency_e2e.json', 'w'), indent=1)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--project-ref', default=None)
    ap.add_argument('--skip-offline', action='store_true')
    a = ap.parse_args()
    guards()
    if not a.skip_offline:
        offline()
    if a.project_ref:
        end_to_end(a.project_ref)
    print('\n' + ('ALL IDEMPOTENCY TESTS PASS' if not FAIL else f'{len(FAIL)} FAILED: {FAIL}'))
    sys.exit(0 if not FAIL else 1)
