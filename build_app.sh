#!/usr/bin/env bash
set -e

echo "🔨 Сборка ICO..."
swift build -c release

APP_DIR="ICO.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

cp ".build/release/ICO" "$MACOS_DIR/ICO"

# Copy resources and frameworks into bundle
if [ -d "Resources" ]; then
    cp -R Resources/* "$RESOURCES_DIR/" 2>/dev/null || true
fi

if [ -d "Frameworks" ]; then
    cp -R Frameworks/* "$FRAMEWORKS_DIR/" 2>/dev/null || true
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ICO</string>
    <key>CFBundleIdentifier</key>
    <string>com.ico.app</string>
    <key>CFBundleName</key>
    <string>ICO</string>
    <key>CFBundleDisplayName</key>
    <string>ICO</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.4</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>ICO требуется доступ к аудио для регулировки громкости отдельных приложений.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ICO требуется доступ к экрану для оптического распознавания текста (OCR).</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>ICO требуется доступ к аудиосистеме для микшера громкости.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ICO требуется доступ к AppleEvents для интеграции с медиаплеерами.</string>
</dict>
</plist>
EOF

echo "🔏 Подписание приложения (Ad-Hoc для сохранения разрешений TCC)..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Приложение готово: $APP_DIR"
