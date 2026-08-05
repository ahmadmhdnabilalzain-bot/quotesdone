#!/usr/bin/env python3
"""
QuotesDone knowledge-corpus importer.

Streams the 67 category packages of QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31 into the
kb_stage schema through the kb_corpus_import edge function.

Design notes that matter:

* THE CORPUS NEVER ENTERS A MODEL CONTEXT. This script opens one ZIP at a time, reads one JSONL line
  at a time, and posts batches. Nothing is summarised, printed in bulk, or pasted anywhere.
* NO PLATFORM CREDENTIAL LIVES HERE. Authentication is a single-purpose token read from a local file;
  the service-role key stays inside the Supabase runtime.
* IDEMPOTENT AT TWO LEVELS. File level: a SHA-256 ledger skips files whose bytes have not changed.
  Row level: every write is an upsert on a stable ID. Re-running is therefore both the "no duplicates"
  guarantee and the "resume after interruption" mechanism - there is only one code path, so there is
  only one thing that can be wrong.
* VALIDATION IS FAIL-CLOSED PER ROW, NOT PER FILE. A malformed record is rejected and reported with
  its exact ID; the other 4,742 records in that file still land. Losing a whole trade's knowledge
  because one row has a bad date would be a worse outcome than a visible gap register.
* 23_all_records.jsonl IS SKIPPED DELIBERATELY. It is a byte-for-byte concatenation of the module
  files (verified: identical record_id sets, 4,743 = 4,743). Importing both would double the work
  and make every count in the report meaningless.
* 02_category_master.md IS NOT IMPORTED. 119 MB of narrative across the packages, and the control
  pack forbids putting a master into a runtime prompt. Its checksum is recorded; the text stays in
  the archive where it belongs.
"""
import argparse, hashlib, io, json, os, re, sys, time, zipfile, csv
from datetime import datetime, timezone
import urllib.request, urllib.error
from kb_idempotency import (canonical_rule_key, digests, fetch_rule_keys, classify, gate,
                            reconcile, UpsertKeyChanged, StaleKeysPresent)

BASE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(BASE, 'all86', 'QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31')
PKG_DIR = os.path.join(CORPUS, '01_CATEGORY_KNOWLEDGE_PACKAGES')
# The endpoint used to be a production literal, so this importer could only ever write to
# production - which is also why the 4 Aug re-import could not have been rehearsed anywhere first.
# It is now resolved from --project-ref / KB_PROJECT_REF, and production requires an explicit flag.
PROD_REF = 'htdblwldjkcgjvmqkbeh'
PROJECT_REF = (os.environ.get('KB_PROJECT_REF') or PROD_REF).strip()
FN_URL = f'https://{PROJECT_REF}.supabase.co/functions/v1/kb_corpus_import'
# The import token is minted per run and revoked after, so .tok is absent between imports. Reading
# it at module import time made every invocation - including --help and every guard test - die with
# a FileNotFoundError instead of doing its job. It is read on first use.
_TOKEN = None


def token():
    global _TOKEN
    if _TOKEN is None:
        p = os.path.join(BASE, '.tok')
        if not os.path.exists(p):
            sys.exit(f'no import token at {p}. Mint one into app_secrets(kb_import_token) and write it here; '
                     f'revoke it when the run finishes.')
        _TOKEN = open(p).read().strip()
    return _TOKEN


def set_target(ref, allow_production):
    global PROJECT_REF, FN_URL
    if not re.fullmatch(r'[a-z]{20}', ref or ''):
        sys.exit(f'refusing: {ref!r} is not a valid project ref')
    if ref == PROD_REF and not allow_production:
        sys.exit('refusing: target is production. Pass --i-mean-production to override.')
    PROJECT_REF = ref
    FN_URL = f'https://{ref}.supabase.co/functions/v1/kb_corpus_import'
    return ref
BATCH = 1000   # kb_corpus_import's MAX_ROWS; halves the number of round trips

MODULE_FILES = [
    '04_glossary_en_ar.jsonl', '05_products_services.jsonl', '06_technical_knowledge.jsonl',
    '07_brands_manufacturers.jsonl', '08_supplier_ecosystem.jsonl', '09_quotation_knowledge.jsonl',
    '10_document_requirements.jsonl', '11_uae_regulations_authorities.jsonl',
    '12_inquiry_questions.jsonl', '14_validation_rules.jsonl', '15_pricing_cost_drivers.jsonl',
    '16_risks_common_mistakes.jsonl', '17_troubleshooting.jsonl', '18_scenarios_tests.jsonl',
]
RULES_FILE = '13_decision_rules.jsonl'

VALID_STATUS = {'draft', 'source_verified', 'reviewed', 'approved', 'quarantined', 'superseded'}
SLUG_RE = re.compile(r'^[a-z0-9-]+$')


# ---------------------------------------------------------------------------- transport
def call(action, **kw):
    payload = dict(kw); payload['__token'] = token(); payload['action'] = action
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(FN_URL, data=data, headers={'Content-Type': 'application/json'})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            body = e.read().decode('utf-8', 'replace')[:600]
            # Retry only what is worth retrying. A 500 carrying a JSON error body is the FUNCTION
            # telling us the write is wrong (the first run hit "Invalid schema: kb_stage" and then
            # spent 5 x 180s per request pretending it might work next time - 67 packages of that is
            # a silent all-day hang). Retry transport-shaped failures; surface logic failures at once.
            transient = e.code in (408, 429, 502, 503, 504) or (e.code == 500 and '"error"' not in body)
            if transient and attempt < 4:
                time.sleep(2 * (attempt + 1)); continue
            return {'error': f'http_{e.code}', 'body': body}
        except Exception as e:                                    # noqa: BLE001
            if attempt < 4:
                time.sleep(2 * (attempt + 1)); continue
            return {'error': str(e)}
    return {'error': 'unreachable'}


class Writer:
    """Buffers rows per target and flushes in batches. Dry-run counts without posting."""
    def __init__(self, dry):
        self.dry = dry; self.buf = {}; self.written = {}; self.errors = []

    def add(self, target, row):
        self.buf.setdefault(target, []).append(row)
        if len(self.buf[target]) >= BATCH:
            self.flush(target)

    def flush(self, target=None):
        for t in ([target] if target else list(self.buf)):
            rows = self.buf.get(t) or []
            if not rows:
                continue
            if not self.dry:
                res = call('batch', target=t, rows=rows)
                if not res.get('ok'):
                    self.errors.append({'target': t, 'rows': len(rows),
                                        'error': res.get('error'), 'details': res.get('details'),
                                        'sample_ids': res.get('sample_ids')})
            self.written[t] = self.written.get(t, 0) + len(rows)
            self.buf[t] = []


# ---------------------------------------------------------------------------- validation
def validate(rec, kind):
    """Returns a list of problems. Mirrors 04_KNOWLEDGE_RECORD_SCHEMA.json without a jsonschema dep."""
    p = []
    if kind == 'rule':
        if not (rec.get('rule_id') or rec.get('record_id')):
            p.append('missing rule_id and record_id')
        for f in ('category_slug', 'subcategory_slug'):
            if not rec.get(f): p.append(f'missing {f}')
        return p
    for f in ('record_id', 'category_slug', 'subcategory_slug', 'module', 'record_type',
              'title', 'content', 'version', 'validation_status'):
        if not rec.get(f): p.append(f'missing {f}')
    if rec.get('category_slug') and not SLUG_RE.match(rec['category_slug']): p.append('bad category_slug')
    if rec.get('subcategory_slug') and not SLUG_RE.match(rec['subcategory_slug']): p.append('bad subcategory_slug')
    if rec.get('title') and len(rec['title']) < 3: p.append('title too short')
    if rec.get('content') and len(rec['content']) < 20: p.append('content too short')
    vs = rec.get('validation_status')
    if vs and vs not in VALID_STATUS: p.append(f'bad validation_status={vs}')
    c = rec.get('confidence')
    if c is not None and (not isinstance(c, (int, float)) or not 0 <= c <= 1): p.append('confidence out of range')
    if not isinstance(rec.get('source_ids', []), list): p.append('source_ids not a list')
    return p


def as_list(v):
    if v is None: return []
    if isinstance(v, list): return v
    return [v]


def sha_text(*parts):
    h = hashlib.sha256()
    for p in parts:
        h.update((p if isinstance(p, str) else json.dumps(p, sort_keys=True, ensure_ascii=False)).encode('utf-8'))
    return h.hexdigest()


# ---------------------------------------------------------------------------- row builders
def record_row(rec, package_id, run_id):
    return {
        'record_id': rec['record_id'], 'category_slug': rec['category_slug'],
        'subcategory_slug': rec['subcategory_slug'], 'module': rec['module'],
        'record_type': rec['record_type'], 'title': rec['title'][:2000], 'content': rec['content'],
        'structured_data': rec.get('structured_data') if isinstance(rec.get('structured_data'), (dict, list)) else {},
        'jurisdiction': rec.get('jurisdiction'), 'authority': rec.get('authority'),
        'source_ids': as_list(rec.get('source_ids')),
        'effective_date': rec.get('effective_date'), 'superseded_date': rec.get('superseded_date'),
        'version': str(rec.get('version')), 'confidence': rec.get('confidence'),
        'validation_status': rec['validation_status'], 'review_after': rec.get('review_after'),
        'keywords_en': as_list(rec.get('keywords_en')), 'keywords_ar': as_list(rec.get('keywords_ar')),
        'applies_when': rec.get('applies_when'), 'exceptions': as_list(rec.get('exceptions')),
        'escalation_rule': rec.get('escalation_rule'),
        'package_id': package_id, 'ingestion_run_id': run_id,
        'content_sha256': sha_text(rec['content'], rec.get('structured_data') or {}),
    }


def question_row(rec, run_id):
    sd = rec.get('structured_data') or {}
    if not isinstance(sd, dict): sd = {}
    return {
        'question_id': rec['record_id'], 'record_id': rec['record_id'],
        'source_question_id': sd.get('question_id') or sd.get('field') or None,
        'category_slug': rec['category_slug'], 'subcategory_slug': rec['subcategory_slug'],
        'field_key': sd.get('field_key') or sd.get('field') or None,
        'question_en': sd.get('question_en'), 'question_ar': sd.get('question_ar'),
        'answer_type': sd.get('expected_answer_type') or sd.get('answer_type'),
        'allowed_values': as_list(sd.get('allowed_values')),
        'unit': sd.get('unit'),
        'mandatory': bool(sd.get('mandatory')),
        'activation': {k: sd.get(k) for k in
                       ('conditions', 'depends_on', 'regulatory_trigger', 'escalation_condition',
                        'order', 'is_common_question', 'supplier_facing_field',
                        'confidence_contribution', 'validation_rules') if k in sd},
        'impact': as_list(sd.get('impact')),
        'on_missing': sd.get('missing_answer_behavior'),
        'answerable_by_documents': as_list(sd.get('documents_that_may_answer')),
        'payload': sd, 'ingestion_run_id': run_id,
    }


def validation_row(rec, run_id):
    sd = rec.get('structured_data') or {}
    if not isinstance(sd, dict): sd = {}
    return {
        'validation_id': rec['record_id'], 'record_id': rec['record_id'],
        'source_validation_id': sd.get('validation_id') or sd.get('code') or None,
        'category_slug': rec['category_slug'], 'subcategory_slug': rec['subcategory_slug'],
        'rule_text': sd.get('rule_text') or sd.get('description') or sd.get('expression'),
        'severity': sd.get('severity'), 'on_fail': as_list(sd.get('on_fail') or sd.get('on_conflict')),
        'payload': sd, 'ingestion_run_id': run_id,
    }


def scenario_row(rec, run_id):
    sd = rec.get('structured_data') or {}
    if not isinstance(sd, dict): sd = {}
    return {
        'scenario_id': rec['record_id'], 'record_id': rec['record_id'],
        'source_scenario_id': sd.get('scenario_id') or sd.get('test_id') or None,
        'category_slug': rec['category_slug'], 'subcategory_slug': rec['subcategory_slug'],
        'setup': sd.get('setup') or sd.get('input'),
        'expected': sd.get('expected') or sd.get('expected_status'),
        'pass_criteria': as_list(sd.get('pass_criteria') or sd.get('assertions')),
        'status': sd.get('status') or 'not_executed', 'payload': sd, 'ingestion_run_id': run_id,
    }


# 13_decision_rules.jsonl comes in TWO shapes and neither is wrong. 28 packages emit a flat rule
# ({rule_id, when, then, priority, ...}); the other 39 wrap the same rule inside the standard record
# envelope, with the rule body in structured_data and the record carrying its own title, content,
# keywords and validation_status. A first pass at this importer only understood the flat shape and
# rejected 6,599 rules - 5.7% of the corpus, and disproportionately the ask-this-question-next rules
# that are the entire point of having a deterministic layer. Both shapes are handled here, and the
# wrapped ones are ALSO written to kb_stage.records so their narrative text stays searchable and
# versioned like every other record.
def rule_shape(r):
    # ORDER IS THE WHOLE FIX. 4 Aug 2026.
    #
    # The comment above says both shapes are handled. They were not. 28 of the 67 packages emit a
    # rule that carries BOTH a flat `rule_id` AND a full record envelope - record_id, title,
    # content, structured_data{when,then}, keywords, validation_status. Testing `rule_id` first
    # classified every one of them as 'flat', and rule_row(shape='flat') writes
    # `record_id: None, payload: {}` - so the rule landed in kb_stage.decision_rules stripped of
    # its narrative, and the record was NEVER written to kb_stage.records at all.
    #
    # Measured on production 4 Aug 2026: 3,793 decision_rule records absent from kb_stage.records
    # across 28 categories - including construction, MEP, utilities, gas, wastewater, firefighting
    # and ELV, the seven core construction trades. 61 of the other 62 record types matched the
    # source packages exactly, which is what made this invisible: the corpus looked complete.
    #
    # The envelope is the stronger signal, so it is tested first. A record that has a record_id and
    # a rule body in structured_data IS wrapped, whatever else it also carries.
    sd = r.get('structured_data')
    if r.get('record_id') and isinstance(sd, dict) and (sd.get('rule_id') or sd.get('when') or sd.get('then')):
        return 'wrapped'
    if r.get('rule_id'): return 'flat'
    return None


def rule_row(r, run_id, shape):
    # THE KEY IS canonical_rule_key(), NOT the shape's own identifier. 4 Aug 2026, finding A-01:
    # writing r['rule_id'] for flat and r['record_id'] for wrapped means the SAME rule changes key
    # when the shape detector's verdict changes, and an upsert on a changed key is an insert.
    # The source rule id exists in both shapes, so it is the key; the envelope's own id is kept
    # in record_id for provenance, where it cannot affect matching.
    key = canonical_rule_key(r, shape)
    if shape == 'flat':
        return {
            'rule_id': key, 'source_rule_id': r['rule_id'], 'record_id': None,
            'category_slug': r['category_slug'], 'subcategory_slug': r['subcategory_slug'],
            'rule_type': r.get('rule_type'), 'priority': r.get('priority'),
            'when_json': r.get('when'), 'then_json': r.get('then'),
            'source_ids': as_list(r.get('source_ids')), 'confidence': r.get('confidence'),
            'requires_human_review': bool(r.get('requires_human_review')),
            'version': str(r.get('version') or ''), 'payload': {}, 'ingestion_run_id': run_id,
        }
    sd = r.get('structured_data') or {}
    return {
        'rule_id': key, 'source_rule_id': sd.get('rule_id'), 'record_id': r['record_id'],
        'category_slug': r['category_slug'], 'subcategory_slug': r['subcategory_slug'],
        'rule_type': sd.get('rule_type') or r.get('record_type'),
        'priority': sd.get('priority'),
        'when_json': sd.get('when') or r.get('applies_when'), 'then_json': sd.get('then'),
        'source_ids': as_list(r.get('source_ids')), 'confidence': r.get('confidence'),
        'requires_human_review': bool(sd.get('requires_human_review')),
        'version': str(r.get('version') or ''), 'payload': sd, 'ingestion_run_id': run_id,
    }


# ---------------------------------------------------------------------------- per package
def import_package(zpath, dry, report, force=False):
    pkg_file = os.path.basename(zpath)
    pkg_sha = hashlib.sha256(open(zpath, 'rb').read()).hexdigest()
    with zipfile.ZipFile(zpath) as zf:
        names = zf.namelist()
        root = names[0].split('/')[0]
        def rd(fn):
            try:
                # utf-8-sig: the source registries were written by Excel and carry a BOM, which
                # otherwise turns the first CSV header into "﻿source_id" and silently drops
                # every source_id in the package.
                with zf.open(f'{root}/{fn}') as fh: return fh.read().decode('utf-8-sig')
            except KeyError:
                return None

        manifest = json.loads(rd('01_manifest.json') or '{}')
        taxonomy = json.loads(rd('03_taxonomy.json') or '{}')
        package_id = manifest.get('package_id') or root
        version = str(manifest.get('version') or manifest.get('package_version') or '2026.07.31')

        run_id = None
        if not dry:
            res = call('begin_run', package_id=package_id, package_version=version, package_sha256=pkg_sha)
            if not res.get('ok'):
                report['packages'].append({'package': pkg_file, 'error': res}); return
            if res.get('reused') and res.get('status') == 'completed' and not force:
                report['packages'].append({'package': pkg_file, 'skipped': 'already_completed',
                                           'run_id': res['run_id']})
                return
            run_id = res['run_id']
            hashes = (call('get_hashes', package_id=package_id).get('hashes') or {})
        else:
            hashes = {}

        w = Writer(dry)
        counts = {}

        # ---- taxonomy first: records carry category_slug, and a category row must exist for the
        # subcategory FK. Sources next, because record.source_ids point at them.
        # 03_taxonomy.json also comes in two shapes: 6 packages put the category fields at the top
        # level, 61 nest them under "category". Reading only the first shape left 61 of 67 domains
        # with no category row at all - and since kb_stage.subcategories has an FK to categories,
        # every one of their subcategories would have been dropped too. The bilingual subcategory
        # aliases live in there, so that silently removes the Arabic routing vocabulary for 91% of
        # the corpus while the record counts still look perfect.
        cat = taxonomy.get('category') if isinstance(taxonomy.get('category'), dict) else {}
        cat_slug = taxonomy.get('category_slug') or cat.get('slug')
        if cat_slug:
            w.add('categories', {
                'category_slug': cat_slug,
                'category_number': taxonomy.get('category_number') or cat.get('founder_sequence') or cat.get('number'),
                'category_name_en': taxonomy.get('category_name_en') or cat.get('name_en') or cat_slug,
                'category_name_ar': taxonomy.get('category_name_ar') or cat.get('name_ar'),
                'package_id': package_id, 'package_version': version, 'package_zip': pkg_file,
                'aliases': as_list(taxonomy.get('aliases') or cat.get('aliases')), 'raw': taxonomy,
            })
            w.flush('categories')
            for sub in taxonomy.get('subcategories') or []:
                if not sub.get('slug'): continue
                w.add('subcategories', {
                    'category_slug': cat_slug, 'subcategory_slug': sub.get('slug'),
                    'subcategory_number': sub.get('number') or sub.get('sort'),
                    'name_en': sub.get('name_en') or sub.get('slug'), 'name_ar': sub.get('name_ar'),
                    'aliases_en': as_list(sub.get('aliases_en')), 'aliases_ar': as_list(sub.get('aliases_ar')),
                    'raw': sub,
                })
            w.flush('subcategories')

        src = rd('19_source_registry.csv')
        if src:
            for row in csv.DictReader(io.StringIO(src)):
                sid = row.get('source_id') or row.get('id')
                if not sid: continue
                w.add('sources', {
                    'source_id': sid, 'title': row.get('title') or sid,
                    'publisher': row.get('publisher'), 'url': row.get('url'),
                    'source_type': row.get('source_type') or row.get('type'),
                    'jurisdiction': row.get('jurisdiction'),
                    'published_date': row.get('published_date'), 'accessed_date': row.get('accessed_date'),
                    'notes': row.get('notes'), 'raw': row,
                })
            w.flush('sources')

        gaps = rd('20_gap_register.csv')
        if gaps and not dry:
            for row in csv.DictReader(io.StringIO(gaps)):
                w.add('knowledge_gaps', {
                    'package_id': package_id, 'category_slug': cat_slug,
                    'subcategory_slug': row.get('subcategory_slug'),
                    'gap': (row.get('gap') or row.get('description') or json.dumps(row))[:4000],
                    'severity': row.get('severity') or row.get('priority'),
                    'raw': row, 'ingestion_run_id': run_id,
                })
            w.flush('knowledge_gaps')

        # ---- module records
        rejected = []
        for fn in MODULE_FILES:
            member = f'{root}/{fn}'
            if member not in names: continue
            raw = zf.read(member)
            fsha = hashlib.sha256(raw).hexdigest()
            if hashes.get(fn, {}).get('sha256') == fsha and not force:
                counts[fn] = 'skipped_unchanged'; continue
            n = 0
            for line in io.TextIOWrapper(io.BytesIO(raw), 'utf-8'):
                line = line.strip()
                if not line: continue
                try:
                    rec = json.loads(line)
                except Exception as e:                             # noqa: BLE001
                    rejected.append({'file': fn, 'id': None, 'reason': f'json: {e}'}); continue
                probs = validate(rec, 'record')
                if probs:
                    rejected.append({'file': fn, 'id': rec.get('record_id'), 'reason': '; '.join(probs)}); continue
                n += 1
                w.add('records', record_row(rec, package_id, run_id))
                m = rec['module']
                if m == 'inquiry_qualification':   w.add('questions', question_row(rec, run_id))
                elif m == 'validation':            w.add('validation_rules', validation_row(rec, run_id))
                elif m == 'scenario_test':         w.add('scenario_tests', scenario_row(rec, run_id))
            # records must be committed before their children (FK record_id)
            w.flush('records')
            w.flush('questions'); w.flush('validation_rules'); w.flush('scenario_tests')
            counts[fn] = n
            if not dry:
                call('put_hash', package_id=package_id, file_name=fn, sha256=fsha, rows_seen=n, run_id=run_id)

        # ---- decision rules (different shape, no FK)
        member = f'{root}/{RULES_FILE}'
        if member in names:
            raw = zf.read(member); fsha = hashlib.sha256(raw).hexdigest()
            if hashes.get(RULES_FILE, {}).get('sha256') == fsha and not force:
                counts[RULES_FILE] = 'skipped_unchanged'
            else:
                n = 0
                for line in io.TextIOWrapper(io.BytesIO(raw), 'utf-8'):
                    line = line.strip()
                    if not line: continue
                    try: r = json.loads(line)
                    except Exception as e:                          # noqa: BLE001
                        rejected.append({'file': RULES_FILE, 'id': None, 'reason': f'json: {e}'}); continue
                    probs = validate(r, 'rule')
                    shape = rule_shape(r)
                    if not shape: probs.append('unrecognised rule shape (no rule_id, no wrapped structured_data)')
                    if probs:
                        rejected.append({'file': RULES_FILE, 'id': r.get('rule_id') or r.get('record_id'),
                                         'reason': '; '.join(probs)}); continue
                    n += 1
                    if shape == 'wrapped':
                        rprobs = validate(r, 'record')
                        if not rprobs:
                            w.add('records', record_row(r, package_id, run_id))
                    w.add('decision_rules', rule_row(r, run_id, shape))
                w.flush('records')
                w.flush('decision_rules')
                counts[RULES_FILE] = n
                if not dry:
                    call('put_hash', package_id=package_id, file_name=RULES_FILE, sha256=fsha, rows_seen=n, run_id=run_id)

        w.flush()
        total = sum(v for v in counts.values() if isinstance(v, int))
        entry = {'package': pkg_file, 'package_id': package_id, 'version': version,
                 'sha256': pkg_sha[:16], 'run_id': run_id, 'rows': total,
                 'by_file': counts, 'written': w.written,
                 'rejected': len(rejected), 'rejected_detail': rejected[:50],
                 'write_errors': w.errors[:10]}
        report['packages'].append(entry)
        if not dry:
            call('finish_run', run_id=run_id,
                 status='completed' if not w.errors else 'completed_with_errors',
                 inserted_count=total, rejected_count=len(rejected),
                 report={'by_file': counts, 'rejected': len(rejected), 'write_errors': w.errors[:10]})
        print(f'  {pkg_file:70s} rows={total:>6} rejected={len(rejected):>4} errs={len(w.errors)}', flush=True)


def scan_expected(zips):
    """Walk the archives WITHOUT writing and return exactly what a correct database would hold.

    This is the number the 4 Aug run never computed. It reported 52,697 "rows", which was lines
    read from files - a quantity that is identical whether the writes updated 12,929 rows or
    inserted 3,325 extra ones.
    """
    rules, records = {}, set()
    for z in zips:
        with zipfile.ZipFile(os.path.join(PKG_DIR, z)) as zf:
            names = zf.namelist(); root = names[0].split('/')[0]
            for fn in MODULE_FILES:
                m = f'{root}/{fn}'
                if m not in names: continue
                for line in io.TextIOWrapper(io.BytesIO(zf.read(m)), 'utf-8'):
                    line = line.strip()
                    if not line: continue
                    try: rec = json.loads(line)
                    except Exception: continue                      # noqa: BLE001
                    if not validate(rec, 'record') and rec.get('record_id'):
                        records.add(rec['record_id'])
            m = f'{root}/{RULES_FILE}'
            if m in names:
                for line in io.TextIOWrapper(io.BytesIO(zf.read(m)), 'utf-8'):
                    line = line.strip()
                    if not line: continue
                    try: r = json.loads(line)
                    except Exception: continue                      # noqa: BLE001
                    shape = rule_shape(r)
                    if not shape or validate(r, 'rule'): continue
                    key = canonical_rule_key(r, shape)
                    sd = r.get('structured_data') or {}
                    rules[key] = {'source_rule_id': (r['rule_id'] if shape == 'flat' else sd.get('rule_id')),
                                  'record_id': (r.get('record_id') if shape == 'wrapped' else None)}
                    if shape == 'wrapped' and not validate(r, 'record') and r.get('record_id'):
                        records.add(r['record_id'])
    return rules, records


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project-ref', default=None, help='target Supabase project ref')
    ap.add_argument('--i-mean-production', action='store_true')
    ap.add_argument('--preflight-only', action='store_true',
                    help='measure the database against the archives and exit; writes nothing')
    ap.add_argument('--allow-stale', action='store_true')
    ap.add_argument('--no-preflight', action='store_true', help='escape hatch; recorded in the report')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--only', default=None, help='substring filter on the package filename')
    ap.add_argument('--out', default=None)
    ap.add_argument('--workers', type=int, default=1,
                    help='packages imported concurrently. Safe: every foreign key in the corpus is '
                         'within a package (records->questions, categories->subcategories), and one '
                         'package is always handled start-to-finish by one worker.')
    a = ap.parse_args()

    if a.project_ref: set_target(a.project_ref, a.i_mean_production)
    elif PROJECT_REF == PROD_REF and not a.i_mean_production and not a.dry_run:
        sys.exit('refusing: no --project-ref given and the default is production. '
                 'Pass --project-ref <staging> or --i-mean-production.')

    zips = sorted(z for z in os.listdir(PKG_DIR) if z.endswith('.zip'))
    if a.only: zips = [z for z in zips if a.only in z]
    report = {'started_at': datetime.now(timezone.utc).isoformat(), 'dry_run': a.dry_run,
              'project_ref': PROJECT_REF, 'package_count': len(zips), 'packages': []}
    print(f'{"DRY RUN" if a.dry_run else "IMPORT"}: {len(zips)} packages -> {PROJECT_REF}')

    # ---- PRE-FLIGHT. Before a single row is written.
    before = expected_rules = expected_records = None
    if not a.dry_run and not a.no_preflight:
        print('preflight: scanning archives...', flush=True)
        exp_rules, exp_records = scan_expected(zips)
        expected_rules, expected_records = len(exp_rules), len(exp_records)
        present = fetch_rule_keys(PROJECT_REF)
        verdict = classify(exp_rules, present)
        before = digests(PROJECT_REF)
        report['preflight'] = verdict
        print('preflight: ' + json.dumps({k: v for k, v in verdict.items() if not k.endswith('sample')}))
        try:
            gate(verdict, allow_stale=a.allow_stale)
        except (UpsertKeyChanged, StaleKeysPresent) as e:
            report['preflight_refused'] = str(e)
            json.dump(report, open(a.out or os.path.join(BASE, 'preflight_report.json'), 'w'), indent=1)
            sys.exit(f'\nPREFLIGHT REFUSED\n{e}')
        if a.preflight_only:
            json.dump(report, open(a.out or os.path.join(BASE, 'preflight_report.json'), 'w'), indent=1)
            print('preflight only — nothing written.'); return
    elif a.no_preflight:
        report['preflight'] = 'SKIPPED via --no-preflight'
    if a.workers > 1:
        from concurrent.futures import ThreadPoolExecutor
        lock = __import__('threading').Lock()
        safe = []
        def one(z):
            local = {'packages': []}
            import_package(os.path.join(PKG_DIR, z), a.dry_run, local, force=a.force)
            with lock: safe.extend(local['packages'])
        with ThreadPoolExecutor(max_workers=a.workers) as ex:
            list(ex.map(one, zips))
        report['packages'] = sorted(safe, key=lambda p: p.get('package', ''))
    else:
        for z in zips:
            import_package(os.path.join(PKG_DIR, z), a.dry_run, report, force=a.force)
    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    report['total_rows'] = sum(p.get('rows', 0) for p in report['packages'])
    report['total_rejected'] = sum(p.get('rejected', 0) for p in report['packages'])
    report['total_write_errors'] = sum(len(p.get('write_errors') or []) for p in report['packages'])

    # ---- RECONCILE. Measured from the database, not asserted by the writer.
    # "rows=52,697 rejected=0 write_errors=0" is what a 3,325-row duplication looked like.
    # A report that cannot print `inserted=` cannot describe an idempotent run.
    if before is not None:
        after = digests(PROJECT_REF)
        rec = reconcile(before, after, expected_rules, expected_records, report['total_rejected'])
        report['reconciliation'] = rec
        print('\nreconciliation: ' + json.dumps(rec, indent=1))
        if not rec['count_matches_archive']:
            report['verdict'] = 'MISMATCH'
            print(f"\nCOUNT MISMATCH — rules {rec['rules_after']} vs expected {rec['rules_expected']}, "
                  f"records {rec['records_after']} vs expected {rec['records_expected']}")
        else:
            report['verdict'] = 'OK'

    out = a.out or os.path.join(BASE, 'dry_run_report.json' if a.dry_run else 'import_report.json')
    json.dump(report, open(out, 'w'), indent=1)
    r = report.get('reconciliation') or {}
    print(f'\nseen={report["total_rows"]:,} rejected={report["total_rejected"]:,} '
          f'write_errors={report["total_write_errors"]} '
          f'inserted={r.get("rules_inserted", "n/a")} '
          f'rules={r.get("rules_after", "n/a")}/{r.get("rules_expected", "n/a")} '
          f'records={r.get("records_after", "n/a")}/{r.get("records_expected", "n/a")}  -> {out}')
    if report.get('verdict') == 'MISMATCH':
        sys.exit(1)


if __name__ == '__main__':
    main()
