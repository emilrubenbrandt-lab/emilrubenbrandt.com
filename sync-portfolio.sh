#!/bin/bash
#
# Portfolio Sync Script
# Synct Bilder von Google Drive -> GitHub Portfolio
# Fuegt neue Bilder hinzu, entfernt geloeschte Bilder (inkl. Titel)
#

DRIVE_IMAGES="$HOME/Library/CloudStorage/GoogleDrive-emilrubenbrandt@gmail.com/Meine Ablage/emilrubenbrandt.com/images"
REPO_PATH="$HOME/Portfolio-Repo"
REPO_IMAGES="$REPO_PATH/images"
INDEX_HTML="$REPO_PATH/index.html"
REMOTE="origin"
BRANCH="main"

echo ""
echo "Portfolio Sync gestartet..."
echo ""

# Error handling
set -e
trap 'echo "Fehler bei der Synchronisierung!"; exit 1' ERR

if [ ! -d "$DRIVE_IMAGES" ]; then
    echo "Fehler: Google Drive Ordner nicht gefunden:"
    echo "   $DRIVE_IMAGES"
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "Fehler: Repository-Ordner nicht gefunden:"
    echo "   $REPO_PATH"
    exit 1
fi

# Create images directory if it doesn't exist
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

# Neue Bilder kopieren (mit Fehlerbehandlung)
for img in "${NEW_IMAGES[@]}"; do
    if [ -f "$DRIVE_IMAGES/$img" ]; then
        cp "$DRIVE_IMAGES/$img" "$REPO_IMAGES/$img" || { echo "Fehler beim Kopieren von $img"; exit 1; }
        echo "Kopiert: $img"
    else
        echo "Warnung: $img nicht mehr in Drive vorhanden, übersprungen"
    fi
done

# Geloeschte Bilder entfernen
for img in "${REMOVED_IMAGES[@]}"; do
    rm "$REPO_IMAGES/$img"
    echo "Geloescht: $img"
done

# Schreibe Listen in Temp-Dateien fuer Python
REMOVED_FILE=$(mktemp)
NEW_FILE=$(mktemp)
for img in "${REMOVED_IMAGES[@]}"; do echo "$img" >> "$REMOVED_FILE"; done
for img in "${NEW_IMAGES[@]}"; do echo "$img" >> "$NEW_FILE"; done

# index.html updaten via Python (block-basiert, entfernt ganzen <figure> Block inkl. Titel)
python3 << PYEOF
import re
import os

html_path = "$INDEX_HTML"
removed_path = "$REMOVED_FILE"
new_path = "$NEW_FILE"

with open(removed_path) as f:
    removed = [l.strip() for l in f if l.strip()]

with open(new_path) as f:
    new_imgs = [l.strip() for l in f if l.strip()]

with open(html_path, encoding="utf-8") as f:
    content = f.read()

# Entferne ganzen <figure>...</figure> Block fuer jedes geloeschte Bild
for img in removed:
    pattern = r'[ \t]*<figure>.*?images/' + re.escape(img) + r'.*?</figure>[ \t]*\n?'
    content = re.sub(pattern, '', content, flags=re.DOTALL)

# Fuege neue <figure> Bloecke vor </main> ein
new_figures = ""
for img in new_imgs:
    new_figures += f'        <figure>\n            <img src="images/{img}" alt="">\n        </figure>\n\n'

content = content.replace("    </main>", new_figures + "    </main>")

with open(html_path, "w", encoding="utf-8") as f:
    f.write(content)

print("index.html aktualisiert")
PYEOF

rm "$REMOVED_FILE" "$NEW_FILE"

# Git commit & push mit besserer Fehlerbehandlung
if [ ${#NEW_IMAGES[@]} -gt 0 ]; then
    git add "${NEW_IMAGES[@]/#/$REPO_IMAGES/}"
fi

if [ ${#REMOVED_IMAGES[@]} -gt 0 ]; then
    git add "${REMOVED_IMAGES[@]/#/$REPO_IMAGES/}" || true
fi

git add index.html

# Nur committen wenn es Änderungen gibt
if ! git diff --cached --quiet; then
    PARTS=()
    if [ ${#NEW_IMAGES[@]} -gt 0 ]; then PARTS+=("+ ${#NEW_IMAGES[@]} Bilder hinzugefügt"); fi
    if [ ${#REMOVED_IMAGES[@]} -gt 0 ]; then PARTS+=("- ${#REMOVED_IMAGES[@]} Bilder entfernt"); fi
    COMMIT_MSG=$(IFS='; '; echo "${PARTS[*]}")
    
    git commit -m "$COMMIT_MSG" || { echo "Nichts zu committen"; exit 0; }
    
    # Pull rebase vor push
    if ! git pull --rebase origin main 2>&1; then
        echo "Fehler beim Pull-Rebase. Bitte manuell prüfen."
        exit 1
    fi
    
    # Push mit Fehlerbehandlung
    if ! git push "$REMOTE" "$BRANCH"; then
        echo "Fehler beim Push. Bitte manuell prüfen."
        exit 1
    fi
else
    echo "Keine Änderungen zu committen."
fi

echo ""
echo "✓ Sync abgeschlossen! Webseite aktualisiert in ~1-2 Minuten."
echo ""
