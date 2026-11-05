#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Gota"
BUNDLE_ID="com.vleineker.gota"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> Limpando build anterior"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Testes do núcleo primeiro: se algum falhar, o set -e para o build aqui.
./test.sh

compile_arch() {
  local target="$1"
  local output="$2"
  swiftc -parse-as-library -swift-version 5 -O -whole-module-optimization \
    -target "$target" -sdk "$SDK_PATH" \
    -framework SwiftUI -framework AppKit -framework UserNotifications -framework ServiceManagement \
    Sources/*.swift Sources/Core/*.swift -o "$output"
}

echo "==> Compilando (arm64)"
compile_arch "arm64-apple-macosx14.0" "$BUILD_DIR/$APP_NAME-arm64"

X86_OK=1
echo "==> Compilando (x86_64)"
if ! compile_arch "x86_64-apple-macosx14.0" "$BUILD_DIR/$APP_NAME-x86_64" \
  2>"$BUILD_DIR/x86_64-error.log"; then
  X86_OK=0
  echo "==> AVISO: build x86_64 falhou, binario sera so arm64:" >&2
  cat "$BUILD_DIR/x86_64-error.log" >&2
fi

echo "==> Gerando binario (universal se x86_64 compilou)"
if [ "$X86_OK" -eq 1 ]; then
  lipo -create -output "$APP_DIR/Contents/MacOS/$APP_NAME" \
    "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"
else
  cp "$BUILD_DIR/$APP_NAME-arm64" "$APP_DIR/Contents/MacOS/$APP_NAME"
fi

echo "==> Copiando Info.plist"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
mkdir -p "$APP_DIR/Contents/Resources/menubar"
cp Resources/menubar/*.svg "$APP_DIR/Contents/Resources/menubar/"
plutil -lint "$APP_DIR/Contents/Info.plist"

echo "==> Assinando (ad-hoc)"
codesign --force --sign - "$APP_DIR"

echo "==> Encerrando instância em execução"
pkill -x "$APP_NAME" || true

echo "==> Instalando em $INSTALL_DIR"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL_DIR"
ditto "$APP_DIR" "$INSTALL_DIR"

echo "==> Atualizando registro do LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR"

echo "==> Abrindo"
open "$INSTALL_DIR"

echo "==> Limpando build/"
rm -rf "$APP_DIR"

echo "==> Pronto: $INSTALL_DIR"
