#!/bin/bash
# Build MultiWindow (巨魔分屏) as a TrollStore-installable .tipa
# Uses Xcode toolchain directly; private frameworks are weak-linked via stubs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="MultiWindow"
BUNDLE_ID="com.ycwl.MultiWindow"
VERSION="$(awk -F': ' '/^Version:/{print $2}' control | tr -d '\r')"
TIPA_BASE="巨魔分屏-${VERSION}"
OUT_DIR="$ROOT/packages"

# Locate ldid (macOS build): PATH -> bundled tools/ -> auto-download
LDID_BIN="${LDID:-}"
if [[ -z "$LDID_BIN" ]]; then
    if command -v ldid >/dev/null 2>&1; then
        LDID_BIN="$(command -v ldid)"
    elif [[ -x "$ROOT/tools/ldid" ]]; then
        LDID_BIN="$ROOT/tools/ldid"
    else
        mkdir -p "$ROOT/tools"
        echo "Downloading ldid (macOS) ..." >&2
        curl -fsSL --max-time 120 \
            -o "$ROOT/tools/ldid" \
            'https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus8/ldid_macosx_x86_64'
        chmod +x "$ROOT/tools/ldid"
        LDID_BIN="$ROOT/tools/ldid"
    fi
fi

# Source files (same list as Makefile)
SOURCES=(
    AppDelegate.m
    AppSceneViewController.m
    DecoratedAppSceneView.m
    DecoratedFloatingView.m
    Hooks.m
    LauncherViewController.m
    MWLogViewerViewController.m
    PiPManager.m
    ResizeHandleView.m
    SceneDelegate.m
    ViewController.m
    main.m
)

SDK="$(xcrun -sdk iphoneos --show-sdk-path)"
BUILD_DIR="$ROOT/.build"
STAGE="$BUILD_DIR/Payload"
BIN="$BUILD_DIR/$APP_NAME"

mkdir -p "$STAGE/$APP_NAME.app" "$OUT_DIR"

echo "==> Compiling arm64 (iOS 15.0+) ..."
xcrun -sdk iphoneos clang \
    -arch arm64 \
    -miphoneos-version-min=15.0 \
    -isysroot "$SDK" \
    -fobjc-arc -fcommon -fmodules \
    -I. -F"$ROOT/stubs" \
    -Wno-everything \
    -framework UIKit -framework Foundation -framework AVKit -framework Security -framework CoreServices \
    -Wl,-weak_framework,FrontBoard \
    -Wl,-weak_framework,RunningBoardServices \
    -Wl,-undefined,dynamic_lookup \
    "${SOURCES[@]}" \
    -o "$BIN"

cp "$BIN" "$STAGE/$APP_NAME.app/$APP_NAME"
cp Resources/Info.plist "$STAGE/$APP_NAME.app/Info.plist"
cp Resources/AppIcon*.png "$STAGE/$APP_NAME.app/" 2>/dev/null || true
chmod 755 "$STAGE/$APP_NAME.app/$APP_NAME"

echo "==> Fakesigning with entitlements ..."
"$LDID_BIN" -S"$ROOT/entitlements.xml" "$STAGE/$APP_NAME.app/$APP_NAME"

# Sequence number: always create a new file, never overwrite an existing package
seq=1
while [[ -e "$OUT_DIR/${TIPA_BASE}-${seq}.tipa" ]]; do
    seq=$((seq + 1))
done
TIPA="$OUT_DIR/${TIPA_BASE}-${seq}.tipa"

echo "==> Packaging $TIPA ..."
# zip refuses to replace a pre-existing archive in the output dir (and direct
# writes there are blocked). Build the archive inside BUILD_DIR under a
# throwaway name, then move it into place.
ZIPSafe="$BUILD_DIR/.tipa-stage-$$.zip"
rm -f "$ZIPSafe"
(cd "$BUILD_DIR" && zip -qry "$(basename "$ZIPSafe")" Payload)
mv "$ZIPSafe" "$TIPA"

echo "==> Done: $TIPA"
ls -lh "$TIPA"
