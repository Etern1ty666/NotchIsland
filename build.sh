#!/bin/bash
# Использование:
#   ./build.sh                 — собрать build/NotchIsland.app
#   ./build.sh dev             — собрать и запустить для разработки (без установки и автозапуска, логи в терминале)
#   ./build.sh install         — собрать, заменить копию в /Applications и запустить её
#   ./build.sh dmg             — собрать установщик build/NotchIsland.dmg
#   ./build.sh release 1.2     — выпустить версию 1.2: собрать, подписать, сделать дельты от прошлых версий,
#                                обновить appcast.xml и залить всё на сервер вместе с установщиком
set -euo pipefail
cd "$(dirname "$0")"

APP="build/NotchIsland.app"
DMG="build/NotchIsland.dmg"
# универсальный бинарник (Apple Silicon + Intel); минимум macOS 13 задан в Package.swift
ARCHS=(--arch arm64 --arch x86_64)
SPARKLE=".build/artifacts/sparkle/Sparkle"
# секретный ключ подписи обновлений (копия из связки ключей, создан generate_keys --account notchisland)
KEY="$HOME/.config/notchisland/sparkle_private_key"
# копия папки обновлений с сервера: прошлые версии нужны, чтобы считать дельты
RELEASES="releases"
# DEPLOY=user@host:/путь — куда заливать обновления (файл не в git)
CONF="release.env"

build() {
  swift build -c release "${ARCHS[@]}"
  local bin
  bin="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/NotchIsland"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
  cp "$bin" "$APP/Contents/MacOS/NotchIsland"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  chmod -R u+rwX,go+rX "$APP"   # файлы приложения читают все пользователи Mac
  codesign --force --deep --sign - "$APP"   # ad-hoc подпись, достаточно для локального использования
  echo "Собрано: $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist))"
}

make_dmg() {
  local stage="build/dmg"
  rm -rf "$stage" "$DMG"
  mkdir -p "$stage"
  cp -R "$APP" "$stage/"
  ln -s /Applications "$stage/Applications"   # ярлык для перетаскивания
  hdiutil create -volname "NotchIsland" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$stage"
  echo "Готово: $DMG"
}

release() {
  local version="${1:-}"
  [ -n "$version" ] || { echo "Укажи версию: ./build.sh release 1.2"; exit 1; }
  [ -f "$CONF" ] || { echo "Нет $CONF со строкой DEPLOY=user@host:/путь"; exit 1; }
  # shellcheck disable=SC1090
  source "$CONF"
  [ -f "$KEY" ] || { echo "Нет ключа подписи $KEY"; exit 1; }
  local host="${DEPLOY%%:*}" dir="${DEPLOY#*:}"
  local feed url
  feed=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" Resources/Info.plist)
  url="${feed%/*}/"

  # прошлые версии — с сервера; установщик и страница лежат отдельно
  mkdir -p "$RELEASES"
  rsync -az --exclude download/ --exclude index.html "$DEPLOY/" "$RELEASES/"
  local zip="$RELEASES/NotchIsland-$version.zip"
  [ ! -e "$zip" ] || { echo "Версия $version уже выпущена"; exit 1; }

  # версию видят Sparkle и меню приложения
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
                          -c "Set :CFBundleVersion $version" Resources/Info.plist
  build
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$zip"
  # подписывает архив, считает дельты от прошлых версий и дописывает appcast.xml
  "$SPARKLE/bin/generate_appcast" --ed-key-file "$KEY" --download-url-prefix "$url" "$RELEASES"
  make_dmg

  ssh "$host" "mkdir -p '$dir/download'"
  rsync -az --delete --exclude download/ --exclude index.html "$RELEASES/" "$DEPLOY/"
  rsync -az "$DMG" "$DEPLOY/download/NotchIsland.dmg"
  rsync -az Server/index.html "$DEPLOY/index.html"
  echo "Выпущена версия $version"
  echo "  обновления: $feed"
  echo "  установщик: ${url}download/NotchIsland.dmg"
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
    make_dmg
    ;;
  release)
    release "${2:-}"
    ;;
  *)
    echo "Неизвестная команда: $1"; exit 1
    ;;
esac
