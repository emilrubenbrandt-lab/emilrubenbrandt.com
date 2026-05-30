#!/bin/bash
#
# Portfolio Sync
# Bilder direkt in images/ ablegen, dann dieses Script ausführen.
#
# images/order.json  — Array mit Dateinamen in gewünschter Reihenfolge
# images/titles.json — Objekt { "datei.jpg": "Titel" }
#

set -e

REPO_PATH="$(cd "$(dirname "$0")" && pwd)"
REPO_IMAGES="$REPO_PATH/images"
INDEX_HTML="$REPO_PATH/index.html"
WEBP_QUALITY=90

echo ""
echo "Portfolio Sync gestartet..."
echo ""

if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    echo "Fehler: Pillow nicht installiert."
    echo "   python3 -m pip install --user Pillow"
    exit 1
fi

INDEX_HTML="$INDEX_HTML" REPO_IMAGES="$REPO_IMAGES" WEBP_QUALITY="$WEBP_QUALITY" python3 << 'PYEOF'
import os, re, json, html as htmllib
from PIL import Image

repo_images = os.environ['REPO_IMAGES']
html_path = os.environ['INDEX_HTML']
quality = int(os.environ['WEBP_QUALITY'])
IMG_EXTS = ('.jpg', '.jpeg', '.png')

def load_json(path, fallback):
    if not os.path.exists(path):
        return fallback
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f'WARNUNG: {os.path.basename(path)} ungültiges JSON ({e}). Fallback verwendet.')
        return fallback

present = sorted(f for f in os.listdir(repo_images) if f.lower().endswith(IMG_EXTS))
present_set = set(present)

# WebP erzeugen für fehlende Varianten
for img in present:
    base, _ = os.path.splitext(img)
    dst = os.path.join(repo_images, base + '.webp')
    if not os.path.exists(dst):
        with Image.open(os.path.join(repo_images, img)) as im:
            im.save(dst, 'WEBP', quality=quality)
        print(f'WebP erzeugt: {base}.webp')

# Verwaiste WebPs entfernen
for f in list(os.listdir(repo_images)):
    if f.lower().endswith('.webp'):
        base = os.path.splitext(f)[0]
        if not any(base + ext in present_set for ext in IMG_EXTS):
            os.remove(os.path.join(repo_images, f))
            print(f'WebP entfernt: {f}')

order = load_json(os.path.join(repo_images, 'order.json'), [])
titles = load_json(os.path.join(repo_images, 'titles.json'), {})

ordered = [f for f in order if f in present_set]
ordered += [f for f in present if f not in set(ordered)]

def figure_block(img):
    base, _ = os.path.splitext(img)
    title = (titles.get(img) or '').strip()
    lines = [
        '        <figure>',
        '            <picture>',
        f'                <source type="image/webp" srcset="images/{base}.webp">',
        f'                <img src="images/{img}" loading="lazy" alt="">',
        '            </picture>',
    ]
    if title:
        lines.append(f'            <figcaption>{htmllib.escape(title)}</figcaption>')
    lines.append('        </figure>')
    return '\n'.join(lines)

figures = '\n\n'.join(figure_block(img) for img in ordered)
new_main = '    <main>\n' + figures + '\n    </main>' if figures else '    <main>\n    </main>'

with open(html_path, encoding='utf-8') as f:
    content = f.read()

new_content, n = re.subn(
    r'    <main>.*?</main>',
    lambda m: new_main,
    content, count=1, flags=re.DOTALL
)

if n == 0:
    print('FEHLER: <main>-Block nicht gefunden.')
else:
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f'index.html aktualisiert ({len(ordered)} Bilder)')
PYEOF

cd "$REPO_PATH"
git add images/ index.html

if git diff --cached --quiet; then
    echo ""
    echo "Keine Änderungen."
    echo ""
    exit 0
fi

git commit -m "update portfolio"
git pull --rebase origin main 2>/dev/null || true
git push origin main

echo ""
echo "Fertig. Webseite aktualisiert in ~1-2 Minuten."
echo ""
