"""Prepara le immagini per le schede degli store in store/:
- android/<lingua>/: schermate del telefono (1080×1920) per Google Play
- ios/<lingua>/: schermate per l'App Store (iPhone 6,7", 1290×2796, senza trasparenza)
- icon-512.png e feature-graphic.png (1024×500) per Google Play.

Prima rigenera le schermate:
  flutter test tool/screenshots/screenshots_test.dart --update-goldens
  SHOTS=ios flutter test tool/screenshots/screenshots_test.dart --update-goldens
poi: python3 tool/make_store_assets.py"""
import pathlib
import shutil

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "tool" / "screenshots"
OUT = ROOT / "store"

# In ordine di presentazione: Preferiti, ricetta, passaggi, Le mie, gruppi, suggerimento, modifica, tema scuro.
PICK = ["19_favorites", "02_recipe", "03_steps", "01_mine", "05_groups", "14_suggest", "07_edit", "10_dark"]

shutil.rmtree(OUT, ignore_errors=True)
for store, src in (("android", "out"), ("ios", "out_ios")):
    for lang in ("it", "en"):
        d = OUT / store / lang
        d.mkdir(parents=True)
        for i, name in enumerate(PICK, 1):
            im = Image.open(SHOTS / src / lang / f"{name}.png").convert("RGB")
            im.save(d / f"{i:02d}_{name[3:]}.png", optimize=True)

icon = Image.open(ROOT / "assets" / "icon.png").convert("RGBA").resize((512, 512), Image.LANCZOS)
icon.save(OUT / "icon-512.png")

# Copertina Google Play: tovaglia/terracotta, logo e motto a mano.
W, H = 1024, 500
g = Image.new("RGB", (W, H), (180, 83, 42))
d = ImageDraw.Draw(g)
for x in range(0, W, 40):  # quadretti della tovaglia
    d.rectangle([x, 0, x + 19, H], fill=(190, 98, 58))
for y in range(0, H, 40):
    d.rectangle([0, y, W, y + 19], fill=(190, 98, 58))
d.rounded_rectangle([40, 40, W - 40, H - 40], radius=28, fill=(254, 246, 232))
logo = Image.open(ROOT / "assets" / "logo.png").convert("RGBA").resize((340, 340), Image.LANCZOS)
g.paste(logo, (70, 80), logo)
hand = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "PatrickHand-Regular.ttf"), 92)
body = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "PatrickHand-Regular.ttf"), 44)
d.text((440, 140), "FamilyRecipes", font=hand, fill=(180, 83, 42))
d.text((444, 260), "Il ricettario di famiglia,", font=body, fill=(59, 42, 30))
d.text((444, 312), "scritto e condiviso insieme", font=body, fill=(59, 42, 30))
g.save(OUT / "feature-graphic.png")
print("Immagini pronte in", OUT)
