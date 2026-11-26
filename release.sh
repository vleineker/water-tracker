#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Water Tracker"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
DIST_DIR="dist"

PUBLISH=1
for arg in "$@"; do
  case "$arg" in
    --no-publish) PUBLISH=0 ;;
  esac
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
  Resources/Info.plist)"
ZIP_NAME="$APP_NAME-$VERSION.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "==> Buildando $APP_NAME v$VERSION"
./build.sh

echo "==> Empacotando $ZIP_PATH"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent --sequesterRsrc "$INSTALL_DIR" "$ZIP_PATH"

echo "==> SHA-256"
shasum -a 256 "$ZIP_PATH"

if [ "$PUBLISH" -eq 0 ]; then
  echo "==> --no-publish: zip gerado, pulando gh release create"
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "==> gh nao autenticado, pulando gh release create"
  exit 0
fi

echo "==> Criando release v$VERSION"
gh release create "v$VERSION" "$ZIP_PATH" \
  --title "$APP_NAME v$VERSION" --notes-file - <<EOF
O que é: Water Tracker é um lembrete e tracker de água para a barra de menus
do macOS.

Como instalar: baixe o zip acima, descompacte e mova "Water Tracker.app" para
~/Applications (ou /Applications), depois abra. Detalhes do aviso de
segurança do macOS na primeira abertura: seção "Instalar" do README.
EOF
