#!/usr/bin/env python3
import csv,json,sys,pathlib
root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.')
rows=list(csv.DictReader(open(root/'00_CONTROL/01_OPERATIONAL_CATEGORY_INDEX_001-086.csv',encoding='utf-8')))
assert len(rows)==86 and [int(r['catalog_num']) for r in rows]==list(range(1,87))
files=sorted((root/'01_ROUTE_MANIFESTS').glob('*.json')); assert len(files)==86
for p in files:
 m=json.load(open(p,encoding='utf-8')); assert m['knowledge_mappings']; assert m['catalog_num'] in range(1,87); assert m['routing_aliases_en']
print({'routes':86,'manifests':86,'verdict':'PASS'})
