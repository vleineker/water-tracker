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
plutil -lint "$APP_DIR/Contents/Info.plist"

# O app instalado roda o ajudante daqui, sem depender do clone do repo (issue #8).
# Só as dependências de produção entram. Sem npm e sem garmin/node_modules, o app
# compila mesmo assim e, com o Garmin ligado, mostra que falta o ajudante.
echo "==> Copiando o ajudante do Garmin"
HELPER_DIR="$APP_DIR/Contents/Resources/garmin"
if [ ! -d garmin/node_modules ] && command -v npm >/dev/null; then
  (cd garmin && npm ci --omit=dev --no-audit --no-fund)
fi
if [ -d garmin/node_modules ]; then
  mkdir -p "$HELPER_DIR"
  cp garmin/gota-garmin.mjs garmin/package.json garmin/package-lock.json "$HELPER_DIR/"
  ditto garmin/node_modules "$HELPER_DIR/node_modules"
  if command -v npm >/dev/null; then
    (cd "$HELPER_DIR" && npm prune --omit=dev --no-audit --no-fund >/dev/null)
  fi
  rm -rf "$HELPER_DIR/node_modules/.bin" "$HELPER_DIR/node_modules/.package-lock.json"
else
  echo "==> AVISO: sem garmin/node_modules nem npm; o .app vai sem o ajudante do Garmin" >&2
fi

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
