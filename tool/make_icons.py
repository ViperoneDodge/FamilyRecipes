"""Genera icona, logo, icona adattiva, icona delle notifiche e splash da tool/branding/logo_source.png.
Uso: python3 tool/make_icons.py tool/branding/logo_source.png ."""
import sys, pathlib
from PIL import Image, ImageDraw, ImageFilter, ImageChops
src, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
CREAM = (254, 246, 232)
im = Image.open(src).convert('RGB')
N = im.size[0]
# Angoli neri fuori dal quadrato arrotondato -> crema
mask = Image.new('L', (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([14, 14, N - 15, N - 15], radius=int(N * 0.2), fill=255)
full = Image.new('RGB', (N, N), CREAM); full.paste(im, (0, 0), mask)
# Contenuto (pentola, famiglia, scritta) senza sfondo
diff = ImageChops.difference(full, Image.new('RGB', (N, N), CREAM)).convert('L')
alpha = diff.point(lambda v: 0 if v < 14 else (255 if v > 40 else int((v - 14) * 9.8)))
inner = Image.new('L', (N, N), 0)
ImageDraw.Draw(inner).rounded_rectangle([60, 60, N - 61, N - 61], radius=int(N * 0.17), fill=255)
alpha = ImageChops.multiply(alpha, inner)
full.paste(Image.new('RGB', (N, N), CREAM), (0, 0), ImageChops.invert(inner))
content = full.convert('RGBA'); content.putalpha(alpha)
bbox = alpha.getbbox(); print('bbox', bbox)

def rounded(size):
    out = full.resize((size, size), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.22), fill=255)
    out.putalpha(m.resize((size, size), Image.LANCZOS)); return out

def centered(size, frac):
    c = content.crop(bbox); w, h = c.size; s = size * frac / max(w, h)
    c = c.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0)); out.alpha_composite(c, ((size - c.size[0]) // 2, (size - c.size[1]) // 2)); return out

rounded(1024).save(root / 'assets' / 'icon.png')
rounded(512).save(root / 'docs' / 'icon.png')
centered(1024, 0.92).save(root / 'assets' / 'logo.png')
# Silhouette per le notifiche: pentola, famiglia e vapore (senza scritta)
y_text = int(N * 0.66)
sil = alpha.copy(); ImageDraw.Draw(sil).rectangle([0, y_text, N, N], fill=0)
sb = sil.getbbox()
icons = root / 'tool' / 'icons'
for k, f in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    mp, dr = icons / f'mipmap-{k}', icons / f'drawable-{k}'
    rounded(int(48 * f)).save(mp / 'ic_launcher.png')
    a = int(108 * f)
    Image.new('RGB', (a, a), CREAM).save(mp / 'ic_launcher_background.png')
    fg = full.resize((a, a), Image.LANCZOS).convert('RGBA')  # sfondo crema = background, il contenuto resta nella zona sicura
    fg = centered(a, 0.72); fg.save(mp / 'ic_launcher_foreground.png')
    n = int(24 * f); s = sil.crop(sb); w, h = s.size; sc = n * 0.92 / max(w, h)
    s = s.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)
    ni = Image.new('RGBA', (n, n), (255, 255, 255, 0)); white = Image.new('RGBA', s.size, (255, 255, 255, 255)); white.putalpha(s)
    ni.alpha_composite(white, ((n - s.size[0]) // 2, (n - s.size[1]) // 2)); ni.save(dr / 'ic_stat_notify.png')
    sl = int(140 * f); centered(sl, 0.95).save(dr / 'splash_logo.png')
print('ok')
