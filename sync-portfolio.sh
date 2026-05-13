#!/bin/bash
#
# Portfolio Sync Script
# Synct Bilder von Google Drive → GitHub Portfolio
# 
# Usage: ./sync-portfolio.sh
#

set -e  # Stop bei Fehler

# ============ KONFIGURATION ============

# Lokaler Google Drive Pfad (passe an falls anders)
# Neue Drive App:
DRIVE_IMAGES="$HOME/Library/CloudStorage/GoogleDrive-emilrubenbrandt@gmail.com/Meine Ablage/emilrubenbrandt.com/images"
# Alte Drive App (falls du die nutzt):
# DRIVE_IMAGES="$HOME/Google Drive/emilrubenbrandt.com/images"

# Git Repo Pfad (passe an wo dein Repo liegt)
REPO_PATH="$HOME/Portfolio-Repo"
REPO_IMAGES="$REPO_PATH/images"
INDEX_HTML="$REPO_PATH/index.html"

# Git Remote
REMOTE="origin"
BRANCH="main"

# ============ SCRIPT START ============

echo "🚀 Portfolio Sync gestartet..."
echo ""

# Prüfe ob Drive-Ordner existiert
if [ ! -d "$DRIVE_IMAGES" ]; then
    echo "❌ Fehler: Google Drive Ordner nicht gefunden:"
    echo "   $DRIVE_IMAGES"
    echo ""
    echo "💡 Passe DRIVE_IMAGES im Script an!"
    exit 1
fi

# Prüfe ob Repo existiert
if [ ! -d "$REPO_PATH" ]; then
    echo "❌ Fehler: Git Repo nicht gefunden:"
    echo "   $REPO_PATH"
    echo ""
    echo "💡 Passe REPO_PATH im Script an!"
    exit 1
fi

# Wechsle ins Repo
cd "$REPO_PATH"

# Zähle Bilder in Drive
DRIVE_COUNT=$(find "$DRIVE_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l | tr -d ' ')
echo "📁 Google Drive: $DRIVE_COUNT Bilder gefunden"

# Zähle Bilder im Repo
REPO_COUNT=$(find "$REPO_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null | wc -l | tr -d ' ')
echo "📦 Git Repo: $REPO_COUNT Bilder vorhanden"
echo ""

# Finde neue Bilder
NEW_IMAGES=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_IMAGES/$filename" ]; then
        NEW_IMAGES+=("$filename")
    fi
done < <(find "$DRIVE_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

# Wenn keine neuen Bilder
if [ ${#NEW_IMAGES[@]} -eq 0 ]; then
    echo "✅ Keine neuen Bilder zum Synchronisieren"
    exit 0
fi

# Zeige neue Bilder
echo "🆕 ${#NEW_IMAGES[@]} neue(s) Bild(er) gefunden:"
for img in "${NEW_IMAGES[@]}"; do
    echo "   • $img"
done
echo ""

# Kopiere neue Bilder
echo "📋 Kopiere Bilder ins Repo..."
for img in "${NEW_IMAGES[@]}"; do
    cp "$DRIVE_IMAGES/$img" "$REPO_IMAGES/$img"
    echo "   ✓ $img"
done
echo ""

# Update index.html
echo "📝 Update index.html..."
# Finde Position vor </main>
TEMP_FILE=$(mktemp)
MAIN_END_FOUND=false

while IFS= read -r line; do
    if [[ "$line" =~ \</main\> ]]; then
        # Füge neue figure Blöcke vor </main> ein
        for img in "${NEW_IMAGES[@]}"; do
            echo "        <figure>" >> "$TEMP_FILE"
            echo "            <img src=\"images/$img\" alt=\"\">" >> "$TEMP_FILE"
            echo "        </figure>" >> "$TEMP_FILE"
            echo "" >> "$TEMP_FILE"
        done
        MAIN_END_FOUND=true
    fi
    echo "$line" >> "$TEMP_FILE"
done < "$INDEX_HTML"

if [ "$MAIN_END_FOUND" = false ]; then
    echo "❌ Fehler: </main> Tag nicht gefunden in index.html"
    rm "$TEMP_FILE"
    exit 1
fi

# Ersetze Original
mv "$TEMP_FILE" "$INDEX_HTML"
echo "   ✓ ${#NEW_IMAGES[@]} <figure> Block(s) hinzugefügt"
echo ""

# Git commit & push
echo "🔄 Git Commit & Push..."
git add images/ index.html

# Erstelle Commit-Message
if [ ${#NEW_IMAGES[@]} -eq 1 ]; then
    COMMIT_MSG="Neues Bild: ${NEW_IMAGES[0]}"
else
    COMMIT_MSG="Neue Bilder: ${NEW_IMAGES[*]}"
fi

git commit -m "$COMMIT_MSG"
git push "$REMOTE" "$BRANCH"

echo ""
echo "✨ Sync abgeschlossen!"
echo "🌐 Webseite aktualisiert in ~1-2 Minuten"
echo ""
