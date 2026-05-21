#!/bin/bash
#
# Portfolio Sync Script
# Synct Bilder von Google Drive -> GitHub Portfolio
# Fuegt neue Bilder hinzu, entfernt geloeschte Bilder (inkl. Titel)
# Erzeugt automatisch WebP-Varianten neben jedem JPG fuer schnellere Ladezeiten
# WebP-Konvertierung via Python+Pillow (keine externe Binary noetig)
#

DRIVE_IMAGES="$HOME/Library/CloudStorage/GoogleDrive-emilrubenbrandt@gmail.com/Meine Ablage/emilrubenbrandt.com/images"
REPO_PATH="$HOME/Portfolio-Repo"
REPO_IMAGES="$REPO_PATH/images"
INDEX_HTML="$REPO_PATH/index.html"
REMOTE="origin"
BRANCH="main"
WEBP_QUALITY=90

echo ""
echo "Portfolio Sync gestartet..."
echo ""

if [ ! -d "$DRIVE_IMAGES" ]; then
    echo "Fehler: Google Drive Ordner nicht gefunden:"
    echo "   $DRIVE_IMAGES"
    exit 1
fi

if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    echo "Fehler: Pillow (Python-Bibliothek fuer WebP) ist nicht installiert."
    echo "   Installieren mit: python3 -m pip install --user Pillow"
    exit 1
fi

mkdir -p "$REPO_IMAGES"
cd "$REPO_PATH"

# Neue Bilder finden (in Drive, noch nicht im Repo)
NEW_IMAGES=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_IMAGES/$filename" ]; then
        NEW_IMAGES+=("$filename")
    fi
done < <(find "$DRIVE_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

# Geloeschte Bilder finden (im Repo, nicht mehr in Drive)
REMOVED_IMAGES=()
if [ -d "$REPO_IMAGES" ]; then
    while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        if [ ! -f "$DRIVE_IMAGES/$filename" ]; then
            REMOVED_IMAGES+=("$filename")
        fi
    done < <(find "$REPO_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)
fi

# Nichts zu tun
if [ ${#NEW_IMAGES[@]} -eq 0 ] && [ ${#REMOVED_IMAGES[@]} -eq 0 ]; then
    echo "Alles aktuell, nichts zu synchronisieren."
    echo ""
    exit 0
fi

if [ ${#NEW_IMAGES[@]} -gt 0 ]; then
    echo "Neue Bilder (${#NEW_IMAGES[@]}):"
    for img in "${NEW_IMAGES[@]}"; do echo "   + $img"; done
    echo ""
fi

if [ ${#REMOVED_IMAGES[@]} -gt 0 ]; then
    echo "Zu entfernen (${#REMOVED_IMAGES[@]}):"
    for img in "${REMOVED_IMAGES[@]}"; do echo "   - $img"; done
    echo ""
fi

# Neue Bilder ins Repo kopieren (WebP-Konvertierung passiert spaeter in Python)
for img in "${NEW_IMAGES[@]}"; do
    cp "$DRIVE_IMAGES/$img" "$REPO_IMAGES/$img"
    echo "Kopiert: $img"
done

# Geloeschte JPGs aus Repo entfernen (WebP-Loeschung passiert spaeter in Python)
for img in "${REMOVED_IMAGES[@]}"; do
    rm -f "$REPO_IMAGES/$img"
    echo "Geloescht: $img"
done

# Schreibe Listen in Temp-Dateien fuer Python
REMOVED_FILE=$(mktemp)
NEW_FILE=$(mktemp)
for img in "${REMOVED_IMAGES[@]}"; do echo "$img" >> "$REMOVED_FILE"; done
for img in "${NEW_IMAGES[@]}"; do echo "$img" >> "$NEW_FILE"; done

# Python: WebP-Varianten erzeugen/loeschen + index.html updaten
INDEX_HTML="$INDEX_HTML" REPO_IMAGES="$REPO_IMAGES" REMOVED_FILE="$REMOVED_FILE" NEW_FILE="$NEW_FILE" WEBP_QUALITY=$WEBP_QUALITY python3 << 'PYEOF'
import os
import re
from PIL import Image

html_path = os.environ['INDEX_HTML']
repo_images = os.environ['REPO_IMAGES']
removed_path = os.environ['REMOVED_FILE']
new_path = os.environ['NEW_FILE']
quality = int(os.environ['WEBP_QUALITY'])

with open(removed_path) as f:
    removed = [l.strip() for l in f if l.strip()]
with open(new_path) as f:
    new_imgs = [l.strip() for l in f if l.strip()]

# WebP-Variante fuer jedes neue Bild erzeugen (volle Originalaufloesung beibehalten)
for img in new_imgs:
    src = os.path.join(repo_images, img)
    base, _ = os.path.splitext(img)
    dst = os.path.join(repo_images, base + '.webp')
    with Image.open(src) as im:
        im.save(dst, 'WEBP', quality=quality)
    print(f'WebP: {base}.webp')

# WebP-Variante fuer jedes geloeschte Bild entfernen (falls vorhanden)
for img in removed:
    base, _ = os.path.splitext(img)
    webp_path = os.path.join(repo_images, base + '.webp')
    if os.path.exists(webp_path):
        os.remove(webp_path)
        print(f'WebP geloescht: {base}.webp')

# HTML aktualisieren
with open(html_path, encoding='utf-8') as f:
    content = f.read()

# Entferne ganzen <figure>...</figure> Block fuer jedes geloeschte Bild
for img in removed:
    pattern = r'[ \t]*<figure>.*?images/' + re.escape(img) + r'.*?</figure>[ \t]*\n?'
    content = re.sub(pattern, '', content, flags=re.DOTALL)

# Fuege neue <figure>-Bloecke vor </main> ein
new_figures = ''
for img in new_imgs:
    base, _ = os.path.splitext(img)
    new_figures += (
        '        <figure>\n'
        '            <picture>\n'
        f'                <source type="image/webp" srcset="images/{base}.webp">\n'
        f'                <img src="images/{img}" loading="lazy" alt="">\n'
        '            </picture>\n'
        '        </figure>\n\n'
    )

content = content.replace('    </main>', new_figures + '    </main>')

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('index.html aktualisiert')
PYEOF

# Temp-Dateien aufraeumen
rm "$REMOVED_FILE" "$NEW_FILE"

# Git commit & push
git add images/ index.html

PARTS=()
if [ ${#NEW_IMAGES[@]} -gt 0 ]; then PARTS+=("+ ${NEW_IMAGES[*]}"); fi
if [ ${#REMOVED_IMAGES[@]} -gt 0 ]; then PARTS+=("- ${REMOVED_IMAGES[*]}"); fi
COMMIT_MSG=$(IFS='; '; echo "${PARTS[*]}")

git commit -m "$COMMIT_MSG"
git pull --rebase origin main 2>/dev/null || true
git push "$REMOTE" "$BRANCH"

echo ""
echo "Sync abgeschlossen! Webseite aktualisiert in ~1-2 Minuten."
echo ""
