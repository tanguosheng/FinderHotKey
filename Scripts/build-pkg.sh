#!/bin/bash
# Builds dist/FinderHotKey-<version>.pkg from dist/FinderHotKey.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FinderHotKey.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Info.plist")
OUTPUT="$ROOT/dist/FinderHotKey-$VERSION.pkg"

if [ ! -x "$APP/Contents/MacOS/FinderHotKey" ]; then
    "$ROOT/Scripts/build-app.sh"
fi

WORK=$(mktemp -d /tmp/fhk-pkg.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/root"
COMPONENT="$WORK/component.pkg"
EXPANDED="$WORK/expanded"

mkdir -p "$STAGE/Applications"
ditto "$APP" "$STAGE/Applications/FinderHotKey.app"
xattr -cr "$STAGE/Applications/FinderHotKey.app"
find "$STAGE" -name '._*' -delete

pkgbuild \
    --root "$STAGE" \
    --identifier local.tgs.finderhotkey.pkg \
    --version "$VERSION" \
    --scripts "$ROOT/Packaging/scripts" \
    --install-location / \
    --ownership recommended \
    "$COMPONENT"

# Bundle relocation would let Installer move the app to a stale copy with the
# same bundle identifier. Strip it so the payload always lands in /Applications.
pkgutil --expand "$COMPONENT" "$EXPANDED"
/usr/bin/python3 "$ROOT/Scripts/strip-relocate.py" "$EXPANDED/PackageInfo"
pkgutil --flatten "$EXPANDED" "$OUTPUT"

echo "Built: $OUTPUT"
