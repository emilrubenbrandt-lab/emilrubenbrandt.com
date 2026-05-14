#!/bin/bash
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
    echo "Fehler: Google Drive Ordner nicht gefunden"
    exit 1
fi

mkdir -p "$REPO_IMAGES"
cd "$REPO_PATH"

NEW_IMAGES=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    if [ ! -f "$REPO_IMAGES/$filename" ]; then
        NEW_IMAGES+=("$filename")
    fi
done < <(find "$DRIVE_IMAGES" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

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
    exit 0
fi

if [ ${#NEW_IMAGES[@]} -gt 0 ]; then
    echo "Neue Bilder: ${#NEW_IMAGES[@]}"
    for img in "${NEW_IMAGES[@]}"; do
        cp "$DRIVE_IMAGES/$img" "$REPO_IMAGES/$img"
        echo "  + $img"
    done
fi

if [ ${#REMOVED_IMAGES[@]} -gt 0 ]; then
    echo "Zu entfernen: ${#REMOVED_IMAGES[@]}"
    for img in "${REMOVED_IMAGES[@]}"; do
        rm "$REPO_IMAGES/$img"
        echo "  - $img"
    done
fi

python3 - "$INDEX_HTML" << 'EOF'
import sys, re, os

html = sys.argv[1]
with open(html) as f:
    content = f.read()

pattern = r'        <figure>\s*<img[^>]*>\s*</figure>\s*'
content = re.sub(pattern, '', content)

for img in sorted(os.listdir(os.path.expanduser("~/Portfolio-Repo/images"))):
    if img.lower().endswith(('.jpg', '.jpeg', '.png')):
        fig = f'        <figure>\n            <img src="images/{img}" alt="">\n        </figure>\n'
        if fig not in content:
            content = content.replace("    </main>", f"{fig}    </main>")

with open(html, 'w') as f:
    f.write(content)
print("index.html aktualisiert")
EOF

git add -A
if ! git diff --cached --quiet; then
    git commit -m "Update: Portfolio sync"
    git pull --rebase origin main 2>&1 || true
    git push "$REMOTE" "$BRANCH"
fi

echo ""
echo "✓ Sync abgeschlossen!"
echo ""
