// scripts/e2e/journey_proof/sheet.mjs — phone screenshots side by side, captioned, as ONE picture the dossier can print
// at page width (the template draws one picture per line; three phone screens across is how a person reads a chat).
// Seat: customer_support. Uses Python's PIL, already on the machine; no network.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const FONT = fileURLToPath(new URL('../../../supabase/functions/pdf_native/fixtures/brand/qd_sora_regular.ttf', import.meta.url));

const PY = String.raw`
import sys, json
from PIL import Image, ImageDraw, ImageFont
a = json.loads(sys.argv[1])
cols, W, gap, pad = a['cols'], a['width'], 24, 18
try: font = ImageFont.truetype(a['font'], 22)
except Exception: font = ImageFont.load_default()
ims = []
for f in a['files']:
    im = Image.open(f).convert('RGB'); h = int(im.height * W / im.width); ims.append(im.resize((W, h)))
def wrap(t, w):
    out, cur = [], ''
    for word in t.split():
        test = (cur + ' ' + word).strip()
        if font.getlength(test) > w and cur: out.append(cur); cur = word
        else: cur = test
    return out + ([cur] if cur else [])
caps = [wrap(c or '', W) for c in a['captions']]
rows = [list(range(i, min(i + cols, len(ims)))) for i in range(0, len(ims), cols)]
heights = [max(ims[k].height for k in r) + 12 + 28 * max(len(caps[k]) for k in r) for r in rows]
sheet = Image.new('RGB', (pad * 2 + cols * W + (cols - 1) * gap, pad * 2 + sum(heights) + gap * (len(rows) - 1)), 'white')
d = ImageDraw.Draw(sheet); y = pad
for r, h in zip(rows, heights):
    for c, k in enumerate(r):
        x = pad + c * (W + gap); sheet.paste(ims[k], (x, y)); d.rectangle([x - 1, y - 1, x + W, y + ims[k].height], outline=(200, 205, 212), width=2)
        ty = y + ims[k].height + 8
        for ln in caps[k]: d.text((x, ty), ln, fill=(60, 70, 82), font=font); ty += 28
    y += h + gap
sheet.save(a['out'], optimize=True)
print(json.dumps({'out': a['out'], 'w': sheet.width, 'h': sheet.height}))
`;

/** files + captions -> one PNG, `cols` across (3 for phone screens, 1 for a desktop screen). */
export function sheet(files, captions, out, { cols = 3, width = 360, font = FONT } = {}) {
  if (!files.length) return null;
  const r = spawnSync('python3', ['-c', PY, JSON.stringify({ files, captions, out, cols, width, font })], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('sheet: ' + (r.stderr || '').slice(-400));
  return JSON.parse(r.stdout.trim().split('\n').pop());
}

/** Split a long list of shots into sheets of `per`: one row of three phone screens is about half a page. */
export function sheets(shots, outBase, { per = 3, cols = 3 } = {}) {
  const out = [];
  for (let i = 0; i < shots.length; i += per) {
    const part = shots.slice(i, i + per);
    const file = `${outBase}_${String(out.length + 1).padStart(2, '0')}.png`;
    sheet(part.map((s) => s.path), part.map((s) => s.caption), file, { cols });
    out.push({ path: file, caption: null });
  }
  return out;
}
