#!/bin/bash
# Veröffentlicht eine neue Version auf GitHub. Installierte Quarry-Apps bieten sie beim nächsten Start an.
#   ./release.sh 0.3.0 "Was ist neu"
set -euo pipefail
cd "$(dirname "$0")"
NEW=${1:?Version fehlt, z. B. ./release.sh 0.3.0 "Was ist neu"}
NOTES=${2:-"Neue Version"}
REPO=$(cat .update-repo)

echo "$NEW" > VERSION
./build-app.sh --no-install
rm -f build/Quarry.zip
ditto -c -k --keepParent build/Quarry.app build/Quarry.zip
swift scripts/sign-update.swift sign build/Quarry.zip > build/Quarry.zip.sig
git add -A && git commit -qm "Quarry $NEW" && git push -q
gh release create "v$NEW" build/Quarry.zip build/Quarry.zip.sig --repo "$REPO" --title "Quarry $NEW" --notes "$NOTES"
echo "Veröffentlicht: https://github.com/$REPO/releases/tag/v$NEW"
