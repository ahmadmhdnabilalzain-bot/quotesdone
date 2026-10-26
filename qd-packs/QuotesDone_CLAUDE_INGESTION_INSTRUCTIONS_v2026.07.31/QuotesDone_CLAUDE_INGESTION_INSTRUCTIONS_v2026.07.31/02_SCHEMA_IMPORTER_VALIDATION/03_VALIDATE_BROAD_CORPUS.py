#!/usr/bin/env python3
"""Validate package structure without exposing corpus text to an LLM."""
import csv, hashlib, json, sys
from pathlib import Path
from jsonschema import Draft202012Validator

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''): h.update(c)
    return h.hexdigest()

def main(root):
    reports=[]
    for d in sorted(Path(root).glob('QD-KB-*')):
        if not d.is_dir(): continue
        manifest=json.loads((d/'21_ingestion_manifest.json').read_text())
        schema_file=d/(manifest.get('schema') or '25_knowledge_record_schema.json')
        if not schema_file.exists():
            schema_file=Path(root)/'QuotesDone_Knowledge_Record_Schema.json'
        schema=json.loads(schema_file.read_text())
        validator=Draft202012Validator(schema)
        ids=set(); errors=[]; counts={}
        for name in manifest.get('load_order',[]):
            p=d/name
            if not p.exists(): errors.append(f'missing:{name}'); continue
            if p.suffix!='.jsonl': continue
            n=0
            for line_no,line in enumerate(p.open(encoding='utf8'),1):
                if not line.strip(): continue
                n+=1; r=json.loads(line)
                rid=r.get('record_id') or r.get('rule_id') or r.get('question_id')
                if rid in ids: errors.append(f'duplicate:{rid}')
                ids.add(rid)
                for e in validator.iter_errors(r): errors.append(f'{name}:{line_no}:{e.message}')
            counts[name]=n
        reports.append({'package':d.name,'counts':counts,'unique_ids':len(ids),'errors':errors[:200],'error_count':len(errors)})
    print(json.dumps(reports,indent=2))
    return 1 if any(r['error_count'] for r in reports) else 0
if __name__=='__main__': raise SystemExit(main(sys.argv[1]))
