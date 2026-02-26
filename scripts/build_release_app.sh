#!/bin/zsh
set -euo pipefail

APP_NAME="ytBatda"
PRODUCT_NAME="ytBatdaApp"
BUILD_DIR=".build"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_PATH="$MACOS_DIR/$APP_NAME"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ICON_SOURCE_PATH="${ICON_SOURCE_PATH:-icon.png}"
ICON_NAME="AppIcon"
ICON_ICNS_PATH="$RESOURCES_DIR/$ICON_NAME.icns"

swift build -c release --arch arm64 --arch x86_64

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

UNIVERSAL_BIN="$BUILD_DIR/apple/Products/Release/$PRODUCT_NAME"
ARM64_BIN="$BUILD_DIR/arm64-apple-macosx/release/$PRODUCT_NAME"
X86_64_BIN="$BUILD_DIR/x86_64-apple-macosx/release/$PRODUCT_NAME"

if [[ -f "$UNIVERSAL_BIN" ]]; then
  cp "$UNIVERSAL_BIN" "$BIN_PATH"
elif [[ -f "$ARM64_BIN" && -f "$X86_64_BIN" ]]; then
  lipo -create -output "$BIN_PATH" "$ARM64_BIN" "$X86_64_BIN"
elif [[ -f "$BUILD_DIR/release/$PRODUCT_NAME" ]]; then
  cp "$BUILD_DIR/release/$PRODUCT_NAME" "$BIN_PATH"
else
  echo "Could not find built executable for $PRODUCT_NAME" >&2
  exit 1
fi
chmod +x "$BIN_PATH"

if [[ -f "$ICON_SOURCE_PATH" ]]; then
  ICON_WORK_DIR="$(mktemp -d)"
  ICON_SQUARE_PATH="$ICON_WORK_DIR/icon-square.png"
  ICONSET_PATH="$ICON_WORK_DIR/$ICON_NAME.iconset"
  cp "$ICON_SOURCE_PATH" "$ICON_SQUARE_PATH"

  ICON_DIMENSIONS="$(sips -g pixelWidth -g pixelHeight "$ICON_SQUARE_PATH" | awk '/pixelWidth:/ {w=$2} /pixelHeight:/ {h=$2} END {print w " " h}')"
  ICON_WIDTH="${ICON_DIMENSIONS%% *}"
  ICON_HEIGHT="${ICON_DIMENSIONS##* }"
  if [[ "$ICON_WIDTH" != "$ICON_HEIGHT" ]]; then
    ICON_SIDE="$ICON_WIDTH"
    if (( ICON_HEIGHT > ICON_WIDTH )); then
      ICON_SIDE="$ICON_HEIGHT"
    fi
    sips --padToHeightWidth "$ICON_SIDE" "$ICON_SIDE" "$ICON_SQUARE_PATH" >/dev/null
  fi

  mkdir -p "$ICONSET_PATH"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SQUARE_PATH" --out "$ICONSET_PATH/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$ICON_SQUARE_PATH" --out "$ICONSET_PATH/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$ICONSET_PATH" -o "$ICON_ICNS_PATH"
  rm -rf "$ICON_WORK_DIR"
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.jonpurdy.ytbada</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.2</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

ARCH_INFO="$(lipo -info "$BIN_PATH")"
echo "$ARCH_INFO"
[[ "$ARCH_INFO" == *"x86_64"* ]] || { echo "Missing x86_64 slice" >&2; exit 1; }
[[ "$ARCH_INFO" == *"arm64"* ]] || { echo "Missing arm64 slice" >&2; exit 1; }

MIN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST_PATH")"
echo "LSMinimumSystemVersion=$MIN_VERSION"
[[ "$MIN_VERSION" == "14.0" ]] || { echo "Expected LSMinimumSystemVersion=14.0" >&2; exit 1; }

echo "Built and validated $APP_DIR"
