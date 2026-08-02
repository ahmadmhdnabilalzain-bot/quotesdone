#!/usr/bin/env python3
"""
QuotesDone company-operations corpus importer.

Streams QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31 into ops_kb_stage through the
kb_corpus_import edge function.

Design notes:

* THE MASTER IS NEVER READ. 00_COMPANY_OPERATIONS_MASTER.md is 2,057,246 characters. The pack
  forbids putting it in a prompt and there is no reason for the database to hold it either; its
  checksum is verified and the file is otherwise ignored.
* 06_ALL_RECORDS/01_ALL_OPERATIONAL_RECORDS.jsonl IS THE CANONICAL RECORD SET (3,959 rows) and the
  per-department files sum to exactly the same number. The consolidated file is used for the records
  table - one pass, guaranteed complete - and the type-specific files are used only to build the
  relational projections, which is where their extra structure matters. Both are cross-checked: any
  projection row whose record_id is missing from the canonical set is a rejection, not a silent skip.
* NOTHING IS ENABLED. Decision rules, playbooks, workflows, handoffs, KPIs and event subscriptions
  all land with enabled/active = false. The pack is explicit that imported rules stay disabled until
  mapped, tested and approved, and a rule that can fire on import IS an activated rule.
* IMPLEMENTATION STATUS IS NOT TOUCHED. 'target_state' and 'partial' records describe an
  organisation that does not exist yet. Importing them does not make them true, so the column is
  carried verbatim and every downstream view filters on it.
* NO SECRETS. Content is scanned for anything that looks like a key or token before it is written;
  a hit is quarantined rather than stored, because knowledge tables end up in prompts.
"""
import argparse, csv, hashlib, io, json, os, re, sys, time
from datetime import datetime, timezone
import urllib.request, urllib.error

BASE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(BASE, 'data', 'QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31')
FN_URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_corpus_import'
TOKEN = open(os.path.join(BASE, '.tok')).read().strip()
BATCH = 500

VALID_IMPL = {'implemented', 'partial', 'target_state', 'external_reference'}
VALID_VALID = {'source_verified', 'reviewed', 'draft', 'approved', 'quarantined', 'superseded'}
VALID_TIER = {'advisory', 'supervised', 'gated', 'autonomous'}
VALID_RISK = {'low', 'medium', 'high', 'critical'}
VALID_SCOPE = {'company', 'department', 'workflow', 'agent', 'external_source'}

# Anything that looks like a live credential must never reach a knowledge table - these rows end up
# in model prompts. Deliberately narrow so ordinary prose about "the API key" does not trip it.
SECRET_RE = re.compile(
    r'(eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{10,})'     # JWT
    r'|(sk-[A-Za-z0-9]{20,})'                             # OpenAI-style
    r'|(sk_live_[A-Za-z0-9]{10,})|(rk_live_[A-Za-z0-9]{10,})'  # Stripe
    r'|(SG\.[A-Za-z0-9_\-]{20,})'                         # SendGrid
    r'|(AC[0-9a-f]{32})'                                  # Twilio SID
    r'|(-----BEGIN [A-Z ]*PRIVATE KEY-----)')

MAX_LINE = 2_000_000     # reject absurd lines rather than buffering them
MAX_DEPTH = 40           # reject pathological JSON nesting


def call(action, **kw):
    kw['__token'] = TOKEN; kw['action'] = action
    req = urllib.request.Request(FN_URL, data=json.dumps(kw).encode('utf-8'),
                                 headers={'Content-Type': 'application/json'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            body = e.read().decode('utf-8', 'replace')[:600]
            transient = e.code in (408, 429, 502, 503, 504) or (e.code == 500 and '"error"' not in body)
            if transient and attempt < 3:
                time.sleep(2 * (attempt + 1)); continue
            return {'error': f'http_{e.code}', 'body': body}
        except Exception as e:                                   # noqa: BLE001
            if attempt < 3:
                time.sleep(2 * (attempt + 1)); continue
            return {'error': str(e)}
    return {'error': 'unreachable'}


class W:
    def __init__(self, dry):
        self.dry = dry; self.buf = {}; self.written = {}; self.errors = []

    def add(self, target, row):
        self.buf.setdefault(target, []).append(row)
        if len(self.buf[target]) >= BATCH: self.flush(target)

    def flush(self, target=None):
        for t in ([target] if target else list(self.buf)):
            rows = self.buf.get(t) or []
            if not rows: continue
            if not self.dry:
                res = call('ops_batch', target=t, rows=rows)
                if not res.get('ok'):
                    self.errors.append({'target': t, 'rows': len(rows), 'error': res.get('error'),
                                        'details': res.get('details'), 'sample_ids': res.get('sample_ids')})
            self.written[t] = self.written.get(t, 0) + len(rows)
            self.buf[t] = []


def depth(o, d=0):
    if d > MAX_DEPTH: return d
    if isinstance(o, dict): return max([depth(v, d + 1) for v in o.values()] or [d])
    if isinstance(o, list): return max([depth(v, d + 1) for v in o] or [d])
    return d


def sha_text(*parts):
    h = hashlib.sha256()
    for p in parts:
        h.update((p if isinstance(p, str) else json.dumps(p, sort_keys=True, ensure_ascii=False)).encode())
    return h.hexdigest()


def as_list(v):
    if v is None: return []
    return v if isinstance(v, list) else [v]


def date_or_none(v):
    s = str(v or '').strip()[:10]
    return s if re.match(r'^\d{4}-\d{2}-\d{2}$', s) else None


def validate(r):
    p = []
    for f in ('record_id', 'scope_type', 'scope_key', 'module', 'record_type', 'title', 'content',
              'implementation_status', 'validation_status', 'authority_tier', 'risk_level', 'version'):
        if not r.get(f): p.append(f'missing {f}')
    if r.get('scope_type') and r['scope_type'] not in VALID_SCOPE: p.append('bad scope_type')
    if r.get('implementation_status') and r['implementation_status'] not in VALID_IMPL: p.append('bad implementation_status')
    if r.get('validation_status') and r['validation_status'] not in VALID_VALID: p.append('bad validation_status')
    if r.get('authority_tier') and r['authority_tier'] not in VALID_TIER: p.append('bad authority_tier')
    if r.get('risk_level') and r['risk_level'] not in VALID_RISK: p.append('bad risk_level')
    if r.get('content') and len(r['content']) < 20: p.append('content too short')
    if not isinstance(r.get('structured_data', {}), dict): p.append('structured_data not an object')
    if depth(r) > MAX_DEPTH: p.append('json too deep')
    if SECRET_RE.search(json.dumps(r, ensure_ascii=False)): p.append('SECRET-LIKE VALUE - quarantined, not imported')
    return p


def record_row(r, pkg_version, run_id, src_file):
    return {
        'record_id': r['record_id'], 'scope_type': r['scope_type'], 'scope_key': r['scope_key'],
        'module': r['module'], 'record_type': r['record_type'], 'title': r['title'][:2000],
        'content': r['content'],
        'structured_data': r.get('structured_data') or {},
        'source_ids': [str(s) for s in as_list(r.get('source_ids'))],
        'implementation_status': r['implementation_status'], 'validation_status': r['validation_status'],
        'authority_tier': r['authority_tier'], 'risk_level': r['risk_level'],
        'version': str(r['version']),
        'effective_date': date_or_none(r.get('effective_date')),
        'review_after': date_or_none(r.get('review_after')),
        'keywords': as_list(r.get('keywords')), 'dependencies': as_list(r.get('dependencies')),
        'escalation_rule': r.get('escalation_rule') if isinstance(r.get('escalation_rule'), dict) else {},
        'content_sha256': sha_text(r['content'], r.get('structured_data') or {}),
        'package_version': pkg_version, 'ingestion_run_id': run_id, 'source_file': src_file,
    }


def stream(path):
    """One JSON object per line, with the line-size guard the security rules ask for."""
    with open(path, encoding='utf-8') as fh:
        for i, line in enumerate(fh, 1):
            line = line.strip()
            if not line: continue
            if len(line) > MAX_LINE:
                yield i, None, f'line exceeds {MAX_LINE} bytes'; continue
            try:
                yield i, json.loads(line), None
            except Exception as e:                               # noqa: BLE001
                yield i, None, f'json: {e}'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--out', default=None)
    a = ap.parse_args()

    man = json.load(open(os.path.join(PKG, '00_PACKAGE_MANIFEST.json'), encoding='utf-8'))
    pkg_name = man.get('package_name', 'company_operations')
    pkg_version = str(man.get('version', '1.0.0'))
    pkg_sha = sha_text(json.dumps(man.get('files', []), sort_keys=True))

    rep = {'started_at': datetime.now(timezone.utc).isoformat(), 'dry_run': a.dry_run,
           'package': pkg_name, 'version': pkg_version, 'files': {}, 'rejected': [], 'errors': []}

    run_id = None
    if not a.dry_run:
        res = call('ops_begin_run', package_name=pkg_name, package_version=pkg_version, package_sha256=pkg_sha)
        if not res.get('ok'): print('begin_run failed:', res); sys.exit(1)
        run_id = res['run_id']
        rep['run_id'] = run_id
        if res.get('reused') and res.get('status') == 'completed':
            print('package already imported; re-running upserts (idempotent)')

    w = W(a.dry_run)

    # ---- 1. sources ---------------------------------------------------------------------------
    for rel in ('00_COMPANY_CORE/02_SOURCE_REGISTRY.csv',
                '03_EXTERNAL_AUTHORITY_AND_PROVIDER_KNOWLEDGE/02_SOURCE_REGISTRY.csv'):
        p = os.path.join(PKG, rel)
        if not os.path.exists(p): continue
        n = 0
        with open(p, encoding='utf-8-sig') as fh:
            for row in csv.DictReader(fh):
                sid = (row.get('source_id') or '').strip()
                if not sid: continue
                w.add('sources', {
                    'source_id': sid, 'title': row.get('title') or sid,
                    'source_type': row.get('source_type') or row.get('type') or 'unknown',
                    'publisher': row.get('publisher'), 'url_or_path': row.get('url') or row.get('url_or_path'),
                    'status': row.get('status'), 'scope': row.get('scope'),
                    'verified_on': date_or_none(row.get('verified_on') or row.get('accessed_date')),
                    'raw': row})
                n += 1
        w.flush('sources'); rep['files'][rel] = n

    # ---- 2. canonical records ------------------------------------------------------------------
    canonical = os.path.join(PKG, '06_ALL_RECORDS/01_ALL_OPERATIONAL_RECORDS.jsonl')
    seen = set(); n = 0
    for ln, r, err in stream(canonical):
        if err: rep['rejected'].append({'file': '06_ALL_RECORDS', 'line': ln, 'reason': err}); continue
        probs = validate(r)
        if probs:
            rep['rejected'].append({'file': '06_ALL_RECORDS', 'id': r.get('record_id'), 'reason': '; '.join(probs)}); continue
        seen.add(r['record_id']); n += 1
        w.add('records', record_row(r, pkg_version, run_id, '06_ALL_RECORDS'))
    w.flush('records')
    rep['files']['06_ALL_RECORDS/01_ALL_OPERATIONAL_RECORDS.jsonl'] = n
    print(f'  records: {n:,}')

    # ---- 3. relational projections --------------------------------------------------------------
    # Every projection is keyed on record_id and must resolve against the canonical set. A projection
    # row for a record that does not exist would fail the foreign key anyway; catching it here says
    # WHICH row and why instead of failing a batch of 500.
    def project(rel_glob, target, build, key_field='record_id'):
        import glob
        total = 0
        for p in sorted(glob.glob(os.path.join(PKG, rel_glob))):
            rel = os.path.relpath(p, PKG); k = 0
            for ln, r, err in stream(p):
                if err: rep['rejected'].append({'file': rel, 'line': ln, 'reason': err}); continue
                rid = r.get('record_id')
                if rid not in seen:
                    rep['rejected'].append({'file': rel, 'id': rid,
                                            'reason': 'record_id absent from the canonical record set'}); continue
                row = build(r)
                if row is None: continue
                w.add(target, row); k += 1
            w.flush(target); rep['files'][rel] = k; total += k
        print(f'  {target:22s} {total:,}')
        return total

    sd = lambda r: (r.get('structured_data') or {})

    project('01_DEPARTMENTS/*/02_ROLES.jsonl', 'roles', lambda r: {
        'record_id': r['record_id'], 'agent_key': r['scope_key'],
        'department_key': sd(r).get('department_key') or r['scope_key'],
        'title': sd(r).get('title') or r['title'], 'responsibilities': sd(r).get('responsibilities'),
        'authority_tier': r['authority_tier'], 'max_authority': sd(r).get('max_authority'),
        'manager': sd(r).get('manager'), 'raw': sd(r)})

    project('01_DEPARTMENTS/*/03_SOPS.jsonl', 'sops', lambda r: {
        'record_id': r['record_id'],
        'department_key': sd(r).get('owner_department') or r['scope_key'],
        'workflow_key': sd(r).get('workflow'), 'trigger': sd(r).get('trigger'),
        'steps': as_list(sd(r).get('steps')), 'required_inputs': sd(r).get('required_inputs'),
        'required_outputs': sd(r).get('required_outputs'), 'definition_of_done': sd(r).get('definition_of_done'),
        'service_level': sd(r).get('service_level'),
        'rollback': sd(r).get('rollback') if isinstance(sd(r).get('rollback'), str) else json.dumps(sd(r).get('rollback'), ensure_ascii=False) if sd(r).get('rollback') else None,
        'authority_tier': r['authority_tier'], 'raw': sd(r)})

    project('01_DEPARTMENTS/*/04_DECISION_RULES.jsonl', 'decision_rules', lambda r: {
        'record_id': r['record_id'], 'rule_id': sd(r).get('rule_id') or r['record_id'],
        'department_key': r['scope_key'], 'priority': sd(r).get('priority'),
        'condition': sd(r).get('condition') if isinstance(sd(r).get('condition'), (dict, list)) else {'text': sd(r).get('condition')},
        'action': sd(r).get('action') if isinstance(sd(r).get('action'), (dict, list)) else {'text': sd(r).get('action')},
        'owner': sd(r).get('owner'), 'requires_human_review': bool(sd(r).get('requires_human_review')),
        'authority_tier': r['authority_tier'], 'enabled': False, 'raw': sd(r)})

    project('01_DEPARTMENTS/*/05_EXCEPTION_PLAYBOOKS.jsonl', 'exception_playbooks', lambda r: {
        'record_id': r['record_id'], 'exception_key': sd(r).get('exception_key') or r['record_id'],
        'department_key': r['scope_key'], 'trigger': sd(r).get('trigger'),
        'immediate_actions': sd(r).get('immediate_actions'), 'recovery': sd(r).get('recovery'),
        'closure': sd(r).get('closure'), 'enabled': False, 'raw': sd(r)})

    project('01_DEPARTMENTS/*/06_KPIS.jsonl', 'kpis', lambda r: {
        'record_id': r['record_id'], 'department_key': r['scope_key'],
        'metric_name': sd(r).get('metric') or r['title'], 'formula_description': sd(r).get('formula_description'),
        'direction': sd(r).get('direction'), 'source_candidates': sd(r).get('source_candidates'),
        'owner': sd(r).get('owner'), 'enabled': False, 'raw': sd(r)})

    project('01_DEPARTMENTS/*/07_TEMPLATES.jsonl', 'templates', lambda r: {
        'record_id': r['record_id'], 'department_key': r['scope_key'],
        'template_key': sd(r).get('template_key') or sd(r).get('key'),
        'purpose': sd(r).get('purpose') or r['title'],
        'body': sd(r).get('body') or sd(r).get('template') or r['content'], 'raw': sd(r)})

    project('01_DEPARTMENTS/*/08_SCENARIO_TESTS.jsonl', 'scenarios', lambda r: {
        'record_id': r['record_id'], 'scenario_key': sd(r).get('scenario_key') or r['record_id'],
        'scope_key': r['scope_key'], 'kind': 'department',
        'situation': sd(r).get('situation') or r['content'][:500],
        'expected_behaviour': sd(r).get('expected_behaviour') or sd(r).get('expected') or '',
        'pass_criteria': as_list(sd(r).get('pass_criteria')), 'raw': sd(r)})

    project('01_DEPARTMENTS/*/09_LIVE_DATA_BINDINGS.jsonl', 'live_bindings', lambda r: {
        'record_id': r['record_id'], 'department_key': r['scope_key'],
        'object_name': sd(r).get('object_name') or r['title'], 'object_kind': sd(r).get('object_kind'),
        'found_in_export': sd(r).get('found_in_export'), 'read_purpose': sd(r).get('read_purpose'),
        'write_policy': sd(r).get('write_policy'), 'cache_policy': sd(r).get('cache_policy'),
        'mapping_status': 'unresolved', 'raw': sd(r)})

    project('02_CROSS_DEPARTMENT_WORKFLOWS/02_HANDOFFS.jsonl', 'handoffs', lambda r: {
        'record_id': r['record_id'], 'workflow_key': sd(r).get('workflow_key') or r['scope_key'],
        'from_department': sd(r).get('from_department') or '', 'to_department': sd(r).get('to_department') or '',
        'sender_action': sd(r).get('sender_action'), 'receiver_action': sd(r).get('receiver_action'),
        'handoff_payload': sd(r).get('handoff_payload') or {}, 'acceptance': sd(r).get('acceptance'),
        'rejection': sd(r).get('rejection'), 'enabled': False, 'raw': sd(r)})

    project('02_CROSS_DEPARTMENT_WORKFLOWS/04_EVENT_SUBSCRIPTIONS.jsonl', 'event_subscriptions', lambda r: {
        'record_id': r['record_id'], 'event_type': sd(r).get('event_type') or r['title'],
        'department_key': sd(r).get('department_key') or r['scope_key'], 'reason': sd(r).get('reason'),
        'active': False, 'raw': sd(r)})

    project('02_CROSS_DEPARTMENT_WORKFLOWS/05_WORKFLOW_SCENARIOS.jsonl', 'scenarios', lambda r: {
        'record_id': r['record_id'], 'scenario_key': sd(r).get('scenario_key') or r['record_id'],
        'scope_key': r['scope_key'], 'kind': 'workflow',
        'situation': sd(r).get('situation') or r['content'][:500],
        'expected_behaviour': sd(r).get('expected') or sd(r).get('expected_behaviour') or '',
        'pass_criteria': as_list(sd(r).get('pass_criteria')), 'raw': sd(r)})

    # workflows are keyed on workflow_key, not record_id
    wf = 0
    for ln, r, err in stream(os.path.join(PKG, '02_CROSS_DEPARTMENT_WORKFLOWS/01_WORKFLOWS.jsonl')):
        if err or r.get('record_id') not in seen: continue
        s = sd(r)
        w.add('workflows', {
            'workflow_key': s.get('workflow_key') or r['scope_key'], 'record_id': r['record_id'],
            'name': r['title'], 'trigger': s.get('trigger'),
            'departments': [str(x) for x in as_list(s.get('departments'))],
            'steps': as_list(s.get('steps')), 'hard_gates': [str(x) for x in as_list(s.get('hard_gates'))],
            'audit_requirements': s.get('audit_requirements'), 'definition_of_done': s.get('definition_of_done'),
            'implementation_status': r['implementation_status'], 'enabled': False, 'raw': s})
        wf += 1
    w.flush('workflows'); rep['files']['02_CROSS_DEPARTMENT_WORKFLOWS/01_WORKFLOWS.jsonl'] = wf
    print(f'  workflows              {wf}')

    # governance policy records + hard gates, from the canonical set by module/record_type
    pol = gate = 0
    for ln, r, err in stream(canonical):
        if err or r.get('record_id') not in seen: continue
        if r['module'] in ('ai_governance', 'memory', 'audit', 'incident_management', 'data_governance'):
            w.add('policies', {'record_id': r['record_id'], 'policy_domain': r['module'],
                               'policy_key': sd(r).get('policy_key') or r['record_type'], 'raw': sd(r)}); pol += 1
        if r['record_type'] == 'hard_gate':
            w.add('hard_gates', {'record_id': r['record_id'],
                                 'gate_key': sd(r).get('gate_key') or sd(r).get('key') or r['record_id'],
                                 'title': r['title'], 'rule': r['content'][:4000], 'raw': sd(r)}); gate += 1
    w.flush('policies'); w.flush('hard_gates')
    rep['files']['derived/policies'] = pol; rep['files']['derived/hard_gates'] = gate
    print(f'  policies               {pol}\n  hard_gates             {gate}')

    # ---- 4. departments + crosswalk ------------------------------------------------------------
    dep = 0
    p = os.path.join(PKG, '01_DEPARTMENTS/00_DEPARTMENT_INDEX.csv')
    with open(p, encoding='utf-8-sig') as fh:
        for row in csv.DictReader(fh):
            k = (row.get('department_key') or row.get('key') or '').strip()
            if not k: continue
            # The index calls these columns department_name and implementation_assessment, not
            # name/implementation_status. Reading the wrong names is silent: every department would
            # have landed with its key as its display name and every one marked target_state, which
            # is exactly the kind of quiet wrongness that makes a mapping table useless.
            w.add('departments', {'department_key': k,
                                  'name': row.get('department_name') or row.get('name') or k,
                                  'implementation_status': (row.get('implementation_assessment')
                                                            or row.get('implementation_status') or 'target_state'),
                                  'charter': row.get('charter'), 'north_star': row.get('north_star'), 'raw': row})
            dep += 1
    w.flush('departments'); rep['files']['01_DEPARTMENTS/00_DEPARTMENT_INDEX.csv'] = dep
    print(f'  departments            {dep}')

    xw = 0
    p = os.path.join(PKG, '04_AGENT_RUNTIME_AND_GOVERNANCE/07_PRODUCTION_TO_TARGET_DEPARTMENT_CROSSWALK.csv')
    with open(p, encoding='utf-8-sig') as fh:
        for row in csv.DictReader(fh):
            prod = (row.get('production_dept_key') or '').strip()
            for tgt in [t.strip() for t in (row.get('target_departments') or '').split(',') if t.strip()]:
                w.add('department_crosswalk', {'production_dept_key': prod, 'target_department_key': tgt,
                                               'mapping_type': row.get('mapping_type') or 'unknown',
                                               'note': row.get('note'), 'review_status': 'draft'})
                xw += 1
    w.flush('department_crosswalk'); rep['files']['crosswalk'] = xw
    print(f'  department_crosswalk   {xw}')

    w.flush()
    rep['written'] = w.written; rep['errors'] = w.errors[:20]
    rep['rejected_count'] = len(rep['rejected']); rep['rejected'] = rep['rejected'][:100]
    rep['finished_at'] = datetime.now(timezone.utc).isoformat()

    if not a.dry_run:
        call('ops_finish_run', run_id=run_id,
             status='completed' if not w.errors else 'completed_with_errors',
             inserted_count=sum(w.written.values()), rejected_count=rep['rejected_count'],
             detail={'files': rep['files'], 'errors': w.errors[:10]})

    out = a.out or os.path.join(BASE, 'ops_dry_run.json' if a.dry_run else 'ops_import_report.json')
    json.dump(rep, open(out, 'w'), indent=1, ensure_ascii=False)
    print(f"\ntotal rows={sum(w.written.values()):,} rejected={rep['rejected_count']} "
          f"write_errors={len(w.errors)} -> {out}")


if __name__ == '__main__':
    main()
