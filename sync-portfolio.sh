#!/bin/bash
#
# Portfolio Sync Script
# Synct Bilder von Google Drive -> GitHub Portfolio
# Fuegt neue Bilder hinzu, entfernt geloeschte Bilder (inkl. Titel)
#

DRIVE_IMAGES="$HOME/Google Drive/Meine Ablage/emilrubenbrandt.com/images"
REPO_PATH="$HOME/Portfolio-Repo"
REPO_IMAGES="$REPO_PATH/images"
INDEX_HTML="$REPO_PATH/index.html"
REMOTE="origin"
BRANCH="main"

echo ""
echo "Portfolio Sync gestartet..."
echo ""

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

mkdir -p "$REPO_IMAGES"

cd "$REPO_PATH"

# Neue Bilder finden
NEW_IMAGES=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_IMAGES/$filename" ]; then
        NEW_IMAGES+=("$filename")
    fi
done < <(find "$DRIVE_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

# Geloeschte Bilder finden
REMOVED_IMAGES=()
if [ -d "$REPO_IMAGES" ]; then
    while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        if [ ! -f "$DRIVE_IMAGES/$filename" ]; then
            REMOVED_IMAGES+=("$filename")
        fi
    done < <(find "$REPO_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)
fi

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

# Neue Bilder kopieren
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

# index.html updaten via Python - REMOVE ALL FIGURES, THEN ADD ONLY UNIQUE IMAGES
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

# Entferne ALLE <figure> Bloecke, nicht nur einzelne
pattern = r'[ \t]*<figure>.*?</figure>[ \t]*\n?'
content = re.sub(pattern, '', content, flags=re.DOTALL)

# Fuege neue <figure> Bloecke VOR </main> ein (nur unique Images)
new_figures = ""
seen = set()
for img in new_imgs:
    if img not in seen:  # Prevent duplicates
        new_figures += f'        <figure>\n            <img src="images/{img}" alt="">\n        </figure>\n'
        seen.add(img)

# Ersetze </main> mit neuen Bildern + </main>
if new_figures:
    content = content.replace("    </main>", new_figures + "    </main>")

with open(html_path, "w", encoding="utf-8") as f:
    f.write(content)

print("index.html aktualisiert (Duplikate entfernt)")
PYEOF

rm "$REMOVED_FILE" "$NEW_FILE"

# Git commit & push
git add -A

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
    
    # Push
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
