#!/usr/bin/env python3
"""
Operational 86-category routing layer.

Loads the 86 route manifests, the 426-row crosswalk, the 3,831-entry bilingual alias lexicon and the
258 route tests, and writes the reviewable crosswalk into kb_stage.category_crosswalk.

THE ONE RULE THAT MATTERS HERE: the live catalogue wins.
public.catalog_supplier_categories already holds 86 rows whose slugs are production values other
tables, URLs and supplier records depend on. The manifests carry an EXPECTED slug that sometimes
disagrees (e.g. #83 expects 'utility-contractors' where production says
'utility-contractors-dewa-sewa-fewa-approved'). Every row here is keyed on catalog_num and the live
slug is read from the database, never inferred; the expected slug is stored only as evidence so the
disagreements are visible instead of silently resolved.
"""
import argparse, hashlib, json, os, re, sys, unicodedata
from datetime import datetime, timezone
import urllib.request, urllib.error

BASE = os.path.dirname(os.path.abspath(__file__))
ROUTING = os.path.join(BASE, 'all86', 'QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31',
                       '02_OPERATIONAL_86_ROUTING')
FN_URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_corpus_import'
TOKEN = open(os.path.join(BASE, '.tok')).read().strip()
LIVE = json.load(open(os.path.join(BASE, 'live_catalog.json')))   # [{num, slug, name}]
LIVE_BY_NUM = {int(c['num']): c for c in LIVE}


def call(action, **kw):
    kw['__token'] = TOKEN; kw['action'] = action
    req = urllib.request.Request(FN_URL, data=json.dumps(kw).encode('utf-8'),
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return {'error': f'http_{e.code}', 'body': e.read().decode('utf-8', 'replace')[:600]}
    except Exception as e:                                        # noqa: BLE001
        return {'error': str(e)}


# ---- normalisation ------------------------------------------------------------------------------
# The router matches on alias_norm, not on the alias as written. Without this, "DEWA NOC", "dewa noc"
# and "DEWA  N.O.C." are three different strings and two of them never match anything a customer
# actually types. Arabic needs more than casefolding: alef appears as ا/أ/إ/آ depending on who typed
# it, ta-marbuta and ha are interchangeable in informal writing, ya and alef-maqsura likewise, and
# harakat are optional. A customer typing "مقاولو المرافق" must hit an alias stored as
# "مقاولو المرافق" even if one of them carries a hamza the other does not.
AR_DIACRITICS = re.compile(r'[ً-ْٰـ]')
PUNCT = re.compile(r'[^\w؀-ۿ]+', re.UNICODE)


def norm(s: str) -> str:
    s = unicodedata.normalize('NFKC', str(s or '')).casefold()
    s = AR_DIACRITICS.sub('', s)
    s = (s.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
           .replace('ة', 'ه').replace('ى', 'ي').replace('ؤ', 'و').replace('ئ', 'ي'))
    s = PUNCT.sub(' ', s)
    return ' '.join(s.split())


def post(target, rows, dry, report):
    if not rows: return
    for i in range(0, len(rows), 1000):
        chunk = rows[i:i + 1000]
        if dry:
            report.setdefault('would_write', {}); report['would_write'][target] = report['would_write'].get(target, 0) + len(chunk)
            continue
        res = call('batch', target=target, rows=chunk)
        if not res.get('ok'):
            report.setdefault('errors', []).append({'target': target, 'error': res})
        else:
            report.setdefault('written', {}); report['written'][target] = report['written'].get(target, 0) + len(chunk)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    report = {'started_at': datetime.now(timezone.utc).isoformat(), 'dry_run': a.dry_run}

    # ---- 1. routes -----------------------------------------------------------------------------
    mdir = os.path.join(ROUTING, 'route_manifests')
    files = sorted(os.listdir(mdir))
    routes, mismatches, missing_live = [], [], []
    for f in files:
        m = json.load(open(os.path.join(mdir, f), encoding='utf-8'))
        num = int(m['catalog_num'])
        live = LIVE_BY_NUM.get(num)
        if not live:
            missing_live.append(num); continue
        if m.get('expected_catalog_slug') != live['slug']:
            mismatches.append({'num': num, 'expected': m.get('expected_catalog_slug'), 'live': live['slug']})
        routes.append({
            'catalog_num': num, 'route_key': m['route_key'],
            'expected_catalog_slug': m.get('expected_catalog_slug'),
            'catalog_name': live['name'],                 # live name, not the manifest's
            'route_type': m.get('route_type') or 'direct',
            'coverage_status': m.get('coverage_status') or 'unknown',
            'version': str(m.get('version') or '2026.07.31'),
            'manifest': m,
        })
    report['routes'] = {'manifests': len(files), 'routes_built': len(routes),
                        'live_catalogue_size': len(LIVE),
                        'slug_mismatches': len(mismatches), 'mismatch_detail': mismatches,
                        'catalog_nums_absent_from_live': missing_live}
    post('op_route', routes, a.dry_run, report)

    # ---- 2. crosswalk (route -> knowledge package/subcategory) ---------------------------------
    xw, stage_xw = [], []
    seen_map, seen_xw = set(), set()
    with open(os.path.join(ROUTING, '02_OPERATIONAL_CROSSWALK.jsonl'), encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            d = json.loads(line)
            num = int(d['catalog_num']); live = LIVE_BY_NUM.get(num)
            if not live: continue
            k = (num, d['package_slug'], d['subcategory_slug'])
            if k in seen_map: continue
            seen_map.add(k)
            xw.append({'catalog_num': num, 'package_slug': d['package_slug'],
                       'subcategory_slug': d['subcategory_slug'],
                       'priority': d.get('priority') or 'primary',
                       'package_zip': d.get('package_zip'),
                       'package_number': d.get('package_number')})
            # The reviewable crosswalk the control pack demands. relationship_type is derived from
            # the manifest's own priority; everything stays review_status='draft' because a
            # taxonomy bridge nobody has read is not a reviewed taxonomy bridge.
            k2 = (d['subcategory_slug'], str(num), d['package_slug'])
            if k2 in seen_xw: continue
            seen_xw.add(k2)
            stage_xw.append({
                'knowledge_domain_slug': d['package_slug'],
                'knowledge_subcategory_slug': d['subcategory_slug'],
                'production_category_id': str(num),
                'production_category_slug': live['slug'],
                'relationship_type': 'primary' if (d.get('priority') or 'primary') == 'primary' else 'secondary',
                'routing_priority': 10 if (d.get('priority') or 'primary') == 'primary' else 50,
                'review_status': 'draft',
            })
    report['crosswalk'] = {'route_map_rows': len(xw), 'stage_crosswalk_rows': len(stage_xw)}
    post('op_route_map', xw, a.dry_run, report)
    post('crosswalk', stage_xw, a.dry_run, report)

    # ---- 3. alias lexicon ------------------------------------------------------------------------
    aliases, seen_a = [], set()
    langs = {}
    with open(os.path.join(ROUTING, '03_OPERATIONAL_ALIAS_LEXICON.jsonl'), encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            d = json.loads(line)
            num = int(d['catalog_num'])
            if num not in LIVE_BY_NUM: continue
            alias = str(d['alias']); lang = str(d.get('language') or 'en')
            k = (num, lang, alias)
            if k in seen_a: continue
            seen_a.add(k)
            n = norm(alias)
            if not n: continue
            langs[lang] = langs.get(lang, 0) + 1
            aliases.append({'catalog_num': num, 'language': lang, 'alias': alias, 'alias_norm': n,
                            'weight': int(d.get('weight') or 2),
                            'negative': bool(d.get('negative')), 'source': d.get('source')})
    report['aliases'] = {'rows': len(aliases), 'by_language': langs,
                         'negative': sum(1 for x in aliases if x['negative'])}
    post('op_alias', aliases, a.dry_run, report)

    # ---- 4. route tests --------------------------------------------------------------------------
    tests = []
    with open(os.path.join(ROUTING, '04_OPERATIONAL_ROUTE_TESTS.jsonl'), encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line: continue
            d = json.loads(line)
            tests.append({'test_id': d['test_id'],
                          'catalog_num': d.get('expected_catalog_num'),
                          'input': d['input'],
                          'expected_action': d.get('expected_action') or 'route',
                          'expected': d})
    report['route_tests'] = {'rows': len(tests)}
    post('op_route_test', tests, a.dry_run, report)

    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    out = os.path.join(BASE, 'routes_report.json')
    json.dump(report, open(out, 'w'), indent=1, ensure_ascii=False)
    print(json.dumps({k: v for k, v in report.items() if k != 'routes'}, indent=1, ensure_ascii=False)[:2000])
    print('slug mismatches:', len(mismatches), '-> live slug always wins')
    print('->', out)


if __name__ == '__main__':
    main()
