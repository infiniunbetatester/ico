#!/usr/bin/env bash
set -e

echo "📦 Подготовка к созданию DMG для распространения..."

# Ensure ICO.app is built
if [ ! -d "ICO.app" ]; then
    echo "⚙️ ICO.app не найден, запускаем сборку..."
    ./build_app.sh
fi

DMG_NAME="ICO.dmg"
TEMP_DIR="dmg_temp"

rm -rf "$TEMP_DIR" "$DMG_NAME"
mkdir -p "$TEMP_DIR"

echo "📂 Подготовка содержимого DMG..."
cp -R "ICO.app" "$TEMP_DIR/"
ln -s /Applications "$TEMP_DIR/Applications"

echo "💿 Сборка образа диска ($DMG_NAME)..."
hdiutil create -volname "ICO" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_NAME"

rm -rf "$TEMP_DIR"

echo ""
echo "🎉 DMG готов к заливке на GitHub / отправке друзьям:"
echo "👉 $(pwd)/$DMG_NAME"
ls -lh "$DMG_NAME"
