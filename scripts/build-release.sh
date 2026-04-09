#!/bin/bash
set -euo pipefail

#───────────────────────────────────────────────────────────────
# SlapMac – Local Build & Release Script
#
# Usage:
#   ./scripts/build-release.sh <version>
#   Example: ./scripts/build-release.sh 1.0.0
#
# Prerequisites:
#   - Xcode + command-line tools
#   - gh CLI (authenticated)
#   - Sparkle keys in Keychain (run generate_keys once)
#───────────────────────────────────────────────────────────────

VERSION="${1:?Usage: $0 <version>  (e.g. 1.0.0)}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/SlapMac/SlapMac.xcodeproj"
SCHEME="SlapMac"
BUILD_DIR="$REPO_ROOT/build/release"
DMG_NAME="SlapMac-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
APP_PATH="$BUILD_DIR/SlapMac.app"
ARCHIVE_PATH="$BUILD_DIR/SlapMac.xcarchive"
SPARKLE_TOOLS="$REPO_ROOT/.sparkle-tools/bin"
GH="${GH_PATH:-/opt/homebrew/bin/gh}"

echo "🔨 Building SlapMac v${VERSION}..."
echo ""

# ── Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Archive
echo "📦 Archiving..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -5

# ── Extract .app from archive
echo "📂 Extracting .app..."
cp -R "$ARCHIVE_PATH/Products/Applications/SlapMac.app" "$APP_PATH"

# ── Ad-hoc codesign (required for Sparkle to work)
echo "🔐 Ad-hoc signing..."
codesign --force --deep --sign - "$APP_PATH"

# ── Create DMG
echo "💿 Creating DMG..."
hdiutil create \
    -volname "SlapMac" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "✅ DMG created: $DMG_PATH"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"

# ── Sign update with Sparkle EdDSA
echo ""
echo "🔏 Signing with Sparkle EdDSA..."
SIGNATURE_INFO=$("$SPARKLE_TOOLS/sign_update" "$DMG_PATH")
echo "   Signature: $SIGNATURE_INFO"

# Extract edSignature and length for appcast
ED_SIGNATURE=$(echo "$SIGNATURE_INFO" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
FILE_LENGTH=$(stat -f%z "$DMG_PATH")

echo ""
echo "📋 Appcast item info:"
echo "   edSignature: $ED_SIGNATURE"
echo "   length: $FILE_LENGTH"

# ── Generate appcast.xml
APPCAST_PATH="$BUILD_DIR/appcast.xml"
PUB_DATE=$(date -R)

cat > "$APPCAST_PATH" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>SlapMac Updates</title>
    <link>https://tzxh45dhff-art.github.io/SlapMac/appcast.xml</link>
    <description>Most recent updates to SlapMac</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>SlapMac v${VERSION}</h2>
        <ul>
          <li>Latest release</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/tzxh45dhff-art/SlapMac/releases/download/v${VERSION}/${DMG_NAME}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${FILE_LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "📝 Appcast written to: $APPCAST_PATH"

# ── Create GitHub Release
echo ""
echo "🚀 Creating GitHub Release v${VERSION}..."
"$GH" release create "v${VERSION}" \
    "$DMG_PATH" \
    --repo "tzxh45dhff-art/SlapMac" \
    --title "SlapMac v${VERSION}" \
    --notes "## SlapMac v${VERSION}

### Download
Download **${DMG_NAME}** below and drag SlapMac.app to your Applications folder.

> **Note**: Since this app is not notarized, you'll need to right-click → Open on first launch.

### What's new
- Latest release" \
    --latest

echo "✅ Release created!"

# ── Update gh-pages with appcast.xml
echo ""
echo "🌐 Updating appcast.xml on GitHub Pages..."

# Clone gh-pages branch to a temp dir
PAGES_DIR="$BUILD_DIR/gh-pages"
git clone --branch gh-pages --single-branch --depth 1 \
    "https://github.com/tzxh45dhff-art/SlapMac.git" "$PAGES_DIR" 2>/dev/null || {
    # If gh-pages doesn't exist yet, create it
    mkdir -p "$PAGES_DIR"
    cd "$PAGES_DIR"
    git init
    git checkout -b gh-pages
    git remote add origin "https://github.com/tzxh45dhff-art/SlapMac.git"
}

cp "$APPCAST_PATH" "$PAGES_DIR/appcast.xml"
cd "$PAGES_DIR"
git add appcast.xml
git commit -m "Update appcast.xml for v${VERSION}" || true
git push origin gh-pages --force

echo ""
echo "════════════════════════════════════════════════"
echo "  🎉 SlapMac v${VERSION} released successfully!"
echo ""
echo "  📥 Download: https://github.com/tzxh45dhff-art/SlapMac/releases/tag/v${VERSION}"
echo "  🔄 Appcast:  https://tzxh45dhff-art.github.io/SlapMac/appcast.xml"
echo "════════════════════════════════════════════════"
