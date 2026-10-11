#!/bin/bash
# Использование:
#   ./build.sh          — собрать build/NotchIsland.app
#   ./build.sh dev      — собрать и запустить для разработки (без установки и автозапуска, логи в терминале)
#   ./build.sh install  — собрать, заменить копию в /Applications и запустить её
#   ./build.sh dmg      — собрать установщик build/NotchIsland.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP="build/NotchIsland.app"
# универсальный бинарник (Apple Silicon + Intel); минимум macOS 13 задан в Package.swift
ARCHS=(--arch arm64 --arch x86_64)

build() {
  swift build -c release "${ARCHS[@]}"
  local bin
  bin="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/NotchIsland"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$bin" "$APP/Contents/MacOS/NotchIsland"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  codesign --force --deep --sign - "$APP"   # ad-hoc подпись, достаточно для локального использования
  echo "Собрано: $APP"
}

case "${1:-build}" in
  build)
    build
    ;;
  dev)
    pkill -x NotchIsland 2>/dev/null || true
    build
    exec "$APP/Contents/MacOS/NotchIsland" --dev
    ;;
  install)
    pkill -x NotchIsland 2>/dev/null || true
    build
    rm -rf /Applications/NotchIsland.app
    cp -R "$APP" /Applications/NotchIsland.app
    open /Applications/NotchIsland.app
    echo "Установлено и запущено: /Applications/NotchIsland.app"
    ;;
  dmg)
    build
    STAGE="build/dmg"
    DMG="build/NotchIsland.dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"   # ярлык для перетаскивания
    hdiutil create -volname "NotchIsland" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
    echo "Готово: $DMG"
    ;;
  *)
    echo "Неизвестная команда: $1"; exit 1
    ;;
esac
