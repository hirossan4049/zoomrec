#!/usr/bin/env bash
# ZoomRec リリーススクリプト
# Usage:
#   scripts/release.sh <semver>             # 完全フロー (build / tag / push / gh release)
#   scripts/release.sh <semver> --no-push   # ローカルでのみ DMG 生成とタグ付け
set -euo pipefail

VERSION="${1:-}"
SKIP_PUSH=false
for arg in "$@"; do
    case "$arg" in
        --no-push) SKIP_PUSH=true ;;
    esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    cat <<EOF >&2
使い方: $(basename "$0") <semver>             例: $(basename "$0") 0.1.0
        $(basename "$0") <semver> --no-push   タグ付けと DMG のみ (push しない)
EOF
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TAG="v$VERSION"

# --- Sanity checks --------------------------------------------------------
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ tag $TAG が既に存在します" >&2; exit 1
fi
if ! git diff --quiet HEAD; then
    echo "❌ コミットされていない変更があります:" >&2
    git status --short >&2
    exit 1
fi

# --- Bump version ---------------------------------------------------------
echo "▶ project.yml のバージョンを $VERSION に更新"
CURRENT_BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION/ {print $2; exit}' project.yml)
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' \
    -e "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" \
    -e "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" \
    project.yml

echo "▶ xcodegen"
xcodegen >/dev/null

# --- Build Release --------------------------------------------------------
echo "▶ Release ビルド"
BUILD="$ROOT/build"
rm -rf "$BUILD"
xcodebuild \
    -project zoomrec.xcodeproj \
    -scheme zoomrec \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD" \
    build 2>&1 | tail -3

APP="$BUILD/Build/Products/Release/ZoomRec.app"
[ -d "$APP" ] || { echo "❌ $APP が見つかりません" >&2; exit 1; }

# --- Create DMG -----------------------------------------------------------
echo "▶ DMG 作成"
DIST="$ROOT/dist"
mkdir -p "$DIST"
DMG="$DIST/ZoomRec-$VERSION.dmg"
rm -f "$DMG"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "ZoomRec $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null
SIZE=$(du -h "$DMG" | awk '{print $1}')
echo "   $DMG ($SIZE)"

# --- Commit & tag ---------------------------------------------------------
echo "▶ コミット + タグ"
git add project.yml zoomrec.xcodeproj
if ! git diff --cached --quiet; then
    git commit -m "Release $TAG"
fi
git tag -a "$TAG" -m "$TAG"

if [ "$SKIP_PUSH" = true ]; then
    cat <<EOF
✅ ローカルリリース完了。
   DMG: $DMG
   後で公開する場合:
     git push origin HEAD
     git push origin $TAG
     gh release create $TAG "$DMG" --title "ZoomRec $TAG" --notes-file <(git log ...)
EOF
    exit 0
fi

# --- Push & gh release ----------------------------------------------------
echo "▶ origin に push"
git push origin HEAD
git push origin "$TAG"

echo "▶ gh release create"
PREV_TAG=$(git tag --sort=-creatordate | grep -v "^$TAG$" | head -1 || true)
if [ -n "$PREV_TAG" ]; then
    NOTES=$(git log --pretty=format:'- %s' "$PREV_TAG..$TAG")
else
    NOTES=$(git log --pretty=format:'- %s' "$TAG")
fi
gh release create "$TAG" "$DMG" \
    --title "ZoomRec $TAG" \
    --notes "$NOTES"

URL=$(gh release view "$TAG" --json url -q .url)
echo "✅ 完了 — $URL"
