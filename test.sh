#!/bin/bash
# Compila e roda os testes do núcleo (Sources/Core) com swift-testing, sem Xcode.
# `swift test` não funciona com o Command Line Tools desta máquina, então o
# executável é montado direto pelo swiftc. Chamado pelo build.sh antes de compilar o app.
set -euo pipefail

cd "$(dirname "$0")"

DEV="$(xcode-select -p)"
if [ -d "$DEV/Library/Developer/Frameworks/Testing.framework" ]; then
  # Command Line Tools
  FRAMEWORKS="$DEV/Library/Developer/Frameworks"
  LIBS="$DEV/Library/Developer/usr/lib"
else
  # Xcode
  FRAMEWORKS="$DEV/Platforms/MacOSX.platform/Developer/Library/Frameworks"
  LIBS="$DEV/Platforms/MacOSX.platform/Developer/usr/lib"
fi
PLUGINS="$(dirname "$(xcrun -f swiftc)")/../lib/swift/host/plugins/testing"

OUT="build/GotaTests"
mkdir -p build

echo "==> Compilando testes"
swiftc -parse-as-library -swift-version 5 \
  -F "$FRAMEWORKS" -plugin-path "$PLUGINS" -framework Testing \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBS" \
  Sources/Core/*.swift Tests/*.swift -o "$OUT"

echo "==> Rodando testes"
"$OUT"
