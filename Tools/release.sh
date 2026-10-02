#!/bin/bash
#
# BiteFM macOS Release: Archive -> Developer-ID-Export -> Notarisierung -> DMG -> /Applications -> GitHub-Release
#
#   Tools/release.sh [patch|minor|major] [Optionen]
#
# Optionen:
#   --build-only      Nur bauen/notarisieren/DMG/installieren. Keine Versionserhöhung, kein Commit, kein Tag, kein GitHub-Release.
#   --skip-notarize   Notarisierung überspringen (impliziert --build-only; nur zum Testen der Build-Kette).
#   --no-install      Nicht nach /Applications kopieren.
#   -y, --yes         Keine Rückfrage vor Commit/Tag/Push/Release.
#
# Einmalige Voraussetzung (Notarisierung):
#   xcrun notarytool store-credentials "BiteFM-notary" --apple-id <AppleID> --team-id C24WCN78VM
#   (fragt nach einem App-spezifischen Passwort von appleid.apple.com)

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="C24WCN78VM"
NOTARY_PROFILE="${NOTARY_PROFILE:-BiteFM-notary}"
SCHEME="BiteFMMac (App)"
APP_NAME="BiteFM"
BUILD_DIR="build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

BUMP="patch"
BUILD_ONLY=0
SKIP_NOTARIZE=0
INSTALL=1
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        patch|minor|major) BUMP="$arg" ;;
        --build-only) BUILD_ONLY=1 ;;
        --skip-notarize) SKIP_NOTARIZE=1; BUILD_ONLY=1 ;;
        --no-install) INSTALL=0 ;;
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "Unbekanntes Argument: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { echo "Fehler: $*" >&2; exit 1; }

# ---------------------------------------------------------------- Preflight
step "Preflight"
command -v xcodegen >/dev/null || die "xcodegen fehlt (brew install xcodegen)"

SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | awk '{print $2}') || true
[ -n "$SIGN_IDENTITY" ] || die "Kein 'Developer ID Application'-Zertifikat für Team $TEAM_ID im Schlüsselbund"

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "notarytool-Profil '$NOTARY_PROFILE' fehlt. Einmalig einrichten:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <AppleID> --team-id $TEAM_ID"
fi

REMOTE=$(git remote | head -1)
PREV_TAG=""
if [ "$BUILD_ONLY" -eq 0 ]; then
    command -v gh >/dev/null || die "gh fehlt (brew install gh)"
    gh auth status >/dev/null 2>&1 || die "gh ist nicht angemeldet (gh auth login)"
    [ -n "$REMOTE" ] || die "Kein Git-Remote konfiguriert"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "Release nur vom Branch 'main'"
    [ -z "$(git status --porcelain | grep -v '\.DS_Store' || true)" ] \
        || die "Uncommittete Änderungen vorhanden – erst committen."
    PREV_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
    if [ -n "$PREV_TAG" ] && [ -z "$(git log "$PREV_TAG..HEAD" --oneline)" ]; then
        die "Keine neuen Commits seit $PREV_TAG – nichts zu releasen."
    fi
fi

# ---------------------------------------------------------------- Release Notes
NOTES_FILE="$BUILD_DIR/release-notes.md"
mkdir -p "$BUILD_DIR"
if [ "$BUILD_ONLY" -eq 0 ]; then
    step "Release Notes seit ${PREV_TAG:-Anfang}"
    RANGE=${PREV_TAG:+$PREV_TAG..HEAD}
    SUBJECTS=$(git log $RANGE --no-merges --pretty='%s')

    # Typ-Präfix ("feat(scope): ") entfernen, Scope bleibt als Kontext in Klammern
    clean() { sed -E 's/^(feat|fix|perf)\(([^)]*)\): */\2: /; s/^(feat|fix|perf): *//'; }
    {
        for spec in "Neu|^feat(\(|:)" "Fixes|^fix(\(|:)" "Performance|^perf(\(|:)"; do
            title=${spec%%|*}; re=${spec#*|}
            items=$(echo "$SUBJECTS" | grep -E "$re" | clean | sed 's/^/- /' || true)
            [ -n "$items" ] && printf '### %s\n%s\n\n' "$title" "$items"
        done
        true
    } > "$NOTES_FILE"
    [ -s "$NOTES_FILE" ] || echo "Änderungen und Verbesserungen." > "$NOTES_FILE"
    cat "$NOTES_FILE"
fi

# ---------------------------------------------------------------- Version
if [ "$BUILD_ONLY" -eq 0 ]; then
    step "Version erhöhen ($BUMP)"
    # Bei Fehlschlag Versionsänderung zurücknehmen (noch nichts committed)
    trap 'echo "Abgebrochen – setze Versionsänderung zurück"; git checkout -- project.yml BiteFM.xcodeproj' ERR
    # "pre-commit": Build-Nummer = Commit-Anzahl + 1, identisch zum späteren Hook beim Release-Commit
    swift Tools/bump-version.swift "$BUMP" pre-commit
fi
VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/')
echo "BiteFM $VERSION (Build $BUILD)"
if [ "$BUILD_ONLY" -eq 1 ]; then xcodegen generate >/dev/null; fi

# ---------------------------------------------------------------- Archive & Export
step "Archive"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
xcodebuild archive -quiet \
    -project BiteFM.xcodeproj -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates

step "Export (Developer ID)"
xcodebuild -exportArchive -quiet \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist Tools/ExportOptions.plist \
    -allowProvisioningUpdates

APP="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP" ] || die "Export lieferte keine $APP_NAME.app"
codesign --verify --deep --strict "$APP"

# ---------------------------------------------------------------- Notarisierung
notarize() { # $1 = Datei (zip oder dmg)
    local out
    out=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1) || true
    echo "$out"
    echo "$out" | grep -q "status: Accepted" || die "Notarisierung fehlgeschlagen (Log: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE)"
}

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    step "Notarisierung der App"
    ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    xcrun stapler staple "$APP"
    spctl -a -vv "$APP"
fi

# ---------------------------------------------------------------- DMG
step "DMG"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG="$BUILD_DIR/$DMG_NAME"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    step "Notarisierung der DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

# Archiv älterer Versionen (Releases/ ist gitignored)
mkdir -p "Releases/$VERSION"
cp -f "$DMG" "Releases/$VERSION/$DMG_NAME"
echo "Archiviert: Releases/$VERSION/$DMG_NAME"

# ---------------------------------------------------------------- Installieren
if [ "$INSTALL" -eq 1 ]; then
    step "Installation nach /Applications"
    if pgrep -x "$APP_NAME" >/dev/null; then
        osascript -e "quit app \"$APP_NAME\"" || true
        for _ in $(seq 1 20); do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.5; done
    fi
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP" "/Applications/$APP_NAME.app"
    echo "Installiert: /Applications/$APP_NAME.app ($VERSION)"
fi

# ---------------------------------------------------------------- Commit, Tag, GitHub
if [ "$BUILD_ONLY" -eq 1 ]; then
    step "Fertig (build-only): $DMG"
    exit 0
fi

trap - ERR
TAG="v$VERSION"
if [ "$ASSUME_YES" -eq 0 ]; then
    echo
    read -r -p "Commit, Tag $TAG, Push nach '$REMOTE' und GitHub-Release erstellen? [y/N] " answer
    if [[ ! "$answer" =~ ^[yY]$ ]]; then
        git checkout -- project.yml BiteFM.xcodeproj
        echo "Abgebrochen. Versionsänderung zurückgesetzt, DMG liegt in Releases/$VERSION/."
        exit 1
    fi
fi

step "Commit, Tag, Push"
git add project.yml BiteFM.xcodeproj/project.pbxproj
git commit -m "chore(release): v$VERSION"
git tag -a "$TAG" -m "BiteFM $VERSION"
git push "$REMOTE" main "$TAG"

step "GitHub-Release"
gh release create "$TAG" "$DMG" \
    --verify-tag --latest \
    --title "BiteFM $VERSION" \
    --notes-file "$NOTES_FILE"

step "Fertig: BiteFM $VERSION"
