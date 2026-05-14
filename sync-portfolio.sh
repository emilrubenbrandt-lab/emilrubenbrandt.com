#!/bin/bash
#
# Portfolio Sync Script
# Synct Bilder von Google Drive -> GitHub Portfolio
# Fuegt neue Bilder hinzu, entfernt geloeschte Bilder
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

if [ ! -d "$DRIVE_IMAGES" ]; then
    echo "Fehler: Google Drive Ordner nicht gefunden:"
    echo "   $DRIVE_IMAGES"
    exit 1
fi

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

# Neue Bilder kopieren
for img in "${NEW_IMAGES[@]}"; do
    cp "$DRIVE_IMAGES/$img" "$REPO_IMAGES/$img"
    echo "Kopiert: $img"
done

# Geloeschte Bilder entfernen
for img in "${REMOVED_IMAGES[@]}"; do
    rm "$REPO_IMAGES/$img"
    echo "Geloescht: $img"
done

# index.html updaten
TEMP_FILE=$(mktemp)
SKIP_BLOCK=false

while IFS= read -r line; do

    # Pruefe ob Zeile ein geloeschtes Bild referenziert
    for img in "${REMOVED_IMAGES[@]}"; do
        if [[ "$line" == *"images/$img"* ]]; then
            SKIP_BLOCK=true
        fi
    done

    # Wenn im Skip-Block: ueberspringe bis </figure>
    if [ "$SKIP_BLOCK" = true ]; then
        if [[ "$line" == *"</figure>"* ]]; then
            SKIP_BLOCK=false
        fi
        continue
    fi

    # Neue Bilder vor </main> einfuegen
    if [[ "$line" =~ \</main\> ]]; then
        for img in "${NEW_IMAGES[@]}"; do
            echo "        <figure>" >> "$TEMP_FILE"
            echo "            <img src=\"images/$img\" alt=\"\">" >> "$TEMP_FILE"
            echo "        </figure>" >> "$TEMP_FILE"
            echo "" >> "$TEMP_FILE"
        done
    fi

    echo "$line" >> "$TEMP_FILE"

done < "$INDEX_HTML"

mv "$TEMP_FILE" "$INDEX_HTML"
echo ""
echo "index.html aktualisiert"

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
