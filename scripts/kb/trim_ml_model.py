# THE ARABIC + ENGLISH TRIM OF multilingual-e5-small. Seat: it_engineer. 24 Sep 2026 (#907).
#
# Why: the full int8 model (118 MB) cannot load in a Supabase edge worker (it died at 298 MB, reason Memory).
# Keeps: the special tokens, every Arabic-script piece, every single-character piece (so any text still
# tokenizes), and every piece the knowledge corpus uses. The transformer is untouched: only rows of the
# word-embedding table and the matching tokenizer entries are dropped, so a text whose original pieces are all
# kept embeds to the SAME vector. Measured on the 24 Sep build: 250,002 -> 60,422 pieces, 45.5 MB, 70 texts
# (10 EN + 10 AR questions + 50 corpus rows) at cosine 1.00000 against the full model.
#
#   1. files from https://huggingface.co/Xenova/multilingual-e5-small (config.json, tokenizer.json,
#      tokenizer_config.json, special_tokens_map.json, onnx/model_quantized.onnx) into the working directory
#   2. node scripts/kb/trim_ml_model_corpus.mjs --out=corpus.txt
#   3. pip install onnx numpy tokenizers; py scripts/kb/trim_ml_model.py      -> ./trim/
#   4. upload ./trim/* to the public Storage bucket ml-models under multilingual-e5-small-ar-en/, and put the new
#      sha256 of trim/onnx/model_quantized.onnx and trim/tokenizer.json in _shared/ml_embed_recipe.ts.
#      A new trim is a NEW SPACE: every knowledge_vector_ml row must be re-embedded with it.
import json, re, sys, os, numpy as np, onnx
from onnx import numpy_helper
from tokenizers import Tokenizer
tok = Tokenizer.from_file('tokenizer.json')
t = json.load(open('tokenizer.json', encoding='utf8'))
vocab = t['model']['vocab']
AR = re.compile(r'^[▁؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]+$')
keep = set(range(4)) | {a['id'] for a in t['added_tokens']}
for i, (p, s) in enumerate(vocab):
    if AR.match(p) or len(p.replace('▁', '')) <= 1: keep.add(i)
base = len(keep)
lines = [l.rstrip('\n') for l in open('corpus.txt', encoding='utf8')]
for k in range(0, len(lines), 5000):
    for e in tok.encode_batch(lines[k:k+5000]): keep.update(e.ids)
print('kept', len(keep), 'base', base, 'lines', len(lines))
ids = sorted(keep); new = {o: n for n, o in enumerate(ids)}
# tokenizer
t['model']['vocab'] = [vocab[i] for i in ids if i < len(vocab)]
t['model']['unk_id'] = new[3]
for a in t['added_tokens']: a['id'] = new[a['id']]
pp = json.dumps(t['post_processor'])
assert '250001' not in pp
os.makedirs('trim/onnx', exist_ok=True)
json.dump(t, open('trim/tokenizer.json', 'w', encoding='utf8'), ensure_ascii=False)
c = json.load(open('config.json')); c['vocab_size'] = len(ids); json.dump(c, open('trim/config.json', 'w'), indent=2)
for f in ['tokenizer_config.json', 'special_tokens_map.json']: open('trim/' + f, 'w', encoding='utf8').write(open(f, encoding='utf8').read())
tc = json.load(open('trim/tokenizer_config.json', encoding='utf8'))
for k, v in list(tc.get('added_tokens_decoder', {}).items()):
    tc['added_tokens_decoder'].pop(k); tc['added_tokens_decoder'][str(new[int(k)])] = v
json.dump(tc, open('trim/tokenizer_config.json', 'w', encoding='utf8'), ensure_ascii=False, indent=2)
m = onnx.load('onnx/model_quantized.onnx')
for init in m.graph.initializer:
    if init.name == 'embeddings.word_embeddings.weight_quantized':
        a = numpy_helper.to_array(init); init.CopyFrom(numpy_helper.from_array(a[ids], init.name))
onnx.save(m, 'trim/onnx/model_quantized.onnx')
print('size MB', os.path.getsize('trim/onnx/model_quantized.onnx') / 1e6)
